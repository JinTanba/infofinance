// SPDX-License-Identifier: MIT
pragma solidity ^0.5.1;
pragma experimental ABIEncoderV2;

import {Address} from "openzeppelin-solidity/contracts/utils/Address.sol";
import { CTHelpers } from "conditional-tokens/contracts/CTHelpers.sol";
import { ERC20 } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ConditionalTokens } from "./CTF.sol";
import { FPMMDeterministicFactory } from "./Factory.sol";

/**
 * @title Resolver
 * @notice A contract to orchestrate market preparation and oracle setup
 *         for Gnosis Conditional Tokens and a Fixed Product Market Maker (FPMM).
 */
contract Resolver {
    using Address for address;

    // ----------------------------------------
    // Events
    // ----------------------------------------
    event MarketPreparation(
        uint256 fee,
        string title,
        string image,
        string description,
        address[] whitelist,
        uint256 outComeSlotCount,
        address collateralTokenAddress,
        address conditionalTokensAddress,
        uint256 deadline,
        bytes32 indexed marketId,
        uint256 indexed universalId,
        address indexed marketCreatorAddress
    );

    event OracleSet(
        uint256 universalId,
        address indexed oracle,
        address indexed fpmmAddress,
        bytes32 indexed questionId,
        uint256 oracleFee
    );

    // ----------------------------------------
    // Storage
    // ----------------------------------------
    address public conditionalTokensAddress;
    address public factoryAddress;
    address public bondingCurveAddress;

    uint256 public universalId;

    mapping(uint256 => MarketData) public marketData;
    mapping(bytes32 => address[]) public oracleList;
    mapping(bytes32 => address) public fpmmAddressList;

    struct MarketData {
        uint256 fee;
        string title;
        string image;
        string description;
        address[] whitelist;
        uint256 outComeSlotCount;
        address collateralTokenAddress;
        address conditionalTokensAddress;
        uint256 deadline;
    }

    

    constructor(
        address _conditionalTokensAddress,
        address _factoryAddress,
        address _bondingCurveAddress
    ) public {
        conditionalTokensAddress = _conditionalTokensAddress;
        factoryAddress = _factoryAddress;
        bondingCurveAddress = _bondingCurveAddress;
    }


    /**
     * @dev Create a new market with specified parameters.
     * @param fee                   The market fee to be used by the FPMM (basis points or other format).
     * @param title                 Short name for the market.
     * @param image                 Image or IPFS link describing the market.
     * @param description           Textual description of the market.
     * @param whitelist             Array of addresses permitted to call setOracle (if non-empty).
     * @param outComeSlotCount      Number of possible outcomes for the market.
     * @param _collateralToken      The address of the ERC20 token used as collateral.
     * @param deadline              Time by which new oracles must be set (unix timestamp).
     * @return marketId             A keccak256 hash identifying the market.
     */
    function prepareMarket(
        uint256 fee,
        string memory title,
        string memory image,
        string memory description,
        address[] memory whitelist,
        uint256 outComeSlotCount,
        address _collateralToken,
        uint256 deadline
    )
        public
        returns (bytes32 marketId)
    {
        require(outComeSlotCount > 0, "outComeSlotCount must be > 0");
        require(deadline > block.timestamp, "Deadline must be in the future");
        require(_collateralToken != address(0), "Invalid collateralToken address");
        require(_collateralToken.isContract(), "collateralTokenAddress not a contract");

        universalId++;

        MarketData memory info = MarketData({
            fee: fee,
            title: title,
            image: image,
            description: description,
            whitelist: whitelist,
            outComeSlotCount: outComeSlotCount,
            collateralTokenAddress: _collateralToken,
            conditionalTokensAddress: conditionalTokensAddress,
            deadline: deadline
        });

        marketData[universalId] = info;
        marketId = getMarketId(universalId);

        emit MarketPreparation(
            fee,
            title,
            image,
            description,
            whitelist,
            outComeSlotCount,
            _collateralToken,
            conditionalTokensAddress,
            deadline,
            marketId,
            universalId,
            msg.sender
        );
    }

    /**
     * @dev Sets the oracle for a given market and deploys the associated FPMM contract.
     *      Checks whitelisting (if applicable) and ensures it is called before `deadline`.
     * @param _universalId  The universal market ID.
     * @param oracleFee     Additional fee parameter for the FPMM, presumably for the oracle.
     * @return exchangeAddress The address of the newly created FPMM contract.
     */
    function setOracle(
        uint256 _universalId,
        uint256 oracleFee
    )
        external
        returns (address exchangeAddress)
    {
        MarketData memory info = marketData[_universalId];

        // Ensure market is valid
        require(info.outComeSlotCount > 0, "Market does not exist");


        require(block.timestamp <= info.deadline, "Cannot set oracle after deadline");

        // If a whitelist is provided, ensure the caller is whitelisted
        if (info.whitelist.length > 0) {
            bool isWhitelisted = false;
            for (uint256 i = 0; i < info.whitelist.length; i++) {
                if (info.whitelist[i] == msg.sender) {
                    isWhitelisted = true;
                    break;
                }
            }
            require(isWhitelisted, "You are not whitelisted");
        }

        // Prepare condition in Conditional Tokens
        ConditionalTokens ctf = ConditionalTokens(info.conditionalTokensAddress);
        bytes32 questionId = getQuestionId(_universalId, msg.sender);

        // Prevent setting the same oracle multiple times for the same market
        // (questionId => FPMM address). If it’s non-zero, it’s already set.
        require(fpmmAddressList[questionId] == address(0), "Oracle already set for this market");

        ctf.prepareCondition(msg.sender, questionId, info.outComeSlotCount);

        // Build the conditionIds array (currently only one condition)
        bytes32[] memory conditionIds = new bytes32[](1);
        conditionIds[0] = CTHelpers.getConditionId(msg.sender, questionId, info.outComeSlotCount);

        // Record the oracle
        oracleList[getMarketId(_universalId)].push(msg.sender);

        // Create the FPMM
        exchangeAddress = address(FPMMDeterministicFactory(factoryAddress).create2FixedProductMarketMaker(
            2,
            ConditionalTokens(info.conditionalTokensAddress),
            IERC20(info.collateralTokenAddress),
            conditionIds,
            info.fee,
            oracleFee,
            msg.sender,
            bondingCurveAddress
        ));

        fpmmAddressList[questionId] = exchangeAddress;

        emit OracleSet(_universalId, msg.sender, exchangeAddress, questionId, oracleFee);
    }

    // ----------------------------------------
    // View Functions
    // ----------------------------------------

    /**
     * @dev Returns a unique keccak256 market ID for the given universalId + metadata.
     */
    function getMarketId(uint256 _universalId) public view returns (bytes32) {
        MarketData memory info = marketData[_universalId];
        bytes memory encodedMarketData = abi.encodePacked(
            info.title,
            info.description,
            info.image,
            info.whitelist,
            info.outComeSlotCount,
            info.collateralTokenAddress,
            info.conditionalTokensAddress,
            info.fee,
            info.deadline
        );
        return keccak256(abi.encodePacked(_universalId, encodedMarketData));
    }

    /**
     * @dev Returns the questionId for a given market & oracle address.
     */
    function getQuestionId(uint256 _universalId, address oracle) public view returns (bytes32) {
        return keccak256(abi.encodePacked(getMarketId(_universalId), oracle));
    }

    /**
     * @dev Returns the conditionId derived from the questionId and outcome slot count.
     */
    function getConditionId(uint256 _universalId, address oracle) public view returns (bytes32) {
        return CTHelpers.getConditionId(
            oracle,
            getQuestionId(_universalId, oracle),
            marketData[_universalId].outComeSlotCount
        );
    }

    /**
     * @dev Returns the FPMM address for a given market and oracle, if set.
     */
    function getFPMMAddress(uint256 _universalId, address oracle) public view returns (address) {
        return fpmmAddressList[getQuestionId(_universalId, oracle)];
    }

    /**
     * @dev Returns the list of oracle addresses for a given market ID.
     */
    function getOracleList(uint256 _universalId) public view returns (address[] memory) {
        return oracleList[getMarketId(_universalId)];
    }

    /**
     * @dev Returns the MarketData struct for a given _universalId.
     */
    function getMarketData(uint256 _universalId) public view returns (MarketData memory) {
        return marketData[_universalId];
    }
}

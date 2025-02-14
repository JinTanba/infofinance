// SPDX-License-Identifier: MIT
pragma solidity ^0.5.1;

import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ConditionalTokens } from "./CTF.sol";
import { CTHelpers } from "conditional-tokens/contracts/CTHelpers.sol";
import { Create2CloneFactory } from "conditional-tokens-market-makers/contracts/Create2CloneFactory.sol";
import { FixedProductMarketMaker, FixedProductMarketMakerData } from "./AMM.sol";
import { ERC1155TokenReceiver } from "conditional-tokens/contracts/ERC1155/ERC1155TokenReceiver.sol";
import { console } from "forge-std/console.sol";
import { Strings } from 'openzeppelin-solidity/contracts/drafts/Strings.sol';

/**
 * @dev Adjusted factory compatible with the new FPMM.
 *      Note that we have removed `oracleFee` and instead added `bondingCurveAddress`.
 */
contract FPMMDeterministicFactory is Create2CloneFactory, FixedProductMarketMakerData, ERC1155TokenReceiver {

    event FixedProductMarketMakerCreation(
        address indexed creator,
        FixedProductMarketMaker fixedProductMarketMaker,
        ConditionalTokens conditionalTokens,
        IERC20 collateralToken,
        bytes32[] conditionIds,
        uint fee,
        address bondingCurveAddress
    );

    FixedProductMarketMaker public implementationMaster;
    address internal currentFunder;

    constructor() public {
        implementationMaster = new FixedProductMarketMaker();
        
    }

    /**
     * @dev This function is called on the freshly cloned contract to set up its storage
     *      to match the new FPMM's parameters: 
     *      (ConditionalTokens, IERC20, bytes32[], uint, uint[], uint, uint, address, address).
     */
    function cloneConstructor(bytes calldata consData) external {
        (
            ConditionalTokens _conditionalTokens,
            IERC20 _collateralToken,
            bytes32[] memory _conditionIds,
            uint _fee,
            uint _oracleFee,
            address _oracle,
            address _bondingCurveAddress
        ) = abi.decode(consData, (ConditionalTokens, IERC20, bytes32[], uint, uint, address, address));
        
        // Register ERC1155 receiver interfaces
        _supportedInterfaces[_INTERFACE_ID_ERC165] = true;
        _supportedInterfaces[
            ERC1155TokenReceiver(0).onERC1155Received.selector ^
            ERC1155TokenReceiver(0).onERC1155BatchReceived.selector
        ] = true;
        
        // Store data into this proxy's storage
        conditionalTokens = _conditionalTokens;
        collateralToken = _collateralToken;
        conditionIds = _conditionIds;
        fee = _fee;
        oracleFee = _oracleFee;
        oracle = _oracle;
        bondingCurveAddress = _bondingCurveAddress;

        
        

        uint atomicOutcomeSlotCount = 1;
        outcomeSlotCounts = new uint[](conditionIds.length);
        for (uint i = 0; i < conditionIds.length; i++) {
            uint outcomeSlotCount = conditionalTokens.getOutcomeSlotCount(conditionIds[i]);
            atomicOutcomeSlotCount *= outcomeSlotCount;
            outcomeSlotCounts[i] = outcomeSlotCount;
            
        }

        
        require(atomicOutcomeSlotCount > 1, "conditions must be valid");

        collectionIds = new bytes32[][](conditionIds.length);
        _recordCollectionIDsForAllConditions(conditionIds.length, bytes32(0));
        require(positionIds.length == atomicOutcomeSlotCount, "position IDs construction failed!?");
    }

    function _recordCollectionIDsForAllConditions(uint conditionsLeft, bytes32 parentCollectionId) private {
        if(conditionsLeft == 0) {
            uint positionId = CTHelpers.getPositionId(collateralToken, parentCollectionId);
            positionIds.push(positionId);
            return;
        }
        conditionsLeft--;

        uint outcomeSlotCount = outcomeSlotCounts[conditionsLeft];
        collectionIds[conditionsLeft].push(parentCollectionId);
        for(uint i = 0; i < outcomeSlotCount; i++) {
            bytes32 collectionId = CTHelpers.getCollectionId(
                parentCollectionId,
                conditionIds[conditionsLeft],
                1 << i
            );

            _recordCollectionIDsForAllConditions(
                conditionsLeft,
                collectionId
            );
        }
    }

    /**
     * @dev If the newly cloned market maker ever receives ERC1155 from 
     *      itself (for merges/splits), forward them back to the current funder.
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        external
        returns (bytes4)
    {
        ConditionalTokens(msg.sender).safeTransferFrom(address(this), currentFunder, id, value, data);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        external
        returns (bytes4)
    {
        ConditionalTokens(msg.sender).safeBatchTransferFrom(address(this), currentFunder, ids, values, data);
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Creates a new FPMM clone with the given parameters, 
     *      including initial funding. Parameters include:
     *      saltNonce, conditionalTokens, collateralToken, conditionIds, fee,
     *      initialFunds, distributionHint, oracleFee, oracle, and bondingCurveAddress.
     */
    function create2FixedProductMarketMaker(
        uint saltNonce,
        ConditionalTokens _conditionalTokens,
        IERC20 _collateralToken,
        bytes32[] calldata _conditionIds,
        uint _fee,
        uint _oracleFee,
        address _oracle,
        address _bondingCurveAddress
    )
        external
        returns (FixedProductMarketMaker)
    {
        // Deploy clone via create2 using our new constructor data:
        FixedProductMarketMaker fixedProductMarketMaker = FixedProductMarketMaker(
            create2Clone(
                address(implementationMaster),
                saltNonce,
                abi.encode(
                    _conditionalTokens,
                    _collateralToken,
                    _conditionIds,
                    _fee,
                    _oracleFee,
                    _oracle,
                    _bondingCurveAddress
                )
            )
        );
        // Emit creation event with new signature
        emit FixedProductMarketMakerCreation(
            msg.sender,
            fixedProductMarketMaker,
            _conditionalTokens,
            _collateralToken,
            _conditionIds,
            _fee,
            _bondingCurveAddress
        );
        return fixedProductMarketMaker;
    }
}

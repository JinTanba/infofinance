pragma solidity ^0.5.1;

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ConditionalTokens } from "./CTF.sol";
import { ERC1155TokenReceiver } from "@gnosis.pm/conditional-tokens-contracts/contracts/ERC1155/ERC1155TokenReceiver.sol";
import { ERC20 } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { BondingCurve } from "./BondingCurve.sol";
import { console } from "forge-std/console.sol";
import { Strings } from "openzeppelin-solidity/contracts/drafts/Strings.sol";
/**
 * @title CeilDiv
 * @dev Library for computing division and rounding up.
 */
library CeilDiv {
    /**
     * @notice Calculates ceil(x / y).
     * @param x Numerator.
     * @param y Denominator.
     * @return The result of x / y, rounded up.
     */
    function ceildiv(uint x, uint y) internal pure returns (uint) {
        if (x > 0) return ((x - 1) / y) + 1;
        return x / y;
    }
}

/**
 * @title FixedProductMarketMaker
 * @dev A fixed product market maker contract using ERC20-style shares and conditional tokens.
 */
contract FixedProductMarketMaker is ERC20, ERC1155TokenReceiver {
    using SafeMath for uint;
    using CeilDiv for uint;

    uint constant ONE = 10**18;

    ConditionalTokens public conditionalTokens;
    IERC20 public collateralToken;
    bytes32[] public conditionIds;

    // Trading fee fraction in 1e18 units (e.g., 5e16 = 5%)
    uint public fee;

    // Accumulates *all* fee collateral from trades
    uint internal feePoolWeight;

    // [ADDED] Oracle-related variables
    address public oracle;      // address allowed to claim oracleFee
    uint public oracleFee;      // fraction (in 1e18) of feePoolWeight the oracle can claim
    bool public oracleFeePaid;  // tracks whether the oracle fee has been paid out

    uint[] outcomeSlotCounts;
    bytes32[][] collectionIds;
    uint[] positionIds;
    address public bondingCurveAddress;

    event FPMMFundingAdded(
        address indexed funder,
        uint[] amountsAdded,
        uint sharesMinted
    );
    event FPMMFundingRemoved(
        address indexed funder,
        uint[] amountsRemoved,
        uint collateralRemovedFromFeePool,
        uint sharesBurnt
    );
    event FPMMBuy(
        address indexed buyer,
        uint investmentAmount,
        uint feeAmount,
        uint indexed outcomeIndex,
        uint outcomeTokensBought
    );
    event FPMMSell(
        address indexed seller,
        uint returnAmount,
        uint feeAmount,
        uint indexed outcomeIndex,
        uint outcomeTokensSold
    );

    /**
     * @notice Checks if the market is resolved by verifying that `payoutDenominator` is nonzero for all conditions.
     * @return True if the market is resolved, false otherwise.
     */
    function isMarketResolved() public view returns (bool) {
        for (uint i = 0; i < conditionIds.length; i++) {
            if (conditionalTokens.payoutDenominator(conditionIds[i]) == 0) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Retrieves the pool's balances of each outcome token.
     * @return An array of balances corresponding to each position.
     */
    function getPoolBalances() private view returns (uint[] memory) {
        address[] memory thises = new address[](positionIds.length);
        for (uint i = 0; i < positionIds.length; i++) {
            thises[i] = address(this);
        }
        return conditionalTokens.balanceOfBatch(thises, positionIds);
    }

    /**
     * @notice Creates a basic partition array where each element represents a single outcome bit.
     * @param outcomeSlotCount The number of outcomes.
     * @return partition An array with one bit set per outcome.
     */
    function generateBasicPartition(uint outcomeSlotCount)
        private
        pure
        returns (uint[] memory partition)
    {
        partition = new uint[](outcomeSlotCount);
        for (uint i = 0; i < outcomeSlotCount; i++) {
            partition[i] = 1 << i;
        }
    }

    /**
     * @notice Splits collateral positions for all conditions, creating outcome tokens for each condition.
     * @param amount The amount of collateral to split.
     */
    function splitPositionThroughAllConditions(uint amount) private {
        for (uint i = conditionIds.length - 1; int(i) >= 0; i--) {
            uint[] memory partition = generateBasicPartition(outcomeSlotCounts[i]);
            for (uint j = 0; j < collectionIds[i].length; j++) {
                conditionalTokens.splitPosition(
                    collateralToken,
                    collectionIds[i][j],
                    conditionIds[i],
                    partition,
                    amount
                );
            }
        }
    }

    /**
     * @notice Merges outcome tokens for all conditions back into collateral tokens.
     * @param amount The amount of outcome tokens to merge.
     */
    function mergePositionsThroughAllConditions(uint amount) private {
        for (uint i = 0; i < conditionIds.length; i++) {
            uint[] memory partition = generateBasicPartition(outcomeSlotCounts[i]);
            for (uint j = 0; j < collectionIds[i].length; j++) {
                conditionalTokens.mergePositions(
                    collateralToken,
                    collectionIds[i][j],
                    conditionIds[i],
                    partition,
                    amount
                );
            }
        }
    }

    /**
     * @notice Returns the total fees accumulated so far.
     * @return The current value of the fee pool weight.
     */
    function collectedFees() external view returns (uint) {
        return feePoolWeight;
    }

    /**
     * @notice Internal function that pays out the oracle fee one time if the market is resolved and not yet paid.
     */
    function _payOracleFee() internal {
        if (!oracleFeePaid) {
            // Calculate the oracle's share
            uint oracleShare = feePoolWeight.mul(oracleFee).div(ONE);
            // Deduct from the fee pool
            feePoolWeight = feePoolWeight.sub(oracleShare);
            // Transfer to the oracle
            require(collateralToken.transfer(oracle, oracleShare), "Oracle fee transfer failed");
            // Mark as paid
            oracleFeePaid = true;
        }
    }

    function redeemFees() external {
        require(isMarketResolved(), "Market not resolved yet");

        _payOracleFee();

        uint holderBalance = balanceOf(msg.sender);
        require(holderBalance > 0, "No liquidity tokens");

        uint holderShare = feePoolWeight.mul(holderBalance).div(totalSupply());
        _burn(msg.sender, holderBalance);
        feePoolWeight = feePoolWeight.sub(holderShare);

        require(collateralToken.transfer(msg.sender, holderShare), "Fee transfer failed");
    }

    /**
     * @notice Allows a user to add collateral funding to the market maker, minting share tokens in return.
     * @param addedFunds The amount of collateral to add.
     */
    function addFunding(uint addedFunds) external {
        
        require(addedFunds > 0, "funding must be non-zero");
        require(collateralToken.transferFrom(msg.sender, address(this), addedFunds), "funding transfer failed");
        require(collateralToken.approve(address(conditionalTokens), addedFunds), "approval for splits failed");
        
        splitPositionThroughAllConditions(addedFunds);
        
        uint mintedAmount = addedFunds;
        
        
        
        
        
        
        
        
        
        
        uint cost = BondingCurve(bondingCurveAddress).calculateCost(addedFunds, totalSupply());
        
        _mint(msg.sender, cost);
        
        


        uint[] memory sendBackAmounts = new uint[](positionIds.length);
        emit FPMMFundingAdded(msg.sender, sendBackAmounts, mintedAmount);
    }

    /**
     * @notice Removing funding is disabled in this contract. This function reverts on call.
     * @param sharesToBurn The intended share tokens to burn.
     */
    function removeFunding(uint sharesToBurn) external {
        revert("removeFunding disabled");
    }

    /**
     * @notice ERC1155 single transfer hook. Accepts transfers only if the operator is this contract. Otherwise rejects.
     */
    function onERC1155Received(
        address operator,
        address /* from */,
        uint256 /* id */,
        uint256 /* value */,
        bytes calldata /* data */
    )
        external
        returns (bytes4)
    {
        if (operator == address(this)) {
            return this.onERC1155Received.selector;
        }
        return 0x0; // rejects external transfers
    }

    /**
     * @notice ERC1155 batch transfer hook. Accepts batch transfers only if operator is this contract and from is address(0). Otherwise rejects.
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata /* ids */,
        uint256[] calldata /* values */,
        bytes calldata /* data */
    )
        external
        returns (bytes4)
    {
        if (operator == address(this) && from == address(0)) {
            return this.onERC1155BatchReceived.selector;
        }
        return 0x0;
    }

    /**
     * @notice Calculates how many outcome tokens can be bought with a given investment, accounting for fees.
     * @param investmentAmount The total amount of collateral intended for the purchase.
     * @param outcomeIndex The index of the outcome to be bought.
     * @return The number of outcome tokens that can be purchased.
     */
    function calcBuyAmount(uint investmentAmount, uint outcomeIndex) public view returns (uint) {
        require(outcomeIndex < positionIds.length, "invalid outcome index");
        uint[] memory poolBalances = getPoolBalances();
        uint investmentMinusFee = investmentAmount.sub(investmentAmount.mul(fee) / ONE);

        uint buyTokenPoolBalance = poolBalances[outcomeIndex];
        uint endingOutcomeBalance = buyTokenPoolBalance.mul(ONE);

        for (uint i = 0; i < poolBalances.length; i++) {
            if (i != outcomeIndex) {
                uint poolBalance = poolBalances[i];
                endingOutcomeBalance = endingOutcomeBalance
                    .mul(poolBalance)
                    .ceildiv(poolBalance.add(investmentMinusFee));
            }
        }
        require(endingOutcomeBalance > 0, "must have non-zero balances");

        return buyTokenPoolBalance
            .add(investmentMinusFee)
            .sub(endingOutcomeBalance.ceildiv(ONE));
    }

    /**
     * @notice Calculates how many outcome tokens must be sold to receive a specific net amount of collateral, accounting for fees.
     * @param returnAmount The net amount of collateral the user wants to receive.
     * @param outcomeIndex The index of the outcome token to be sold.
     * @return The number of outcome tokens required to be sold.
     */
    function calcSellAmount(uint returnAmount, uint outcomeIndex) public view returns (uint) {
        require(outcomeIndex < positionIds.length, "invalid outcome index");
        uint[] memory poolBalances = getPoolBalances();

        uint returnAmountPlusFees = returnAmount.mul(ONE).div(ONE.sub(fee));
        uint sellTokenPoolBalance = poolBalances[outcomeIndex];
        uint endingOutcomeBalance = sellTokenPoolBalance.mul(ONE);

        for (uint i = 0; i < poolBalances.length; i++) {
            if (i != outcomeIndex) {
                uint poolBalance = poolBalances[i];
                endingOutcomeBalance = endingOutcomeBalance
                    .mul(poolBalance)
                    .ceildiv(poolBalance.sub(returnAmountPlusFees));
            }
        }
        require(endingOutcomeBalance > 0, "must have non-zero balances");

        return returnAmountPlusFees
            .add(endingOutcomeBalance.ceildiv(ONE))
            .sub(sellTokenPoolBalance);
    }

    /**
     * @notice Executes the purchase of outcome tokens, deducting a fee and distributing tokens accordingly.
     * @param investmentAmount The total collateral amount being invested.
     * @param outcomeIndex The index of the outcome token to purchase.
     * @param minOutcomeTokensToBuy The minimum acceptable number of outcome tokens to buy.
     */
    function buy(uint investmentAmount, uint outcomeIndex, uint minOutcomeTokensToBuy) external {
        uint outcomeTokensToBuy = calcBuyAmount(investmentAmount, outcomeIndex);
        require(outcomeTokensToBuy >= minOutcomeTokensToBuy, "minimum buy not reached");

        require(collateralToken.transferFrom(msg.sender, address(this), investmentAmount), "cost transfer failed");

        uint feeAmount = investmentAmount.mul(fee).div(ONE);
        feePoolWeight = feePoolWeight.add(feeAmount);

        uint investmentMinusFee = investmentAmount.sub(feeAmount);
        require(collateralToken.approve(address(conditionalTokens), investmentMinusFee), "approval for splits failed");
        splitPositionThroughAllConditions(investmentMinusFee);

        conditionalTokens.safeTransferFrom(
            address(this),
            msg.sender,
            positionIds[outcomeIndex],
            outcomeTokensToBuy,
            ""
        );

        emit FPMMBuy(msg.sender, investmentAmount, feeAmount, outcomeIndex, outcomeTokensToBuy);
    }

    /**
     * @notice Executes the sale of outcome tokens for a specific net return amount, accounting for fees.
     * @param returnAmount The amount of collateral the seller wants to receive (net of fees).
     * @param outcomeIndex The index of the outcome token to sell.
     * @param maxOutcomeTokensToSell The maximum outcome tokens the user is willing to sell.
     */
    function sell(uint returnAmount, uint outcomeIndex, uint maxOutcomeTokensToSell) external {
        uint outcomeTokensToSell = calcSellAmount(returnAmount, outcomeIndex);
        require(outcomeTokensToSell <= maxOutcomeTokensToSell, "maximum sell exceeded");

        conditionalTokens.safeTransferFrom(
            msg.sender,
            address(this),
            positionIds[outcomeIndex],
            outcomeTokensToSell,
            ""
        );

        uint feeAmount = returnAmount.mul(fee).div(ONE.sub(fee));
        feePoolWeight = feePoolWeight.add(feeAmount);

        uint returnAmountPlusFees = returnAmount.add(feeAmount);
        mergePositionsThroughAllConditions(returnAmountPlusFees);

        require(collateralToken.transfer(msg.sender, returnAmount), "return transfer failed");

        emit FPMMSell(msg.sender, returnAmount, feeAmount, outcomeIndex, outcomeTokensToSell);
    }
}

/**
 * @title FixedProductMarketMakerData
 * @dev Storage layout for proxy-based deployments of FixedProductMarketMaker.
 */
contract FixedProductMarketMakerData {
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;
    uint256 internal _totalSupply;

    bytes4 internal constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;
    mapping(bytes4 => bool) internal _supportedInterfaces;

    event FPMMFundingAdded(
        address indexed funder,
        uint[] amountsAdded,
        uint sharesMinted
    );
    event FPMMFundingRemoved(
        address indexed funder,
        uint[] amountsRemoved,
        uint collateralRemovedFromFeePool,
        uint sharesBurnt
    );
    event FPMMBuy(
        address indexed buyer,
        uint investmentAmount,
        uint feeAmount,
        uint indexed outcomeIndex,
        uint outcomeTokensBought
    );
    event FPMMSell(
        address indexed seller,
        uint returnAmount,
        uint feeAmount,
        uint indexed outcomeIndex,
        uint outcomeTokensSold
    );

    ConditionalTokens internal conditionalTokens;
    IERC20 internal collateralToken;
    bytes32[] internal conditionIds;
    uint internal fee;
    uint internal feePoolWeight;

    uint[] internal outcomeSlotCounts;
    bytes32[][] internal collectionIds;
    uint[] internal positionIds;
    address internal bondingCurveAddress;

    // Oracle fields
    address internal oracle;
    uint internal oracleFee;
    bool internal oracleFeePaid;
}

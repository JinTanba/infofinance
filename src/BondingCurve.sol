// SPDX-License-Identifier: MIT
pragma solidity ^0.5.1;
import { console } from "forge-std/console.sol";
contract BondingCurve {
    uint256 public constant A = 1; // Base price offset.
    uint256 public constant B = 1; // Slope.
    
    // A predetermined flat price to use when no tokens have been issued yet.
    uint256 public constant INITIAL_PRICE = 1;

    /**
     * @notice Calculates the cost for minting additional tokens, taking into account a special case for totalSupply = 0.
     * @param increase    The number of tokens to mint (ΔS).
     * @param totalSupply The current total supply (S).
     * @return cost       The calculated cost.
     */
    function calculateCost(uint256 increase, uint256 totalSupply)
        external
        view
        returns (uint cost)
    {
        
        cost = increase;
        
    }
}

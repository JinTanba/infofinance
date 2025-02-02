// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "conditional-tokens-market-makers/contracts/MarketMaker.sol";
import "conditional-tokens/contracts/ConditionalTokens.sol";

contract Counter {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}

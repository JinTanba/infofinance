// SPDX-License-Identifier: MIT
pragma solidity 0.5.17;

import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

import { ConditionalTokens } from "../src/CTF.sol";
import { FixedProductMarketMaker } from "../src/AMM.sol";
import { FPMMDeterministicFactory } from "../src/Factory.sol";
import { ERC20Mintable } from "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { Resolver } from "../src/MarketRealy.sol";
import { BondingCurve } from "../src/BondingCurve.sol";

import { CTHelpers } from "conditional-tokens/contracts/CTHelpers.sol";

/**
 * @dev A Foundry script that:
 *   1) Deploys Conditional Tokens
 *   2) Deploys the FPMMDeterministicFactory
 *   3) Deploys a mintable ERC20 (as collateral)
 *   4) Deploys a BondingCurve
 *   5) Deploys the Resolver
 *   6) Creates a test market
 *   7) Registers itself as an Oracle
 *   8) Demonstrates adding funding to the newly created FPMM
 */
contract DeployCTF {
    event LogDeployment(address indexed deployedAt, uint256 chainId);

    ConditionalTokens public ctf;
    FPMMDeterministicFactory public factory;
    ERC20Mintable public collateralToken;
    Resolver public resolver;
    BondingCurve public bondingCurve;

    // Storing references to the results of "prepareMarket" / "setOracle"
    uint256 public universalMarketId;
    bytes32 public marketId;
    bytes32 public questionId;
    bytes32 public conditionId;
    address public fpmmAddress;

    function run() public returns (address) {
        // 1) Prank as the deployer
        Vm vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
        vm.startPrank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        // 2) Deploy all core contracts
        ctf = new ConditionalTokens();
        

        factory = new FPMMDeterministicFactory();
        

        collateralToken = new ERC20Mintable();
        // Mint a large supply to our deployer
        collateralToken.mint(msg.sender, 100_000_000_0000 ether);
        

        bondingCurve = new BondingCurve();
        

        resolver = new Resolver(
            address(ctf),
            address(factory),
            address(bondingCurve)
        );
        

        // 3) Prepare a new market
        {
            // Example metadata
            uint256 fee = 300;  // e.g. 3%
            string memory title = "Will ETH exceed $2k by EOY?";
            string memory image = "https://somecdn/img.png";
            string memory description = "Basic test market for demonstration";
            address[] memory whitelist = new address[](0);  // open to all
            uint256 outcomeSlotCount = 2;  // yes/no
            uint256 deadline = block.timestamp + 30 days;

            // This increments the resolver's internal universalId
            marketId = resolver.prepareMarket(
                fee,
                title,
                image,
                description,
                whitelist,
                outcomeSlotCount,
                address(collateralToken),
                deadline
            );
        }
        // The first market is universalId = 1
        universalMarketId = 1;
        
        

        // 4) Set the Oracle (deploys FPMM)
        {
            uint256 oracleFee = 1000;
            fpmmAddress = resolver.setOracle(universalMarketId, oracleFee);
            
        }

        questionId = resolver.getQuestionId(universalMarketId, address(this));
        
        

        conditionId = resolver.getConditionId(universalMarketId, address(this));
        
        
        // create2FixedProductMarketMaker
        
        factory.create2FixedProductMarketMaker()

    }
}

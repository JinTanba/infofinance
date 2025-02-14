// SPDX-License-Identifier: MIT
pragma solidity 0.5.17; // Or change to ^0.8.x if your environment demands it

import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

import { ConditionalTokens } from "../src/CTF.sol";
import { FixedProductMarketMaker } from "../src/AMM.sol";
import { FPMMDeterministicFactory } from "../src/Factory.sol";
import { ERC20Mintable } from "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

// Make sure this import path points to your actual updated Resolver contract file
import { Resolver } from "../src/MarketRealy.sol";

import { BondingCurve } from "../src/BondingCurve.sol";

// If you need the official Gnosis CTHelpers, use the correct path:
// import { CTHelpers } from "@gnosis.pm/conditional-tokens-contracts/contracts/CTHelpers.sol";
// Otherwise, if you have a local copy in "conditional-tokens/contracts/CTHelpers.sol", keep that.
import { CTHelpers } from "conditional-tokens/contracts/CTHelpers.sol";

/**
 * @title CheckResolver
 * @notice Foundry script to deploy and test the updated Resolver contract and related Gnosis CTF contracts.
 */
contract CheckResolver {
    event LogDeployment(address indexed deployedAt, uint256 chainId);

    Vm vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    ConditionalTokens public ctf;
    FPMMDeterministicFactory public factory;
    ERC20Mintable public collateralToken;
    BondingCurve public bondingCurve;
    Resolver public resolver;

    // Data we gather from the script
    uint256 public universalMarketId;
    bytes32 public marketId;
    bytes32 public questionId;
    bytes32 public conditionId;
    address public fpmmAddress;

    /**
     * @dev This function deploys and configures all contracts, then runs a simple test flow:
     *      - Creates a market
     *      - Registers the script caller as an oracle
     *      - Adds funding to the newly created FPMM
     *      Finally, it returns the address of the deployed Resolver (for convenience).
     */
    function run() public returns (address) {
        // ---------------------------------
        // 1) Setup: Impersonate a deployer
        // ---------------------------------
        address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        vm.startPrank(deployer);

        // (Uncomment if you want an actual tx broadcast in a live environment)
        // vm.startBroadcast();

        // ---------------------------------
        // 2) Deploy core contracts
        // ---------------------------------
        ctf = new ConditionalTokens();
        

        factory = new FPMMDeterministicFactory();
        

        collateralToken = new ERC20Mintable();
        // Mint some collateral to the deployer
        collateralToken.mint(deployer, 100_000_000_0000 ether);
        

        bondingCurve = new BondingCurve();
        

        // ---------------------------------
        // 3) Deploy the updated Resolver
        // ---------------------------------
        resolver = new Resolver(
            address(ctf),
            address(factory),
            address(bondingCurve)
        );
        

        // ---------------------------------
        // 4) Create a new market
        // ---------------------------------
        {
            // Parameters
            // NOTE: If your FPMM interprets fee as a fraction of 1e18, "500" is effectively 5e-16, not 5%.
            // If you truly want 5%, use fee = 5e16 (i.e., 0.05 * 1e18 = 5e16).
            uint256 fee = 500; 
            string memory title = "Will it rain tomorrow?";
            string memory image = "ipfs://someCid";
            string memory description = "A simple yes/no market about tomorrow’s weather.";
            address[] memory whitelist = new address[](0); // Empty => no whitelist
            uint256 outComeSlotCount = 2; // yes/no
            address _collateralToken = address(collateralToken);
            uint256 deadline = block.timestamp + 1 days;

            uint256 oldUniversalId = resolver.universalId();

            marketId = resolver.prepareMarket(
                fee,
                title,
                image,
                description,
                whitelist,
                outComeSlotCount,
                _collateralToken,
                deadline
            );

            universalMarketId = oldUniversalId + 1;
            
            
        }

        // ---------------------------------
        // 5) Register this script (deployer) as an Oracle
        // ---------------------------------
        {
            // Example: set an "oracleFee" of 200 (like 2%, or 200 basis points, etc.)
            uint256 oracleFee = 200;

            fpmmAddress = resolver.setOracle(
                universalMarketId,
                oracleFee
            );

            // We can confirm we got the correct questionId & conditionId
            questionId = resolver.getQuestionId(universalMarketId, address(deployer));
            conditionId = resolver.getConditionId(universalMarketId, address(deployer));

            
            FixedProductMarketMaker fpmm = FixedProductMarketMaker(fpmmAddress);

            // If your FPMM has a function to expose the BondingCurve address:
            address bc = fpmm.bondingCurveAddress();
            

            
            
        }

        // ---------------------------------
        // 6) Demonstrate adding funding to the new FPMM
        // ---------------------------------
        {
            // Approve the FPMM to spend our collateral
            IERC20(collateralToken).approve(fpmmAddress, 1000 ether);

            // Typically, you pass distributionHint so the newly minted outcome tokens 
            // get distributed across the 2 positions. For a 2-outcome market, 
            // [500 ether, 500 ether] if you're depositing 1000 total, etc.
            uint256[] memory distributionHint = new uint256[](2);
            distributionHint[0] = 500 ether;
            distributionHint[1] = 500 ether;

            // IMPORTANT: pass both parameters: addedFunds and distributionHint
            FixedProductMarketMaker(fpmmAddress).addFunding(1000 ether);

            
        }

        // vm.stopBroadcast();
        vm.stopPrank();

        // Optionally emit an event if desired
        // emit LogDeployment(address(resolver), block.chainid);

        // Return the address of the Resolver for reference
        return address(resolver);
    }
}

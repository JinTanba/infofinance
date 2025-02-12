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

contract CheckFactory {
    // State variables to reduce stack usage
    ConditionalTokens public ctf;
    FPMMDeterministicFactory public factory;
    ERC20Mintable public collateral;
    BondingCurve public bondingCurve;
    Resolver public resolver;
    
    // Split the run function into smaller functions
    function run() external {
        deployContracts();
        createMarket();
        address fpmm = setupOracle();
        initializeFPMM(fpmm);
        verifyFPMM(fpmm);
    }

    function deployContracts() internal {
        // Prank as the deployer
        Vm vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
        vm.startPrank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        // Deploy contracts
        ctf = new ConditionalTokens();
        console.log("ConditionalTokens deployed at", address(ctf));

        factory = new FPMMDeterministicFactory();
        console.log("FPMMDeterministicFactory deployed at", address(factory));

        collateral = new ERC20Mintable();
        collateral.mint(msg.sender, 1e24);
        console.log("ERC20Mintable (collateral) deployed at", address(collateral));

        bondingCurve = new BondingCurve();
        console.log("BondingCurve deployed at", address(bondingCurve));

        resolver = new Resolver(
            address(ctf),
            address(factory),
            address(bondingCurve)
        );
        console.log("Resolver deployed at", address(resolver));
    }

    function createMarket() internal {
        MarketParams memory params = MarketParams({
            fee: 300,
            title: "Will ETH exceed $2k by EOY?",
            image: "http://example.com/img.png",
            desc: "Demo market for verifying FPMM & factory",
            outcomeSlotCount: 2,
            deadline: block.timestamp + 30 days
        });

        address[] memory wlist = new address[](0);
        bytes32 marketId = resolver.prepareMarket(
            params.fee,
            params.title,
            params.image,
            params.desc,
            wlist,
            params.outcomeSlotCount,
            address(collateral),
            params.deadline
        );
        console.log("Market prepared: marketId =", bytes32ToString(marketId));
    }

    function setupOracle() internal returns (address) {
        console.log("\nCalling resolver.setOracle(...) => should deploy minimal proxy FPMM...");
        uint256 oracleFee = 1000;
        address newFPMMAddr = resolver.setOracle(1, oracleFee);
        console.log("FPMM (proxy) deployed at", newFPMMAddr);
        return newFPMMAddr;
    }

    function initializeFPMM(address newFPMMAddr) internal {
        console.log("Manually calling cloneConstructor on the new FPMM clone...");

        bytes32 questionId = resolver.getQuestionId(1, address(this));
        bytes32 conditionId = resolver.getConditionId(1, address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        conditionIds[0] = conditionId;

        bytes memory initData = abi.encode(
            ctf,
            IERC20(collateral),
            conditionIds,
            300,
            1000,
            address(this),
            address(bondingCurve)
        );

        (bool success, ) = newFPMMAddr.call(
            abi.encodeWithSignature("cloneConstructor(bytes)", initData)
        );
        require(success, "cloneConstructor call on FPMM clone failed");
        
        console.log("Successfully initialized FPMM proxy storage.");
    }

    function verifyFPMM(address newFPMMAddr) internal {
        FixedProductMarketMaker typedFPMM = FixedProductMarketMaker(newFPMMAddr);

        require(
            address(typedFPMM.conditionalTokens()) == address(ctf),
            "FPMM: conditionalTokens mismatch"
        );
        require(
            address(typedFPMM.collateralToken()) == address(collateral),
            "FPMM: collateralToken mismatch"
        );
        require(
            typedFPMM.fee() == 300,
            "FPMM: fee mismatch"
        );
        require(
            typedFPMM.oracleFee() == 1000,
            "FPMM: oracleFee mismatch"
        );
        require(
            typedFPMM.oracle() == address(this),
            "FPMM: oracle mismatch"
        );
        require(
            typedFPMM.bondingCurve() == address(bondingCurve),
            "FPMM: bondingCurveAddress mismatch"
        );

        console.log("All FPMM checks passed! The new clone is correctly initialized.");
    }

    // Helper struct to group market parameters
    struct MarketParams {
        uint256 fee;
        string title;
        string image;
        string desc;
        uint256 outcomeSlotCount;
        uint256 deadline;
    }

    function bytes32ToString(bytes32 x) internal pure returns (string memory) {
        return string(abi.encodePacked(x));
    }
}
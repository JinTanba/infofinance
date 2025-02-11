## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```




1. `prepareCondition(...)`
   args:
   description:
2. `splitPosition(...)`
   args:
   description:
3. `splitPosition`
   args:
   description:

   // pragma solidity ^0.5.1;
// import {CTHelpers} from "conditional-tokens/contracts/CTHelpers.sol";

// contract Relay {

//     mapping(bytes32 => uint256) public salts;
//     mapping(bytes32 => address[]) public oracleList;

//     struct EventInfo{
//         string name;
//         string symbol;
//         string title;
//         string description;
//         address[] whitelist;
//         bytes[] positions;
//         string[] positionsBio;
//         uint256 expaired;
//     }

//     struct PrepareEventParams {
//         EventInfo info;
//         address conditionalTokensAddress;
//         address collateralTokenAddress;
//         uint256 fee;
//     }

//     function prepareEvent(PrepareEventParams calldata params) external returns(bytes32 eventId) {
//     }

//     function setOracle(bytes32 eventId) external returns(bytes32 questionId) {
//     }

// }



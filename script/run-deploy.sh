#!/bin/bash
forge build
cast send --private-key $PRIVATE_KEY \
    --rpc-url http://localhost:8545 \
    --from $DEPLOYER_ADDRESS \
    "$(forge inspect DeployCTF run)"
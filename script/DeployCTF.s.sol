// SPDX-License-Identifier: MIT
pragma solidity 0.5.17;


import {ConditionalTokens} from 'conditional-tokens/contracts/ConditionalTokens.sol';


contract DeployCTF is Script {
    function run() public {
        // プライベートキーの取得方法を修正
        bytes32 deployerPrivateKey = vm.envBytes32("PRIVATE_KEY");
        
        // broadcastの開始
        vm.broadcast(deployerPrivateKey);
        
        // コントラクトのデプロイ
        ConditionalTokens ctf = new ConditionalTokens();
        
        // デプロイアドレスのログ出力
        emit log_address(address(ctf));
    }
}
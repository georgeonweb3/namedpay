// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NamedPay.sol";
import "../test/MockAgentID.sol";

/// @notice Deploy NamedPay.
/// Env:
///   AGENT_ID   — Agent ID contract address (default: BSC mainnet SPACE ID Agent ID)
///   DEPLOY_MOCK — "true" to deploy MockAgentID first and point NamedPay at it
///                 (BSC testnet has no Agent ID contract)
///   MINT_LABEL / MINT_OWNER — if set with DEPLOY_MOCK, mint a test name
contract Deploy is Script {
    address internal constant MAINNET_AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external {
        address agentId = vm.envOr("AGENT_ID", MAINNET_AGENT_ID);
        bool deployMock = vm.envOr("DEPLOY_MOCK", false);

        vm.startBroadcast();
        if (deployMock) {
            MockAgentID mock = new MockAgentID();
            agentId = address(mock);
            console.log("MockAgentID deployed at:", agentId);
            string memory label = vm.envOr("MINT_LABEL", string(""));
            if (bytes(label).length > 0) {
                address mintOwner = vm.envAddress("MINT_OWNER");
                mock.mint(label, mintOwner);
                console.log("Minted test name:", label, "->", mintOwner);
            }
        }
        NamedPay pay = new NamedPay(agentId);
        console.log("NamedPay deployed at:", address(pay));
        console.log("Agent ID:", agentId);
        console.log("Owner (deployer):", msg.sender);
        vm.stopBroadcast();
    }
}

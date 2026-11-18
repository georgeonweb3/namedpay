// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/NamedPay.sol";

/// @notice Fork test against the REAL Agent ID contract on BSC mainnet
/// (0x60b9262456de011f7d15a54cdd8c48baaa8b022f). Verifies the exact on-chain
/// claim the whole product rests on: tokenId = keccak256(label), and
/// ownerOf(keccak256("georgeonweb3")) is George's wallet.
/// @dev Only runs when BSC_RPC_URL is set, e.g.:
///   BSC_RPC_URL=https://bsc-dataseed.binance.org forge test --match-contract NamedPayForkTest
contract NamedPayForkTest is Test {
    address internal constant AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address internal constant GEORGE = 0xA79E2C85D5456Fa3d9115d86398896a390159D1c;

    NamedPay internal pay;

    function setUp() public {
        string memory rpc = vm.envOr("BSC_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(rpc);
        pay = new NamedPay(AGENT_ID);
    }

    function test_realAgentId_resolvesGeorgeonweb3() public {
        assertEq(pay.resolveName("georgeonweb3"), GEORGE);
    }

    function test_realAgentId_caseInsensitive() public {
        assertEq(pay.resolveName("GeorgeOnWeb3"), GEORGE);
    }

    function test_realAgentId_nonexistentNameReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                NamedPay.NameNotFound.selector, keccak256(bytes("definitely-not-a-real-agent-id-name-xyz"))
            )
        );
        pay.resolveName("definitely-not-a-real-agent-id-name-xyz");
    }
}

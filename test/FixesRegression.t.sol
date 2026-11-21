// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/NamedPay.sol";
import "./MockAgentID.sol";

/// @notice Regression tests for the F1 + F2 audit fixes (2026-11-21).
/// F1: escrow owner is frozen at creation; a payout rotation or a name
/// sale after creation does not change who may confirm or who gets paid.
/// F2: paying by the full ".ai" name resolves instead of reverting.
contract NamedPayFixesTest is Test {
    MockAgentID internal agentId;
    NamedPay internal pay;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal payer = makeAddr("payer");
    address internal alicePayout = makeAddr("alicePayout");
    address internal alicePayout2 = makeAddr("alicePayout2");

    function setUp() public {
        vm.deal(deployer, 100 ether);
        vm.deal(payer, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        agentId = new MockAgentID();
        agentId.mint("alice", alice);
        agentId.mint("bob", bob);

        vm.prank(deployer);
        pay = new NamedPay(address(agentId));
    }

    // --- F1a: payout rotation does not affect an open escrow ---

    function test_F1_payoutRotationDoesNotChangeOpenEscrow() public {
        vm.prank(alice);
        pay.registerPayee("alice", alicePayout);

        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice");

        // Owner rotates the payout after the escrow was created.
        vm.prank(alice);
        pay.registerPayee("alice", alicePayout2);

        // The frozen owner (alice) can still confirm, and the payee
        // recorded at creation (alicePayout) is the one who gets paid.
        uint256 beforeOld = alicePayout.balance;
        uint256 beforeNew = alicePayout2.balance;
        vm.prank(alice);
        pay.confirmDelivery(id);
        assertEq(alicePayout.balance - beforeOld, 1 ether);
        assertEq(alicePayout2.balance - beforeNew, 0);

        // The new payout applies to new payments, not open escrows.
        assertEq(pay.resolveName("alice"), alicePayout2);
    }

    // --- F1b: name sale does not move confirmation rights on an open escrow ---

    function test_F1_nameSaleDoesNotMoveOpenEscrow() public {
        vm.prank(alice);
        pay.registerPayee("alice", alicePayout);

        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice");

        // Name is sold to bob after the escrow was created.
        agentId.transfer("alice", bob);

        // The new owner cannot confirm an escrow created under the old owner.
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(NamedPay.NotNameOwnerForEscrow.selector, id, bob)
        );
        pay.confirmDelivery(id);

        // The frozen owner (alice, who did the work) still confirms, and
        // the payee recorded at creation is paid.
        uint256 before = alicePayout.balance;
        vm.prank(alice);
        pay.confirmDelivery(id);
        assertEq(alicePayout.balance - before, 1 ether);
    }

    // --- F1c: refund path still works after the fix ---

    function test_F1_refundStillWorksAfterRotationAndSale() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 2 ether}("alice");

        vm.prank(alice);
        pay.registerPayee("alice", alicePayout2);
        agentId.transfer("alice", bob);

        uint256 before = payer.balance;
        vm.prank(payer);
        pay.refund(id);
        assertEq(payer.balance - before, 2 ether);
    }

    // --- F2: ".ai" suffix ---

    function test_F2_payByNameWithAiSuffixResolves() public {
        uint256 before = alice.balance;
        vm.prank(payer);
        pay.payByName{value: 0.5 ether}("alice.ai");
        assertEq(alice.balance - before, 0.5 ether);
    }

    function test_F2_payByNameWithUppercaseAiSuffixResolves() public {
        vm.prank(alice);
        pay.registerPayee("alice", alicePayout);

        uint256 before = alicePayout.balance;
        vm.prank(payer);
        pay.payByName{value: 0.5 ether}("ALICE.AI");
        assertEq(alicePayout.balance - before, 0.5 ether);
    }

    function test_F2_resolveNameWithAiSuffix() public {
        assertEq(pay.resolveName("alice.ai"), alice);
        assertEq(pay.resolveName("Alice.AI"), alice);
    }

    function test_F2_escrowByNameWithAiSuffix() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice.ai");

        uint256 before = alice.balance;
        vm.prank(alice);
        pay.confirmDelivery(id);
        assertEq(alice.balance - before, 1 ether);
    }

    function test_F2_onlyOneSuffixStripped() public {
        // "alice.ai.ai" strips one ".ai" -> "alice.ai", which is not a
        // registered label, so it still reverts NameNotFound.
        vm.prank(payer);
        vm.expectRevert(
            abi.encodeWithSelector(
                NamedPay.NameNotFound.selector, keccak256(bytes("alice.ai"))
            )
        );
        pay.payByName{value: 0.1 ether}("alice.ai.ai");
    }

    function test_F2_bareAiSuffixRevertsEmptyLabel() public {
        vm.prank(payer);
        vm.expectRevert(NamedPay.EmptyLabel.selector);
        pay.payByName{value: 0.1 ether}(".ai");
    }
}

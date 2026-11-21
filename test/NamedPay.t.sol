// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/NamedPay.sol";
import "./MockAgentID.sol";

contract NamedPayTest is Test {
    MockAgentID internal agentId;
    NamedPay internal pay;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal payer = makeAddr("payer");
    address internal alicePayout = makeAddr("alicePayout");
    address internal stranger = makeAddr("stranger");

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

    // --- registerPayee ---

    function test_registerPayee_onlyByNameOwner() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(NamedPay.NotNameOwner.selector, keccak256(bytes("alice")), stranger)
        );
        pay.registerPayee("alice", alicePayout);
    }

    function test_registerPayee_setsPayoutAndResolveReturnsIt() public {
        vm.prank(alice);
        pay.registerPayee("alice", alicePayout);
        assertEq(pay.resolveName("alice"), alicePayout);
        assertEq(pay.payoutOf(keccak256(bytes("alice"))), alicePayout);
    }

    function test_registerPayee_zeroAddressResetsToOwnerWallet() public {
        vm.prank(alice);
        pay.registerPayee("alice", alicePayout);
        assertEq(pay.resolveName("alice"), alicePayout);

        vm.prank(alice);
        pay.registerPayee("alice", address(0));
        assertEq(pay.resolveName("alice"), alice);
    }

    function test_registerPayee_emptyLabelReverts() public {
        vm.prank(alice);
        vm.expectRevert(NamedPay.EmptyLabel.selector);
        pay.registerPayee("", alicePayout);
    }

    // --- resolveName ---

    function test_resolveName_returnsOwnerWalletWhenNoPayoutRegistered() public {
        assertEq(pay.resolveName("bob"), bob);
    }

    function test_resolveName_revertsOnNonexistentName() public {
        vm.expectRevert(
            abi.encodeWithSelector(NamedPay.NameNotFound.selector, keccak256(bytes("nobody")))
        );
        pay.resolveName("nobody");
    }

    function test_resolveName_caseInsensitive() public {
        assertEq(pay.resolveName("Alice"), alice);
        assertEq(pay.resolveName("ALICE"), alice);
        assertEq(pay.resolveName("aLiCe"), alice);
    }

    // --- payByName ---

    function test_payByName_forwardsExactValueToPayout() public {
        vm.prank(alice);
        pay.registerPayee("alice", alicePayout);

        uint256 before = alicePayout.balance;
        vm.prank(payer);
        pay.payByName{value: 0.5 ether}("alice");
        assertEq(alicePayout.balance - before, 0.5 ether);
        assertEq(address(pay).balance, 0);
    }

    function test_payByName_forwardsToOwnerWalletWhenNoPayoutRegistered() public {
        uint256 before = bob.balance;
        vm.prank(payer);
        pay.payByName{value: 0.25 ether}("bob");
        assertEq(bob.balance - before, 0.25 ether);
    }

    function test_payByName_revertsOnNonexistentName() public {
        vm.prank(payer);
        vm.expectRevert(
            abi.encodeWithSelector(NamedPay.NameNotFound.selector, keccak256(bytes("nobody")))
        );
        pay.payByName{value: 0.1 ether}("nobody");
    }

    function test_payByName_revertsOnZeroValue() public {
        vm.prank(payer);
        vm.expectRevert(NamedPay.ZeroPayment.selector);
        pay.payByName{value: 0}("alice");
    }

    function test_payByName_uppercaseLabelResolves() public {
        uint256 before = alice.balance;
        vm.prank(payer);
        pay.payByName{value: 0.1 ether}("ALICE");
        assertEq(alice.balance - before, 0.1 ether);
    }

    // --- escrow ---

    function test_escrow_confirmDeliveryReleasesToPayee() public {
        vm.prank(alice);
        pay.registerPayee("alice", alicePayout);

        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice");

        uint256 before = alicePayout.balance;
        vm.prank(alice);
        pay.confirmDelivery(id);
        assertEq(alicePayout.balance - before, 1 ether);

        (,,,,,, bool released, bool refunded) = pay.escrows(id);
        assertTrue(released);
        assertFalse(refunded);
    }

    function test_escrow_confirmDelivery_onlyNameOwner() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("bob");

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(NamedPay.NotNameOwnerForEscrow.selector, id, stranger)
        );
        pay.confirmDelivery(id);
    }

    function test_escrow_refundBeforeConfirmationReturnsFunds() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 2 ether}("alice");

        uint256 before = payer.balance;
        vm.prank(payer);
        pay.refund(id);
        assertEq(payer.balance - before, 2 ether);

        (,,,,,, bool released, bool refunded) = pay.escrows(id);
        assertFalse(released);
        assertTrue(refunded);
    }

    function test_escrow_refund_onlyPayer() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice");

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(NamedPay.NotPayer.selector, id, stranger)
        );
        pay.refund(id);
    }

    function test_escrow_timeoutRefundAfterDeadline() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice");

        vm.warp(block.timestamp + 7 days + 1);
        uint256 before = payer.balance;
        vm.prank(stranger); // anyone may trigger it
        pay.timeoutRefund(id);
        assertEq(payer.balance - before, 1 ether);
    }

    function test_escrow_timeoutRefundBeforeDeadlineReverts() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice");

        (,,,,, uint256 deadline,,) = pay.escrows(id);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(NamedPay.DeadlineNotReached.selector, id, deadline)
        );
        pay.timeoutRefund(id);
    }

    function test_escrow_doubleSettleReverts() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice");

        vm.prank(alice);
        pay.confirmDelivery(id);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NamedPay.AlreadySettled.selector, id));
        pay.confirmDelivery(id);

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(NamedPay.AlreadySettled.selector, id));
        pay.refund(id);
    }

    function test_escrow_unknownIdReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NamedPay.EscrowNotFound.selector, 999));
        pay.confirmDelivery(999);
    }

    // --- pause ---

    function test_pause_blocksNewPaymentsButNotFundRelease() public {
        vm.prank(payer);
        uint256 id = pay.escrowByName{value: 1 ether}("alice");

        vm.prank(deployer);
        pay.pause();
        assertTrue(pay.paused());

        vm.prank(payer);
        vm.expectRevert(NamedPay.ContractPaused.selector);
        pay.payByName{value: 0.1 ether}("alice");

        vm.prank(alice);
        vm.expectRevert(NamedPay.ContractPaused.selector);
        pay.registerPayee("alice", alicePayout);

        vm.prank(payer);
        vm.expectRevert(NamedPay.ContractPaused.selector);
        pay.escrowByName{value: 0.1 ether}("alice");

        // Fund release still works while paused.
        uint256 before = alice.balance;
        vm.prank(alice);
        pay.confirmDelivery(id);
        assertEq(alice.balance - before, 1 ether);

        vm.prank(deployer);
        pay.unpause();
        assertFalse(pay.paused());
    }

    function test_pause_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NamedPay.NotOwner.selector, stranger));
        pay.pause();
    }

    function test_constructor_revertsOnZeroAgentId() public {
        vm.expectRevert(NamedPay.ZeroAddress.selector);
        new NamedPay(address(0));
    }

    function test_plainBnbTransferReverts() public {
        (bool ok,) = address(pay).call{value: 0.1 ether}("");
        assertFalse(ok);
    }
}

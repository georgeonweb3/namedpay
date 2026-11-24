// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BountyEscrow} from "../src/BountyEscrow.sol";
import {MockUSDC, FreezableMockUSDC} from "./Mocks.sol";

/// Audit tests for BountyEscrow (Base Sepolia 0xB552A72ffA00BD23e9b2bB7b9579f6a35d4d560C).
/// Deployed config mirrored here: fee 5%, min 1 USDC, max 100 USDC, max 10 open jobs,
/// max 500 USDC held, 3-day review window, 1h min / 30d max duration.
contract BountyEscrowAuditTest is Test {
    MockUSDC internal usdc;
    BountyEscrow internal escrow;
    address internal treasury = makeAddr("treasury");
    address internal poster = makeAddr("poster");
    address internal agent = makeAddr("agent");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant FEE_BPS = 500;
    uint256 internal constant MIN_AMT = 1_000_000; // 1 USDC
    uint256 internal constant MAX_AMT = 100_000_000; // 100 USDC

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new BountyEscrow(
            usdc, treasury, FEE_BPS, MIN_AMT, MAX_AMT, 10, 500_000_000
        );
        usdc.mint(poster, 10_000_000_000);
        vm.prank(poster);
        usdc.approve(address(escrow), type(uint256).max);
    }

    function _fund(uint256 amount) internal returns (uint256 id) {
        vm.prank(poster);
        id = escrow.fund(agent, amount, block.timestamp + 7 days, bytes32("ref"));
    }

    function _fundAs(address p, address a, uint256 amount) internal returns (uint256 id) {
        usdc.mint(p, amount);
        vm.prank(p);
        usdc.approve(address(escrow), amount);
        vm.prank(p);
        id = escrow.fund(a, amount, block.timestamp + 7 days, bytes32("ref"));
    }

    function _submitAndComplete(uint256 id) internal {
        vm.prank(agent);
        escrow.submit(id, bytes32(uint256(0xabc)));
        vm.prank(poster);
        escrow.complete(id);
    }

    // ── FINDING F-1: fee rounds DOWN, so the fee taken is less than 5% ──────
    // For any amount not divisible by 20, fee = floor(amount/20) < amount/20.
    // E.g. amount 1,000,001 -> fee 50,000, true 5% = 50,000.05. The agent is
    // overpaid by the fractional part (< 1 base unit, < $0.000001). Dust, but a
    // real deviation from "5% fee". This test asserts the fee IS exactly 5%
    // and FAILS against the published contract.
    function testFeeIsExactlyFivePercent() public {
        uint256 amount = 1_000_001; // 1.000001 USDC, smallest non-divisible-by-20 amount >= min
        uint256 id = _fund(amount);
        uint256 agentBefore = usdc.balanceOf(agent);
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        _submitAndComplete(id);
        uint256 feePaid = usdc.balanceOf(treasury) - treasuryBefore;
        uint256 toAgent = usdc.balanceOf(agent) - agentBefore;
        console.log("amount:", amount);
        console.log("fee paid:", feePaid, " true 5% would be 50000.05");
        console.log("agent got:", toAgent, " exact 95% would be 950000.95");
        // Exact-5% assertion: fee * 20 must equal the amount. FAILS (50,000*20 = 1,000,000 != 1,000,001).
        assertEq(feePaid * 20, amount, "fee is not exactly 5% of the amount");
    }

    // Same check at a round amount: fee IS exactly 5% there (control case).
    function testFeeIsExactAtRoundAmount() public {
        uint256 amount = 10_000_000; // 10 USDC
        uint256 id = _fund(amount);
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        _submitAndComplete(id);
        uint256 feePaid = usdc.balanceOf(treasury) - treasuryBefore;
        assertEq(feePaid, 500_000, "fee should be exactly 500,000 at 10 USDC");
        assertEq(feePaid * 20, amount);
    }

    // ── Ruled out: double payment ──────────────────────────────────────────
    function testCannotCompleteTwice() public {
        uint256 id = _fund(10_000_000);
        _submitAndComplete(id);
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.WrongState.selector);
        escrow.complete(id);
    }

    function testCannotRefundAfterPaid() public {
        uint256 id = _fund(10_000_000);
        _submitAndComplete(id);
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(BountyEscrow.WrongState.selector);
        escrow.refundExpired(id);
    }

    function testCannotWithdrawCreditTwice() public {
        // Credit path exercised via a freezable token in CreditTest below;
        // here: no credit exists, so withdraw reverts.
        vm.expectRevert(BountyEscrow.NothingToWithdraw.selector);
        escrow.withdraw();
    }

    // ── Ruled out: wrong address ───────────────────────────────────────────
    function testOnlyNamedAgentCanSubmit() public {
        uint256 id = _fund(10_000_000);
        vm.prank(stranger);
        vm.expectRevert(BountyEscrow.NotAgent.selector);
        escrow.submit(id, bytes32(uint256(1)));
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.NotAgent.selector);
        escrow.submit(id, bytes32(uint256(1)));
    }

    function testOnlyPosterCanReject() public {
        uint256 id = _fund(10_000_000);
        vm.prank(agent);
        escrow.submit(id, bytes32(uint256(1)));
        vm.prank(stranger);
        vm.expectRevert(BountyEscrow.NotPoster.selector);
        escrow.reject(id);
    }

    function testRefundGoesToPosterInFull() public {
        uint256 id = _fund(10_000_000);
        uint256 posterBefore = usdc.balanceOf(poster);
        vm.prank(agent);
        escrow.abandon(id);
        assertEq(usdc.balanceOf(poster) - posterBefore, 10_000_000, "refund must be full, no fee");
        assertEq(usdc.balanceOf(treasury), 0, "treasury must get nothing on refund");
    }

    // ── Ruled out: limits & timing ─────────────────────────────────────────
    function testCannotFundOverMaxAmount() public {
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.BadAmount.selector);
        escrow.fund(agent, MAX_AMT + 1, block.timestamp + 7 days, bytes32("ref"));
    }

    function testCannotFundUnderMinAmount() public {
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.BadAmount.selector);
        escrow.fund(agent, MIN_AMT - 1, block.timestamp + 7 days, bytes32("ref"));
    }

    function testCannotExceedOpenJobLimit() public {
        for (uint256 i = 0; i < 10; i++) {
            _fundAs(poster, agent, MIN_AMT);
        }
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.TooManyOpenJobs.selector);
        escrow.fund(agent, MIN_AMT, block.timestamp + 7 days, bytes32("ref"));
    }

    function testCannotExceedHeldLimit() public {
        // 5 jobs x 100 USDC = 500 USDC held (the max); a 6th dollar breaks it.
        for (uint256 i = 0; i < 5; i++) {
            _fundAs(poster, agent, MAX_AMT);
        }
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.TooMuchHeld.selector);
        escrow.fund(agent, MIN_AMT, block.timestamp + 7 days, bytes32("ref"));
    }

    function testCannotSubmitAfterDeadline() public {
        uint256 id = _fund(10_000_000);
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(agent);
        vm.expectRevert(BountyEscrow.TooLate.selector);
        escrow.submit(id, bytes32(uint256(1)));
    }

    function testStrangerCannotForcePaymentBeforeWindow() public {
        uint256 id = _fund(10_000_000);
        vm.prank(agent);
        escrow.submit(id, bytes32(uint256(1)));
        vm.prank(stranger);
        vm.expectRevert(BountyEscrow.TooEarly.selector);
        escrow.complete(id);
    }

    function testPosterCanCompleteImmediatelyButStrangerAfterWindow() public {
        uint256 id = _fund(10_000_000);
        vm.prank(agent);
        escrow.submit(id, bytes32(uint256(1)));
        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(stranger);
        escrow.complete(id);
        assertEq(usdc.balanceOf(agent), 9_500_000);
    }

    function testCannotRejectAfterWindow() public {
        uint256 id = _fund(10_000_000);
        vm.prank(agent);
        escrow.submit(id, bytes32(uint256(1)));
        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.TooLate.selector);
        escrow.reject(id);
    }

    function testPosterCannotReclaimBeforeDeadline() public {
        uint256 id = _fund(10_000_000);
        vm.expectRevert(BountyEscrow.TooEarly.selector);
        escrow.refundExpired(id);
    }

    function testDeadlineBounds() public {
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.BadDeadline.selector);
        escrow.fund(agent, MIN_AMT, block.timestamp + 30 minutes, bytes32("ref"));
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.BadDeadline.selector);
        escrow.fund(agent, MIN_AMT, block.timestamp + 31 days, bytes32("ref"));
    }
}

/// FINDING F-A: `Paid` is emitted even when the payout was refused and only
/// credited — the event claims a payment that never happened on-chain.
/// When the agent's transfer fails, `_pay` records credit and emits `Credited`,
/// but `complete()` then unconditionally emits `Paid(id, agent, toAgent, fee)`.
/// An indexer reading only `Paid` concludes the agent was paid 9,500,000 while
/// the agent's balance is still 0. This test asserts the event's claim
/// (agent balance rose by the `Paid` amount) and FAILS against the contract.
contract PaidEventAccuracyTest is Test {
    FreezableMockUSDC internal usdc;
    BountyEscrow internal escrow;
    address internal treasury = makeAddr("treasury");
    address internal poster = makeAddr("poster");
    address internal agent = makeAddr("agent");

    event Paid(uint256 indexed id, address indexed agent, uint256 toAgent, uint256 fee);
    event Credited(address indexed account, uint256 amount);

    function setUp() public {
        usdc = new FreezableMockUSDC();
        escrow = new BountyEscrow(usdc, treasury, 500, 1_000_000, 100_000_000, 10, 500_000_000);
        usdc.mint(poster, 10_000_000_000);
        vm.prank(poster);
        usdc.approve(address(escrow), type(uint256).max);
    }

    function testPaidEventMeansAgentWasPaid() public {
        vm.prank(poster);
        uint256 id = escrow.fund(agent, 10_000_000, block.timestamp + 7 days, bytes32("ref"));
        vm.prank(agent);
        escrow.submit(id, bytes32(uint256(1)));
        usdc.setFrozen(agent, true);
        uint256 agentBefore = usdc.balanceOf(agent);
        vm.recordLogs();
        vm.prank(poster);
        escrow.complete(id);
        // Both events fire in the same tx: Credited(agent, 9,500,000) AND Paid(id, agent, 9,500,000, 500,000).
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawPaid;
        bool sawCredited;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Paid(uint256,address,uint256,uint256)")) sawPaid = true;
            if (logs[i].topics[0] == keccak256("Credited(address,uint256)")) sawCredited = true;
        }
        assertTrue(sawPaid, "Paid event should fire");
        assertTrue(sawCredited, "Credited event should fire");
        console.log("agent balance after complete:", usdc.balanceOf(agent), " credit:", escrow.credit(agent));
        // The Paid event claims the agent received 9,500,000. FAILS: balance rose by 0.
        assertEq(usdc.balanceOf(agent) - agentBefore, 9_500_000, "Paid event says agent got 9,500,000");
    }
}

/// Credit-fallback path: a frozen agent's payout is credited, not lost, and a
/// blocked party never traps anyone else's money.
contract CreditPathTest is Test {
    FreezableMockUSDC internal usdc;
    BountyEscrow internal escrow;
    address internal treasury = makeAddr("treasury");
    address internal poster = makeAddr("poster");
    address internal agent = makeAddr("agent");
    address internal agent2 = makeAddr("agent2");

    function setUp() public {
        usdc = new FreezableMockUSDC();
        escrow = new BountyEscrow(usdc, treasury, 500, 1_000_000, 100_000_000, 10, 500_000_000);
        usdc.mint(poster, 10_000_000_000);
        vm.prank(poster);
        usdc.approve(address(escrow), type(uint256).max);
    }

    function testFrozenAgentIsCreditedAndCanWithdrawAfterUnfreeze() public {
        vm.prank(poster);
        uint256 id = escrow.fund(agent, 10_000_000, block.timestamp + 7 days, bytes32("ref"));
        vm.prank(agent);
        escrow.submit(id, bytes32(uint256(1)));
        usdc.setFrozen(agent, true);
        vm.prank(poster);
        escrow.complete(id);
        // Payout refused -> credited, not lost and not stuck.
        assertEq(escrow.credit(agent), 9_500_000);
        assertEq(escrow.totalCredit(), 9_500_000);
        assertEq(usdc.balanceOf(treasury), 500_000, "treasury leg still paid");
        usdc.setFrozen(agent, false);
        vm.prank(agent);
        escrow.withdraw();
        assertEq(usdc.balanceOf(agent), 9_500_000);
        assertEq(escrow.credit(agent), 0);
    }

    function testOneBlockedPartyDoesNotTrapOthers() public {
        vm.prank(poster);
        uint256 id1 = escrow.fund(agent, 10_000_000, block.timestamp + 7 days, bytes32("ref"));
        vm.prank(poster);
        uint256 id2 = escrow.fund(agent2, 10_000_000, block.timestamp + 7 days, bytes32("ref"));
        usdc.setFrozen(agent, true);
        vm.prank(agent);
        escrow.submit(id1, bytes32(uint256(1)));
        vm.prank(agent2);
        escrow.submit(id2, bytes32(uint256(1)));
        vm.prank(poster);
        escrow.complete(id1);
        vm.prank(poster);
        escrow.complete(id2);
        assertEq(usdc.balanceOf(agent2), 9_500_000, "healthy job pays out despite frozen sibling");
        assertEq(escrow.credit(agent), 9_500_000);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BountyEscrow} from "../src/BountyEscrow.sol";
import {MockUSDC} from "./Mocks.sol";

/// Invariant fuzz: the escrow must always be solvent — its USDC balance must
/// equal held (open jobs) + totalCredit (refused payouts) at every step.
/// Any accounting hole (double-pay, lost funds, phantom credit) breaks this.
contract SolvencyFuzzTest is Test {
    MockUSDC internal usdc;
    BountyEscrow internal escrow;
    address internal treasury = makeAddr("treasury");
    address internal poster = makeAddr("poster");
    address internal agent = makeAddr("agent");

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new BountyEscrow(usdc, treasury, 500, 1_000_000, 100_000_000, 10, 500_000_000);
        usdc.mint(poster, 1_000_000_000_000);
        vm.prank(poster);
        usdc.approve(address(escrow), type(uint256).max);
    }

    function _solvent() internal view {
        assertEq(
            usdc.balanceOf(address(escrow)),
            escrow.held() + escrow.totalCredit(),
            "escrow balance must equal held + totalCredit"
        );
    }

    /// Random walk through the whole lifecycle; solvency must hold after every step.
    function testFuzz_lifecycleSolvency(uint256 seed, uint8 steps) public {
        vm.assume(steps > 0 && steps < 20);
        uint256 rnd = seed;
        uint256[] memory ids = new uint256[](20);
        uint256 nIds = 0;
        for (uint256 s = 0; s < steps; s++) {
            rnd = uint256(keccak256(abi.encode(rnd, s)));
            uint256 action = rnd % 7;
            if (action == 0 && nIds < 10) {
                uint256 amount = 1_000_000 + (rnd % 99_000_001);
                vm.warp(block.timestamp + 1);
                vm.prank(poster);
                try escrow.fund(agent, amount, block.timestamp + 7 days, bytes32("ref")) returns (uint256 id) {
                    ids[nIds++] = id;
                } catch {}
            } else if (nIds > 0) {
                uint256 id = ids[rnd % nIds];
                if (action == 1) {
                    vm.prank(agent);
                    try escrow.submit(id, bytes32(uint256(0xabc))) {} catch {}
                } else if (action == 2) {
                    vm.prank(poster);
                    try escrow.complete(id) {} catch {}
                } else if (action == 3) {
                    vm.prank(poster);
                    try escrow.reject(id) {} catch {}
                } else if (action == 4) {
                    vm.prank(agent);
                    try escrow.abandon(id) {} catch {}
                } else if (action == 5) {
                    vm.warp(block.timestamp + 8 days);
                    try escrow.refundExpired(id) {} catch {}
                } else {
                    vm.prank(agent);
                    try escrow.withdraw() {} catch {}
                }
            }
            _solvent();
        }
        _solvent();
    }
}

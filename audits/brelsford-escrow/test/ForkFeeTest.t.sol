// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Runs against the REAL deployed BountyEscrow on Base Sepolia via a fork:
///   forge test --match-contract ForkFeeTest --fork-url https://sepolia.base.org
/// No testnet funds needed (deal/cheats only); no mainnet interaction.
interface IEscrow {
    function fund(address agent, uint256 amount, uint256 deadline, bytes32 ref) external returns (uint256 id);
    function submit(uint256 id, bytes32 deliverable) external;
    function complete(uint256 id) external;
    function feeBps() external view returns (uint256);
}

contract ForkFeeTest is Test {
    IEscrow internal constant ESCROW = IEscrow(0xB552A72ffA00BD23e9b2bB7b9579f6a35d4d560C);
    IERC20 internal constant USDC = IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e);
    address internal poster = makeAddr("poster");
    address internal agent = makeAddr("agent");

    function testDeployedFeeIsExactlyFivePercent() public {
        // Deployed config sanity: fee is 500 bps = 5%.
        assertEq(ESCROW.feeBps(), 500);
        uint256 amount = 1_000_001; // 1.000001 USDC
        deal(address(USDC), poster, amount);
        vm.prank(poster);
        USDC.approve(address(ESCROW), amount);
        vm.prank(poster);
        uint256 id = ESCROW.fund(agent, amount, block.timestamp + 7 days, bytes32("ref"));
        vm.prank(agent);
        ESCROW.submit(id, bytes32(uint256(0xabc)));
        address treasury = 0x3272d3E96Ab19FC9b184b57936FC83Da5Add086e;
        uint256 treasuryBefore = USDC.balanceOf(treasury);
        uint256 agentBefore = USDC.balanceOf(agent);
        vm.prank(poster);
        ESCROW.complete(id);
        uint256 feePaid = USDC.balanceOf(treasury) - treasuryBefore;
        uint256 toAgent = USDC.balanceOf(agent) - agentBefore;
        console.log("amount:", amount);
        console.log("fee paid:", feePaid, " true 5% = 50000.05");
        console.log("agent got:", toAgent, " exact 95% = 950000.95");
        // FAILS on the deployed contract: 50,000 * 20 = 1,000,000 != 1,000,001.
        assertEq(feePaid * 20, amount, "fee is not exactly 5% of the amount");
    }
}

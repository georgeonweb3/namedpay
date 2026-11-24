# Brelsford BountyEscrow audit — failing tests

Audit of `BountyEscrow` (Base Sepolia `0xB552A72ffA00BD23e9b2bB7b9579f6a35d4d560C`,
verified source via Sourcify, exact match, solc 0.8.28) for the bounties on
https://bounty.brelsfordsoftware.com. Deployed config: fee 500 bps (5%),
min 1 USDC, max 100 USDC per job, max 10 open jobs, max 500 USDC held,
3-day review window.

## How to run

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.6.1
forge test
```

`src/BountyEscrow.sol` is the published source, copied verbatim from Sourcify.

## The failing test (finding F-A, $1 tier)

`test/BountyEscrowAudit.t.sol`, contract `PaidEventAccuracyTest`,
`testPaidEventMeansAgentWasPaid()`:

`complete()` emits `Paid(id, agent, toAgent, fee)` unconditionally, even when
the agent's transfer was refused and the amount was only credited. Repro:

1. Poster funds a 10 USDC job for an agent.
2. Agent submits.
3. Agent's address refuses the transfer (e.g. Circle freeze — the contract's
   own `_pay` credit fallback triggers).
4. Poster calls `complete()`. `_pay(agent, 9,500,000)` fails, so
   `credit[agent] += 9,500,000` and `Credited(agent, 9,500,000)` fires.
5. `Paid(id, agent, 9,500,000, 500,000)` fires anyway, while the agent's
   USDC balance is still 0.

The test asserts the `Paid` event's claim (agent balance rose by the paid
amount) and **fails**: `0 != 9500000`. An indexer reading only `Paid`
overstates delivery. (`Credited` also fires in the same tx, so a correct
indexer can disambiguate — hence $1-tier, not $50.)

Same finding, against the real deployed contract on a fork:
`test/ForkFeeTest.t.sol` is the fee-rounding check (documented behavior,
checked and dismissed — fee is `floor(amount/20)`, under 5% by <1 base unit).

## Ruled out (all passing)

- Double payment (`complete` twice, refund after paid, double `withdraw`).
- Wrong address (only the named agent can submit; only the poster can reject;
  refunds go to the poster in full, no fee).
- Lock-up / cross-job blocking (frozen agent is credited and can withdraw
  after unfreeze; a frozen sibling job does not block a healthy job's payout).
- Limits and timing (>$100/job, >10 open jobs, >$500 held, submit after
  deadline, stranger forcing payment before the 3-day window, poster
  reclaiming before the deadline, deadline bounds).
- Solvency invariant fuzz (`test/SolvencyFuzz.t.sol`): contract balance always
  equals `held + totalCredit` across 256 random lifecycle runs.

## Submission

Finding F-A submitted to bounty `bty_3215c7e54e33020a` on
https://bounty.brelsfordsoftware.com as a $1-tier "wrong event" report.
No $50 / $5 / $2 break was found; the contract is unbroken against those
bounties as far as this audit could determine.

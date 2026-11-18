# NamedPay — Build Report (2026-11-18)

**Repo:** https://github.com/georgeonweb3/namedpay — branch `main`, commit `0e72a07` ("NamedPay v1: pay an agent by its .ai name")
**Contract:** `src/NamedPay.sol` (Solidity 0.8.36, no external dependencies)
**Status:** contract + tests DONE and pushed. BSC testnet deploy BLOCKED (faucet). Mainnet NOT deployed (window Nov 21–22, needs George's go).

## 0. Rename — NamePay → NamedPay (decision needed from parent/George)

- **"NamePay" COLLIDES.** Live Web2 wallet brand: namepay.online ("Your money. Your world. A smarter, more seamless way to manage your wallet and payments", © 2026 NamePay, live sign-in page) + namepay.org ("Coming Soon"). GitHub also has mohab-dot/Namepay and PATWEBSITE12/NAMEPAY. A judge googling the name finds a different payments wallet.
- **"PayByName" COLLIDES WORSE.** CoinPayments' trademarked `$PayByName` feature (same domain: paying by name). Block Inc also holds pay-by-name patents. Do not use.
- **"NamedPay" is CLEAN.** No product, no repo, no trademark found (only near-misses: Conduit's "Named Payouts" feature, Namaste Pay Nepal wallet, NAMANE PAY Korean prepaid). `georgeonweb3/namedpay` was free; repo created under this name.
- The contract, tests, deploy script, README and repo are all **NamedPay** now. Renaming before mainnet deploy costs nothing; renaming after deploy would cost a redeploy. **Parent/George: confirm the rename, or pick another name before Nov 21.** PLAN.md still says "NamePay" in places and needs a find-replace once confirmed.

## 1. What shipped

`src/NamedPay.sol` — BNB-only v1, constructor takes the Agent ID contract address (mainnet: `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`).

| Function | Notes |
|---|---|
| `registerPayee(label, payout)` | Only the name owner. `address(0)` resets to the owner wallet. Emits `PayeeRegistered`. |
| `resolveName(label)` view | Registered payout else owner wallet. Reverts `NameNotFound` if the name does not exist. Case-insensitive (A-Z lowercased on-chain). |
| `payByName(label)` payable | Forwards exactly `msg.value`. Reverts on nonexistent name / zero value. Emits `PaidByName`. |
| `escrowByName(label)` payable | Locks funds, 7-day deadline. Emits `EscrowCreated`. |
| `confirmDelivery(escrowId)` | Only the name owner. Releases to payout. Emits `EscrowReleased`. |
| `refund(escrowId)` | Only the payer, any time before confirmation. Emits `EscrowRefunded`. |
| `timeoutRefund(escrowId)` | Anyone, after the deadline, refunds to payer. Emits `EscrowRefunded`. |
| `pause()` / `unpause()` | Owner-only. Blocks new registrations/payments/escrows only — fund release is never paused. |

- No fee in v1. Owner can only pause; cannot move funds; no upgrade path; no withdrawal function; plain BNB transfers revert.
- **Red line honoured:** `resolveName` is a composable view for other contracts, documented in code + README as NOT a lookup product. No lookup UI anywhere.
- `test/MockAgentID.sol` — stand-in for the Agent ID contract (BSC testnet has none), used by unit tests and the testnet deploy script.
- `script/Deploy.s.sol` — `AGENT_ID` env (default mainnet), `DEPLOY_MOCK=true` + `MINT_LABEL`/`MINT_OWNER` for testnet.

## 2. Tests — all passing

- **24 unit tests** (`forge test`): registerPayee only-owner / set / reset-to-owner / empty label; resolveName owner-wallet / nonexistent-reverts / case-insensitive; payByName exact-value-to-payout / to-owner-wallet / nonexistent-reverts / zero-reverts / uppercase-label; escrow confirm-release / confirm-only-owner / refund-before-confirmation / refund-only-payer / timeout-refund-after-deadline / timeout-before-deadline-reverts / double-settle-reverts / unknown-id-reverts; pause blocks new payments but not fund release / pause only-owner; constructor zero-address reverts; plain BNB transfer reverts.
- **3 fork tests** (`BSC_RPC_URL=https://bsc-dataseed.binance.org forge test --match-contract NamedPayForkTest`) against the **real** Agent ID contract on BSC mainnet: `resolveName("georgeonweb3")` == `0xA79E2C85D5456Fa3d9115d86398896a390159D1c`; case-insensitive; nonexistent name reverts. The core mechanism is verified against live mainnet state.
- Compiler: solc 0.8.36, optimizer on (default 200 runs). One fix during build: `error Paused()` collided with `event Paused` — error renamed `ContractPaused()`.

## 3. Local-chain end-to-end (Anvil 31337, MockAgentID) — all confirmed

Deploy script broadcast OK (exit 0):
- MockAgentID `0x5FbDB2315678afecb367f032d93F642f64180aa3` — tx `0xec51df29866f50d0e3498579896a4607af76040d5c5c826b25df7b3b1f9a72da`
- Mint `testname` → `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` — tx `0x42f70c0559d9cb4ee04d3a46f51d645e2ccbeee262943eef28e85f9c28273c4f`
- NamedPay `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` — tx `0x954773134916808f718f59478d74d1f27a468c6e2429d923c47e24a9382bd35f`

Flow (all confirmed, balances verified):
- `resolveName("testname")` → owner wallet, then after `registerPayee` → payout `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` (tx `0x5cc4677d2e276ba5aeeb0d8fc0fb7d059d5f3085875b78d16a9632f6777d4582`)
- `payByName` 0.01 ETH → payout balance 10000 → 10000.01 (tx `0x3f0136b3b30f348c091dd7288b88429efb58c9a7165297ab9beae83e200e5e1c`)
- escrow 0.02 (tx `0xc86d70b1466ce339437608ba90a57cf62d57cfb7ef49529b241583288de05748`) → `confirmDelivery(0)` (tx `0x54a2e18860740c76623a6c3bccdfc2c7bbbc12d9d1c9abcffac36fd22faf5f5c`) → payout 10000.01 → 10000.03
- escrow 0.03 → `refund(1)` returned funds to payer (txs `0x5cd42c20...` / `0x35a268ad...`)
- escrow 0.04 → warp +7d1m → `timeoutRefund(2)` by a third party returned exactly 0.04 (txs `0x5449f20a...` / `0x0c4efe54...`)
- Final escrow states: id 0 released, id 1 refunded, id 2 refunded.

## 4. BSC testnet deploy — BLOCKED (faucet)

No testnet address. Tried, in order:
1. **Official faucet** (testnet.bnbchain.org/faucet-smart): the claim flow requires **hCaptcha** — cannot be solved via curl; the page's JS bundles contain no unauthenticated claim endpoint (only links out to Chainstack/QuickNode).
2. **Chainstack faucet** (faucet.chainstack.com): API is `POST /v1/faucet/{network}` with `Authorization: Bearer <Chainstack API key>` + `{address, source:"browser"}`. Requires a Chainstack account + API key. No key exists; creating an account for George was out of scope.
3. **QuickNode faucet**: requires an X/Twitter post as proof (tweet with the address). Needs George's X session.
4. Direct API probes to Chainstack (no key) and QuickNode (guessed endpoint) returned empty/timed out.

**Unblock routes (parent/George):** (a) George opens the official faucet on his phone and pastes the testnet deployer address `0x0Da027104BB0fb68505734E059EB89Df724fdf67` (key in `namepay/testnet-key.json`, chmod 600, gitignored — testnet funds only, throwaway); or (b) a Chainstack API key; or (c) the QuickNode tweet route. The moment any drip lands, the deploy is one command: `DEPLOY_MOCK=true MINT_LABEL=testname MINT_OWNER=<addr> forge script script/Deploy.s.sol --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 --broadcast --private-key <key-from-testnet-key.json>`.

## 5. Mainnet deploy gas — measured

- **Actual deploy gas (local receipt): 2,021,183 gas.** Mainnet simulation estimate (forge script, conservative): 2,627,537 gas.
- Live gas price at measurement: **0.05 gwei**. BNB: **$589.81** (Binance public mirror).
- **Cost at 0.05 gwei: ~$0.06 (measured) / ~$0.08 (sim estimate).**
- Deploy wallet holds 0.0010629 BNB (~$0.63). The deploy fits the wallet up to **~0.4 gwei (sim) / ~0.5 gwei (measured)**; at 0.5 gwei the sim estimate ($0.77) already exceeds the wallet. Check live gas on Nov 21 before deploying; if gas is above ~0.4 gwei, wait or top up.
- Note: `forge create --estimate` does not exist in forge 1.9.0 — the estimate above comes from `forge script` simulation + the actual local receipt. Same bytecode, same constructor-arg size.

## 6. Other blockers / notes

- **Anvil mainnet-fork dry run: blocked.** bsc-dataseed fork starts but Anvil's state fetches fail ("missing trie node" on system/zero accounts — the dataseed is a pruned node Anvil's REVM backend can't use); drpc fork fails with HTTP 429 (public-endpoint rate limit); publicnode fork can't retrieve the chain ID. The forge fork tests (different state-fetch path) work fine and are the proof against real mainnet state. Do not spend more time on the Anvil fork — the local e2e + forge fork tests cover it.
- **My own error, corrected:** I first deployed with a misremembered Anvil test key (…f3ff80 instead of …f2ff80), which derived to a nonexistent address `0x7f22…` and produced the early "missing trie node" errors on the fork. The fork errors after the key fix are the genuine upstream issue above. Lesson: always read Anvil keys from its own output, never from memory.
- **Testnet deployer key:** fresh throwaway `0x0Da027104BB0fb68505734E059EB89Df724fdf67`, `namepay/testnet-key.json` (chmod 600, gitignored, never committed). No funds, no real value.
- **Repo push note:** `gh repo create` did not attach the remote, and the gh OAuth token lacks the `workflow` scope — the first push was rejected because the Foundry template's `.github/workflows/test.yml` was included. Removed `.github/` and pushed clean. Do not re-add workflow files unless the token scope is widened.
- **No mainnet deploy, no real BNB spent, no submission, nobody contacted.** Nothing in this build touches George's wallets.

## 7. What remains for Nov 21–22

1. **Confirm the rename** (NamedPay) — then find-replace "NamePay" in PLAN.md.
2. **Testnet deploy** (optional but valuable): get a faucet drip to `0x0Da027104BB0fb68505734E059EB89Df724fdf67` (George's phone, 30 seconds), run the one command in §4, record the testnet address + tx hashes.
3. **Mainnet deploy** (needs George's go — real BNB): `forge script script/Deploy.s.sol --rpc-url https://bsc-dataseed.binance.org --broadcast --private-key <deployer-key>`; deployer must hold ≥ ~0.00013 BNB at current gas (check live gas first; abort above ~0.4 gwei). Then verify source on BscScan (API + retries, or the signed-in browser — BscScan is flaky from this VM).
4. **Minimal claim page** (registerPayee + resolveName UI, no lookup surface) + outreach start for the 100+ interactions.
5. **Live-agent proof payment** (hunter pays a named agent by name on-chain) — needs George's explicit go on the specific payment.
6. **Submit Dec 7** (buffer; hard deadline Dec 9, 09:00 WAT).

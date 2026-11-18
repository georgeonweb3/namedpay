# NamedPay — Deployments

## BSC testnet (chain 97) — DEPLOYED 2026-11-18

Deployer (throwaway, testnet only): `0x0Da027104BB0fb68505734E059EB89Df724fdf67`
(funded with 0.1 tBNB from George's main wallet; key in `testnet-key.json`, chmod 600, gitignored)

| Contract | Address | Deploy tx |
|---|---|---|
| MockAgentID (testnet stand-in; BSC testnet has no Agent ID contract) | `0x047Db9E618F51efB25590d4bb1f45b4777866f01` | `0x44a05a8f0e300cc0713eb439f114028084641d6e50eafe1da05003cc5d04ea14` |
| NamedPay | `0x644077780140F7E477cb8ecb6a69f4768DB91E4e` | `0x9fd4d4bf5ae4675aa01098e7f6602d4349740c723a190cf7f832edddd3df4c25` |

Mint `testname` → deployer: tx `0x3190a76b8de3185153687d6e9b7fa651bdc1e0847acdde89eb859391fa878da3`

### Full flow, verified on testnet with real txs (test name `testname`)

Payout test wallet (fresh throwaway): `0x670cFCAD86A7fdB8858051AFa1d184c4Ac772919`

| Step | Tx | Result (balance-checked) |
|---|---|---|
| `registerPayee("testname", payout)` | `0x5e6da72de542453713b9cb6d725de39be61956fcf36c22ddcbf21bdad291c6ab` | `resolveName("testname")` → payout address |
| `payByName("testname")` 0.01 tBNB | `0xd2cee7210da5c8ff8e4d044c08d583db71497553399015cbd3cd69662a4a5238` | payout balance exactly 0.01 tBNB |
| `escrowByName("testname")` 0.02 tBNB (id 1) | `0x38d2e42fcc140e390c3d5507de2a7e4f7c9524973e3fe2f8f1271715c91dec99` | NamedPay balance 0.05 (0.03 escrow 0 + 0.02) |
| `confirmDelivery(1)` | `0x5e67a506e76b9530caffd3aa9a646d27f13598b5bb763e32c0f9389007349d24` | payout balance 0.03 tBNB; escrow 1 `released=true` |
| `escrowByName("testname")` 0.03 tBNB (id 2) | `0x40e4e90f4561de30f6dab9266efee2b58f54481b77e797b92ea62558efc354a1` | NamedPay balance 0.06 |
| `refund(2)` | `0x0d10e7e1846f5483cab953934f34fb88f3d5f9e001d9e88cbf75de06c096b9be` | escrow 2 `refunded=true`; NamedPay balance 0.03 |
| `escrowByName("testname")` 0.03 tBNB (id 0, first attempt) | `0xcb4b66670407c32e4c82584d09d02ba2b2fd4dcac60143578c1de4bed0708e26` | escrow 0 created (payee = deployer, pre-payout-registration) |
| `confirmDelivery(0)` | `0x8ef5eb9c6e5f0421c750c72dbd42f8764b5a5679cde27b2f5932de48dbfc082a` | escrow 0 `released=true`; NamedPay balance 0 |

Final state: NamedPay balance 0; payout wallet 0.03 tBNB; deployer ~0.069 tBNB.
All three escrows settled (id 0 released, id 1 released, id 2 refunded). `timeoutRefund`
was proven on the local Anvil e2e (7-day warp); it cannot be exercised on testnet
without waiting 7 days.

**Note (BSC testnet gas quirk):** `cast send` intermittently estimates a 1-wei tip
cap, which the testnet RPC rejects (`gas tip cap 1, minimum needed 100000000`).
Pass explicit fees on every `cast send`: `--gas-price 1000000000
--priority-gas-price 100000000`.

### Source verification (testnet) — NOT verified

- BscScan web UI returns HTTP 403 from this VM; the V1 API is deprecated and the
  V2 API (`api.etherscan.io/v2/api?chainid=97`) requires an API key — none available.
  One `forge verify-contract` attempt was interrupted by a service restart; the
  follow-up API read confirms verification cannot complete without a key.
- Compiler: solc 0.8.36, optimizer on (200 runs). Constructor arg: Agent ID
  `0x047Db9E618F51efB25590d4bb1f45b4777866f01` (MockAgentID).
- Mainnet verification is the Nov 21–22 job (API key or signed-in browser).

## BSC mainnet (chain 56) — NOT DEPLOYED

Window Nov 21–22, needs George's go. Measured deploy gas: 2,021,183
(~$0.06 at 0.05 gwei). Deploy wallet (agentic) holds ~0.00106 BNB (~$0.63);
deploy fits up to ~0.4 gwei. Check live gas before deploying; abort above ~0.4 gwei.

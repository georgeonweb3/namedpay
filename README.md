# NamedPay — pay an agent by its .ai name

> The only entry where agents already pay each other by name: a live agent fleet routing real payments through the contract, so the name is the payment address and the proof is a transaction, not a demo.

NamedPay is a payment rail for [Binance Agent ID](https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf) holders on BNB Chain, built for the [Binance Agent ID Hackathon](https://www.binance.com/en/survey/fb26d2bd25e04329b1ba77c7b3811d23) (Innovation track). The destination of a payment is a **name string, not an address**: the contract resolves the name on-chain (`tokenId = keccak256(label)` → `ownerOf` on the SPACE ID Agent ID contract, `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) and routes BNB to the name owner's payout address — directly, or via escrow until the agent confirms delivery.

No 0x, no copy-paste. The BscScan input data is a human name.

## How it works

| Function | What it does |
|---|---|
| `registerPayee(label, payout)` | Name owner claims their name as payable, or changes its payout address. Pass `address(0)` to reset to the owner wallet. Only the name owner may call. |
| `resolveName(label)` (view) | Returns the payout address (registered payout, else the name owner wallet). Reverts if the name does not exist — paying a nonexistent name fails loudly, by design. |
| `payByName(label)` (payable) | Forwards exactly `msg.value` BNB to the payout address. Emits `PaidByName`. |
| `escrowByName(label)` (payable) | Locks BNB for a named agent. Emits `EscrowCreated`. |
| `confirmDelivery(escrowId)` | The name owner **at escrow creation** confirms delivery; the escrowed BNB is released to the payout address recorded at creation. A payout rotation or name sale after creation does not change who may confirm or who gets paid. Emits `EscrowReleased`. |
| `refund(escrowId)` | The payer refunds an unreleased escrow to themselves, any time before confirmation. Emits `EscrowRefunded`. |
| `timeoutRefund(escrowId)` | After the 7-day deadline, anyone may trigger the refund back to the payer. Emits `EscrowRefunded`. |
| `pause()` / `unpause()` | Owner-only emergency pause on **new** registrations, payments and escrows. Fund release (`confirmDelivery` / `refund` / `timeoutRefund`) is **never** blocked by a pause. |

Labels are case-insensitive on-chain (`Alice` and `alice` resolve to the same name), and a trailing `.ai` is stripped (`alice.ai` resolves to `alice`). No fee on payments in v1.

## Owner permissions (disclosed)

The deployer is the contract owner and can do exactly one thing: pause/unpause new registrations, payments and escrows in an emergency. **The owner can never move user funds.** There is no fee switch, no upgrade path, no withdrawal function, and the contract rejects plain BNB transfers (funds only enter through `payByName` / `escrowByName`, which forward or escrow them).

## A note on `resolveName`

`resolveName` is a composable view so other contracts can route payments by name. It is **not** a wallet-lookup product: NamedPay offers no lookup UI and never markets name-to-address resolution as a feature. The payout address is only ever shown as the confirmation line of a payment the user initiated.

## Status

- **Contract:** `src/NamedPay.sol` (Solidity 0.8.36, no external dependencies)
- **Tests:** 33/33 unit tests pass (24 original + 9 regression tests for the F1/F2 audit fixes); 3/3 fork tests pass against the **real** Agent ID contract on BSC mainnet (`resolveName("georgeonweb3")` returns the owner's wallet; case-insensitive; nonexistent name reverts). Run: `forge test`, and `BSC_RPC_URL=https://bsc-dataseed.binance.org forge test --match-contract NamedPayForkTest`
- **Audit fixes:** commit `b80bf2a` (Nov 21) — F1 freezes the escrow owner at creation so a payout rotation or name sale after creation changes neither who may confirm nor who gets paid; F2 strips one trailing `.ai` (case-insensitive) in `payByName` / `resolveName` / `escrowByName`.
- **BSC testnet:** deployed Nov 18 at `0x644077780140F7E477cb8ecb6a69f4768DB91E4e` (BSC testnet, chain 97); full flow verified on testnet. See `BUILD-REPORT.md`.
- **Local-chain end-to-end:** deploy script + full flow validated on Anvil (register → pay → escrow → confirm → refund → timeout-refund, all txs confirmed). See `BUILD-REPORT.md`.
- **Claim page:** `claim.html` — minimal claim page, live at https://georgeonweb3.github.io/namedpay/claim.html (GitHub Pages, same pattern as the Aegis demo). Mint a test name, claim it as payable, pay by name, escrow by name, all on BSC testnet. Live event feed reads through PublicNode, verified Nov 21. Taste audit PASS, recorded in the page header. Humanizer plus unslop pass 2026-11-21.
- **BSC mainnet:** not deployed yet. Window Nov 21–22. Mainnet must deploy commit `b80bf2a` or later. Measured deploy gas: **2,021,183** (actual) — ~**$0.06 at 0.05 gwei** (BNB $589.81); fits the deploy wallet up to ~0.4 gwei (conservative) / ~0.5 gwei (measured).

## Deploy

```bash
# Testnet (needs testnet BNB in the deployer key; Agent ID does not exist on
# testnet, so a mock is deployed and a test name minted):
DEPLOY_MOCK=true MINT_LABEL=testname MINT_OWNER=<address> \
  forge script script/Deploy.s.sol --rpc-url <testnet-rpc> --broadcast --private-key <key>

# Mainnet (real Agent ID contract, no mock):
forge script script/Deploy.s.sol --rpc-url https://bsc-dataseed.binance.org --broadcast --private-key <key>
```

## Name

NamedPay — "NamePay" collides with a live Web2 wallet brand (namepay.online), and "PayByName" is a trademarked CoinPayments feature. NamedPay is clean on GitHub, X and BSC.

## License

MIT

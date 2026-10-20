# IDM token

IDM is an immutable, fixed-supply ERC-20. Project X: https://x.com/theidmfun.

| Parameter | Value |
| --- | --- |
| Deployable contract | `src/IDMToken.sol:IDMToken` |
| Name / symbol | `IDM` / `IDM` |
| Decimals | `18` |
| Supply in tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` |
| Constructor arguments | None (`[]`) |
| Constructor payment | None; nonpayable |
| Initial recipient | The direct deployer (`msg.sender`) |
| Launch chain | Ethereum, chain ID `1` |

The constructor mints the entire supply once and emits the standard mint
`Transfer` event. In the IdentityMD custom-token launch, the direct deployer is
the launch factory, which receives all tokens. A direct deployment by another
account would instead give that account the entire supply.

## Behavior and assumptions

The brief specifies a standard token and an X link, with no additional transfer
rules. The link is informational project metadata, documented here and in the
contract's NatSpec; it introduces no external service dependency.

The implementation inherits the vendored OpenZeppelin ERC-20 without overriding
its transfer or allowance logic. Transfers deliver exactly the requested amount.
There are no token taxes, minting entry points, burns, rebases, pauses,
blacklists, ownership, upgrades, or administrative privileges. The inherited
internal mint/burn helpers are not externally callable; the only mint call is
in the constructor. The deployer retains no special authority over holders.

Standard ERC-20 behavior includes:

- Successful transfers and approvals return `true`; invalid operations revert
  with ERC-6093 custom errors.
- Transfers to the zero address and approvals to a zero spender revert.
  Zero-value transfers between nonzero addresses and self-transfers work.
- `approve` replaces the existing allowance. Finite allowances decrease on
  `transferFrom`; `type(uint256).max` is treated as an unlimited allowance.
- A failed `transferFrom` rolls back both balances and allowance.
- `transfer` and `transferFrom` emit `Transfer`; `approve` emits `Approval`.
  OpenZeppelin v5 does not emit `Approval` when spending an allowance.
- Transfers to contracts do not invoke receiver callbacks. Holders must check
  that a recipient contract can manage or return tokens sent to it.

There are no oracle reads, external calls, timing dependencies, or signatures.
Ordinary ETH payments revert. Forced ETH and tokens sent to this contract cannot
be recovered because there is no rescue function.

## Build and test

Use Foundry with Solidity **0.8.26** installed. The verifier supplies this compiler;
Foundry can install it on a connected development machine if needed. All source
dependencies are ordinary files in `lib/`, so an offline build with the pinned
compiler requires no dependency fetch or submodule initialization.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x6c226e6f25d3a8ff1a4023b830eca93e63d2af9f8b44a4dbf327ee02cf9f17b3 forge test
forge fmt --check
```

`foundry.toml` pins the compiler, Cancun EVM, optimizer (200 runs), and
`bytecode_hash = "none"`. It enables neither FFI nor filesystem cheatcode access.
Tests do not read or mutate environment variables or require an RPC endpoint.
The shell seed above controls Foundry's runner, not contract configuration.

The test suite covers metadata, issuance to account and CREATE2 factory
deployers, mint and transfer events, exact launch-allocation transfers, claim
transfers, transfers into and out of a simulated pool holder, approvals,
revocation, infinite allowances, insufficient balances and allowances, invalid
addresses, rollback, rejected administrative calls, and runtime opcode checks.
The pool-holder test checks token movements; it is not an integration test of
Uniswap's PoolManager or pricing.

Four fuzz tests exercise transfer conservation and allowance/balance bounds
with 1,024 cases each. Two stateful invariant tests run 256 sequences of up to
64 calls, comparing balances and allowances with an independent model across
successful and rejected transfers.

Local verification completed with Foundry 1.8.3 and Solidity 0.8.26:
`forge build`, the seeded `forge test`, and `forge fmt --check` all passed.
Foundry reported 36 passing tests (31 unit tests, four fuzz tests, and one
grouped invariant suite containing both properties), with 4,096 fuzz cases and
16,384 invariant calls. All vendored file checksums matched their upstream bytes;
the compiled runtime is 1,752 bytes and has no library link references.

## Deployment and operational responsibilities

The deployment artifact is `out/IDMToken.sol/IDMToken.json`. Deploy its creation
bytecode with no appended constructor arguments and zero ETH. The constructor
makes no external calls and needs no preexisting contracts or setup transactions.
Only `IDMToken` is a production contract; contracts under `test/` are test helpers.

IdentityMD's later manifest step records `IDMToken`, the metadata and supply
above, and empty constructor arguments. This repository deliberately does not
provide a `launch.json`. The network deployer handles attestation, factory
deployment, distribution, liquidity, and explorer verification.

The launch terms supplied with this assignment allocate 10% to the network
distributor, 60% to pool seeding, and 30% to the requester-designated remainder
recipient. Those transfers belong to the factory. The token constructor does
not reserve or transfer any allocation. Pool parameters and the opening price
are handled by the launch system and do not configure this token.

### After launch

No owner, configuration setters, keeper, backend, or ongoing contract maintenance
is required. The deployment operator should verify the deployed artifact,
metadata, initial issuance, and factory distribution receipts. Independent
adversarial review and explorer source verification remain release steps.
No deployment or broadcast is performed by this project.

Holders manage their own keys and allowances. Prefer bounded approvals and
revoke unused approvals. When replacing a nonzero allowance, consider setting
it to zero and waiting for confirmation before setting the new amount to reduce
the standard ERC-20 allowance replacement race. There is no administrative
recovery or emergency freeze mechanism.

## Dependencies and review

- [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2):
  the ERC-20 implementation and its four imported sources, with MIT license.
- [Forge Standard Library v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7):
  Solidity test utilities, with the upstream MIT and Apache-2.0 licenses.

`DEPENDENCIES.json` records immutable upstream commit IDs, archive hashes, and
SHA-256 checksums for each vendored file. No library linking is required.

The supplied security reference informed the review of access control, arithmetic,
zero-address handling, allowance rollback, supply conservation, and external
calls. This work uses compilation, unit tests, fuzzing, stateful invariants, and
manual source review. Slither and Mythril have not been run. These checks do not
replace an independent security audit or the network's protected launch tests.

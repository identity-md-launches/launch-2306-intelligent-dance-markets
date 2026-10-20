# Intelligent Dance Markets (IDM)

A fixed-supply ERC-20 token for the IdentityMD custom-token launch on Robinhood Chain.

| Item | Value |
| --- | --- |
| Solidity contract | `IDMToken` (`src/IDMToken.sol`) |
| Token name | Intelligent Dance Markets |
| Symbol | IDM |
| Decimals | 18 |
| Total supply | 1,000,000,000 IDM = `1000000000000000000000000000` minor units |
| Minting | Once, in the constructor, the whole supply to `msg.sender` (the deployer) |
| Constructor arguments | None |
| Owner / admin | None |

## What the token does

`IDMToken` is OpenZeppelin v5.7.0 `ERC20` with a constructor that mints `TOTAL_SUPPLY` to the
deployer, and nothing else. There is:

- no mint path after the constructor, by anyone, so the supply can never grow;
- no owner, `Ownable`, roles, pause, blocklist, freeze, seize or `burnFrom`;
- no transfer fee, tax, reflection or burn-on-transfer: every `transfer` and `transferFrom`
  moves exactly the amount asked for, and the launch flows arrive whole;
- no `receive` or `fallback`, so plain ether sent to the token reverts;
- no `delegatecall`, `callcode` or `selfdestruct` in the runtime bytecode, and no library with
  external linkage, so the creation code deploys as built.

Standard ERC-20 failure cases revert with OpenZeppelin's ERC-6093 custom errors
(`ERC20InsufficientBalance`, `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`,
`ERC20InvalidSpender`).

## Assumptions

- The deployer is whoever runs the constructor. On the IdentityMD launch that is the
  ProjectFactory, which receives the whole supply and pays it out itself: 10% to the launch's
  MerkleDistributor, 70% (`economics.poolBps = 7000`) to seed the Uniswap v4 pool, and the
  remaining 20% to `economics.remainderTo` (`0xff3E8d9bA776662Ca6Ed1420EE366AFB436d2684`). The
  token does not know or special-case any of these addresses; it does not need to, because it
  takes nothing from any transfer.
- The token takes no constructor arguments. The manifest's `constructorArgs` is the empty list.
- The compiler is pinned to solc 0.8.26 with the optimizer at 200 runs, `via_ir` off and
  `bytecode_hash = "none"`, so the deployed bytes are reproducible from this tree.
- `evm_version` is `cancun`. Robinhood Chain (chain id 4663) is an Arbitrum Nitro rollup at
  ArbOS 61, which executes Cancun opcodes. The contract itself uses no transient storage.

## Deployment parameters

The launch is performed by IdentityMD's deployer through the ProjectFactory; this repository does
not deploy, broadcast or hold keys. What the manifest step needs from this tree:

| Manifest field | Value |
| --- | --- |
| `token.contract` | `IDMToken` |
| `token.name` | `Intelligent Dance Markets` |
| `token.symbol` | `IDM` |
| `token.decimals` | `18` |
| `token.constructorArgs` | `[]` |
| `token.totalSupply` | `1000000000000000000000000000` |
| `contracts` | `[]` (no application contracts) |
| Chain | Robinhood Chain, chain id 4663 |
| Pair currency | IMD, `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| `pool.fee` | `12500` |
| `pool.tickSpacing` | `60` |
| `pool.initialPrice` | `79228162514264337593543950336` (provenance only; the deployer derives the opening price) |
| `economics` | `{"poolBps":7000,"initialMarketCapWei":"2500000000000000000000","remainderTo":"0xff3e8d9ba776662ca6ed1420ee366afb436d2684"}` |

`launch.json` is written by the manifest step after acceptance; it is deliberately not in this
tree.

`script/DeployIDMToken.s.sol` is a review and fork helper only. Its `deploy()` function takes no
configuration and is what the tests call; `run()` wraps it in a broadcast for an operator who
wants a local or test deployment with an account of their choosing.

## After launch

Nothing. The token has no owner-settable values, no outside dependencies and no post-deployment
configuration. There are no numbers the brief left open: name, symbol, decimals and supply are all
specified, and each is a named constant on the contract (`NAME`, `SYMBOL`, `DECIMALS`,
`TOTAL_SUPPLY`).

## Operational responsibilities

- **Nobody can intervene.** There is no admin key. Nobody can pause transfers, freeze an address,
  recover tokens sent to the wrong place, or change the supply. Holders are fully responsible for
  their own balances and approvals.
- **Approvals.** `approve` overwrites rather than adds, and an allowance of `type(uint256).max` is
  never decremented. Holders should grant bounded allowances to contracts they do not fully trust.
- **Tokens sent to the token contract itself** are unrecoverable, as with any plain ERC-20.
- **Robinhood Chain specifics.** `block.number` on Arbitrum Nitro chains returns the L1 block
  number; the token does not use it. The chain's transaction-filtering precompile can censor
  transactions at the sequencer level; that is a property of the chain, not of this token, and
  the token has no mechanism that depends on timely inclusion.
- **Explorer verification** after launch belongs to the launch's deployer. The source compiles
  reproducibly from this tree with the pinned settings in `foundry.toml`.
- **Security review.** The tests here are not an audit. The contract adds no logic beyond
  OpenZeppelin's audited `ERC20`, but an independent adversarial review before release remains the
  requester's responsibility, as with any launched contract.

## Repository layout

```
foundry.toml                  pinned solc 0.8.26, cancun, optimizer 200, bytecode_hash none
src/IDMToken.sol              the token
script/DeployIDMToken.s.sol   argument-free deploy helper (not used by the launch)
test/IDMToken.t.sol           ERC-20 unit and fuzz tests, success and failure paths
test/IDMTokenLaunchFlow.t.sol the launch's flows through a CREATE2 factory stand-in
test/DeployIDMToken.t.sol     the deploy helper's deploy() called directly
lib/forge-std                 forge-std v1.17.0, vendored as plain files
lib/openzeppelin-contracts    OpenZeppelin Contracts v5.7.0, vendored as plain files
```

Dependencies are committed as ordinary files, not submodules, so the project builds offline.

## Building and testing

```
forge build
forge test
forge fmt --check
```

The fuzz tests run with 512 runs per test (`[fuzz] runs` in `foundry.toml`) and pass with the
verifier's seed:

```
FOUNDRY_FUZZ_SEED=0x88469de555d37c84acf313d1c0c4c383075e20f9e448e64a7ce019881f9f4869 forge test
```

Tests read no environment variables, call no outside services and do not depend on their order.

## What is tested

Success paths: metadata; the one-time mint to the deployer with exactly one `Transfer` event;
`transfer` of zero, of the whole supply and to self; `approve` overwrite semantics; `transferFrom`
spending a bounded allowance and leaving an infinite one untouched; the launch split (10% / 70% /
20%) moving exactly and summing to the supply; the swarm share arriving whole at the distributor and
claimable whole; a pool-manager stand-in paying out and taking back exactly; CREATE2 deployment from
the bare creation code at a predictable address.

Failure paths: transfer over balance, from an empty account and to the zero address; approve to the
zero spender; `transferFrom` without, over and from a third party's allowance, and over the owner's
balance despite an allowance; every common mint, ownership, upgrade, pause, blocklist, freeze,
`burnFrom` and seize selector reverting whether called by a stranger or by the factory; the
deployer unable to pull from a holder without an allowance; plain ether rejected.

Fuzz: single and chained transfers conserve the supply and move exactly; over-balance transfers
always revert with the right error; `transferFrom` succeeds exactly when the amount is within the
allowance.

Bytecode: the runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`, and fits EIP-170.

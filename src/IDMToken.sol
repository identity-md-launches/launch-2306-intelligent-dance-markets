// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Intelligent Dance Markets (IDM)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 IDM (18 decimals) is minted once,
/// in the constructor, to the deployer. Nothing can mint afterwards, and nothing is privileged: there
/// is no owner, no pause, no blocklist, no fee and no burn hook. Every transfer moves exactly the
/// amount asked for.
/// @dev The Solidity identifier `IDMToken` is what the launch records (at most 32 characters); the
/// token's own name and symbol come from `name()` and `symbol()`. The contract takes no constructor
/// arguments, calls no other contract in its constructor, and uses no library with external linkage,
/// so its creation code deploys as built on an empty chain.
contract IDMToken is ERC20 {
    /// @notice The ERC-20 name.
    string public constant NAME = "Intelligent Dance Markets";

    /// @notice The ERC-20 symbol.
    string public constant SYMBOL = "IDM";

    /// @notice The ERC-20 decimals, the OpenZeppelin default.
    uint8 public constant DECIMALS = 18;

    /// @notice The whole supply in minor units: one billion tokens at 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Mints the whole supply once, to the deployer (`msg.sender`).
    /// @dev On the IdentityMD launch the deployer is the ProjectFactory, which then pays the supply out
    /// (the swarm's share to the MerkleDistributor, the pool share to the Uniswap v4 PoolManager and
    /// the remainder to the requester). There is no second mint path.
    constructor() ERC20(NAME, SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}

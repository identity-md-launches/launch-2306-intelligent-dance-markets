// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IDMToken} from "src/IDMToken.sol";

/// @notice Drives a closed set of holders through successful and rejected ERC-20 operations.
/// @dev The model starts from the required supply and changes only by requested amounts after
/// successful calls. It never copies balances or allowances back from the token under test.
contract IDMTokenHandler is Test {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant ACTOR_COUNT = 4;

    IDMToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        actors[0] = makeAddr("IDM invariant deployer");
        actors[1] = makeAddr("IDM invariant alice");
        actors[2] = makeAddr("IDM invariant bob");
        actors[3] = makeAddr("IDM invariant carol");

        vm.prank(actors[0]);
        token = new IDMToken();
        expectedBalance[actors[0]] = INITIAL_SUPPLY;

        // Fund every actor using real transfers, so the first random action can move value.
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            _transfer(actors[0], actors[i], INITIAL_SUPPLY / ACTOR_COUNT);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), _amount(amountSeed, expectedBalance[from]));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) external {
        // Exercise revocation, infinite approval, useful finite approval, and the full uint256 domain.
        if (mode % 4 == 0) amount = 0;
        else if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = bound(amount, 0, INITIAL_SUPPLY);
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        uint256 amount = _amount(amountSeed, limit);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");

        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 held = expectedBalance[from];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        token.transfer(_actor(toSeed), amount);
        // No model update: all balances and allowances must still match after rejection.
    }

    function transferFromAboveAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 approvalSeed,
        uint256 amountSeed
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = bound(approvalSeed, 0, INITIAL_SUPPLY);
        uint256 amount = bound(amountSeed, allowed + 1, type(uint256).max);
        _approve(owner, spender, allowed);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        token.transferFrom(owner, _actor(toSeed), amount);
    }

    function transferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 held = expectedBalance[owner];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        _approve(owner, spender, infinite ? type(uint256).max : amount);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        token.transferFrom(owner, _actor(toSeed), amount);
        // In particular, a finite allowance must survive the failed transfer unchanged.
    }

    function transferToZero(uint256 fromSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        uint256 amount = _amount(amountSeed, limit);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(owner, address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.prank(_actor(ownerSeed));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    function _amount(uint256 seed, uint256 limit) internal pure returns (uint256) {
        // Keep zero, one base unit, and the complete available balance/allowance common.
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return limit == 0 ? 0 : 1;
        if (seed % 4 == 2) return limit;
        return bound(seed, 0, limit);
    }
}

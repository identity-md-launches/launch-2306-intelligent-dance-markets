// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IDMToken} from "src/IDMToken.sol";

/// @notice Regression and property tests for allowance lifecycles, aliased accounts, and rejected calls.
/// forge-config: default.fuzz.runs = 1000
contract IDMTokenEdgeCasesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal deployer = makeAddr("edge deployer");
    address internal alice = makeAddr("edge alice");
    address internal bob = makeAddr("edge bob");
    address internal spender = makeAddr("edge spender");
    IDMToken internal token;

    function setUp() public {
        vm.prank(deployer);
        token = new IDMToken();
    }

    function test_oneBaseUnitIsTransferableInBothDirections() public {
        _transfer(deployer, alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        _transfer(alice, deployer, 1);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_wholeSupplyCanBeTransferredThroughAnExactAllowance() public {
        _approve(deployer, spender, SUPPLY);
        vm.prank(spender);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, SUPPLY);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));

        _assertBalances(0, SUPPLY, 0, 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_exhaustedAllowanceCannotBeSpentTwice() public {
        _approve(deployer, spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
        _assertBalances(SUPPLY - 1, 1, 0, 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_infiniteAllowanceCanBeRevokedAfterUse() public {
        _approve(deployer, spender, type(uint256).max);
        _approve(deployer, bob, 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max);

        vm.prank(deployer);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, 0);
        assertTrue(token.approve(spender, 0));

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.allowance(deployer, bob), 7, "revocation affected another spender");
        _assertBalances(SUPPLY - 1, 1, 0, 0);
    }

    function test_largestFiniteAllowanceStillDecrements() public {
        _approve(deployer, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);
        _assertBalances(SUPPLY - 1, 1, 0, 0);
    }

    function test_delegatedSelfTransferConsumesFiniteAllowance() public {
        _approve(deployer, spender, 1);
        vm.prank(spender);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, deployer, 1);
        assertTrue(token.transferFrom(deployer, deployer, 1));
        _assertBalances(SUPPLY, 0, 0, 0);
        assertEq(token.allowance(deployer, spender), 0);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, deployer, 1);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_ownerCallingTransferFromNeedsItsOwnAllowance() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
        _assertBalances(SUPPLY, 0, 0, 0);

        _approve(deployer, deployer, 1);
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        _assertBalances(SUPPLY - 1, 1, 0, 0);
    }

    function test_zeroTransfersFromEmptyAccountsStillEmitTransfer() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        assertTrue(token.transfer(bob, 0));

        // A valid zero-value transferFrom needs neither tokens nor a positive allowance.
        vm.prank(spender);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_zeroAmountsDoNotMakeZeroRecipientsOrSpendersValid() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(alice, address(0), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(alice, address(0)), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_zeroSourceCannotBeUsedEvenForAZeroDelegatedTransfer() public {
        vm.prank(spender);
        // Different ERC-20 versions validate the owner at different stages; rejection is required.
        vm.expectRevert();
        token.transferFrom(address(0), alice, 0);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_selfTransferStillRequiresEnoughBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(alice, 1);

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(deployer, SUPPLY + 1);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_maximumTransferRevertsWithBalanceError() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_infiniteAllowanceDoesNotBypassBalanceChecks() public {
        _approve(deployer, spender, type(uint256).max);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transferFrom(deployer, alice, type(uint256).max);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_approvalFromEmptyHolderCanBeUsedAfterReceivingTokens() public {
        _approve(alice, spender, type(uint256).max - 1);
        _assertBalances(SUPPLY, 0, 0, 0);
        _transfer(deployer, alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 1));
        assertEq(token.allowance(alice, spender), type(uint256).max - 2);
        _assertBalances(SUPPLY - 1, 0, 0, 1);
    }

    function testFuzz_insufficientBalancePreservesTheApprovedAllowance(uint256 held, uint256 attempt, bool infinite)
        public
    {
        held = bound(held, 0, SUPPLY);
        attempt = bound(attempt, held + 1, type(uint256).max - 1);
        uint256 allowed = infinite ? type(uint256).max : attempt;
        _transfer(deployer, alice, held);
        _approve(alice, spender, allowed);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, attempt));
        token.transferFrom(alice, bob, attempt);
        assertEq(token.allowance(alice, spender), allowed, "failed transfer consumed allowance");
        _assertBalances(SUPPLY - held, held, 0, 0);
    }

    function testFuzz_zeroRecipientPreservesTheApprovedAllowance(uint256 allowed, uint256 amount) public {
        amount = bound(amount, 0, allowed < SUPPLY ? allowed : SUPPLY);
        _approve(deployer, spender, allowed);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), amount);
        assertEq(token.allowance(deployer, spender), allowed, "invalid receiver consumed allowance");
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function testFuzz_overwritingApprovalIsIdempotentAndIsolated(
        uint256 original,
        uint256 replacement,
        uint256 otherSpender,
        uint256 otherOwner
    ) public {
        _approve(deployer, spender, original);
        _approve(deployer, bob, otherSpender);
        _approve(alice, spender, otherOwner);
        _approve(deployer, spender, replacement);
        assertEq(token.allowance(deployer, spender), replacement, "approve added instead of replacing");
        _approve(deployer, spender, replacement);
        assertEq(token.allowance(deployer, spender), replacement, "repeated approval changed the allowance");
        assertEq(token.allowance(deployer, bob), otherSpender, "another spender's approval changed");
        assertEq(token.allowance(alice, spender), otherOwner, "another owner's approval changed");
        assertEq(token.allowance(spender, deployer), 0, "approval was applied in reverse");
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function testFuzz_twoSpendersCannotExceedTheOwnersBalance(uint256 held, uint256 firstSpend) public {
        held = bound(held, 1, SUPPLY);
        firstSpend = bound(firstSpend, 0, held);
        _transfer(deployer, alice, held);
        _approve(alice, bob, held);
        _approve(alice, spender, held + 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, deployer, firstSpend));

        uint256 remaining = held - firstSpend;
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, remaining, remaining + 1)
        );
        token.transferFrom(alice, deployer, remaining + 1);
        assertEq(token.allowance(alice, bob), remaining);
        assertEq(token.allowance(alice, spender), held + 1, "failed spend changed independent approval");
        _assertBalances(SUPPLY - remaining, remaining, 0, 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, deployer, remaining));
        assertEq(token.allowance(alice, spender), firstSpend + 1);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function testFuzz_roundTripRestoresBothBalances(uint256 initiallyHeld, uint256 amount) public {
        initiallyHeld = bound(initiallyHeld, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY - initiallyHeld);
        _transfer(deployer, bob, initiallyHeld);
        _transfer(deployer, bob, amount);
        _assertBalances(SUPPLY - initiallyHeld - amount, 0, initiallyHeld + amount, 0);
        _transfer(bob, deployer, amount);
        _assertBalances(SUPPLY - initiallyHeld, 0, initiallyHeld, 0);
    }

    function testFuzz_delegatedSelfTransferPreservesBalanceAndSpendsAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(deployer, spender, infinite ? type(uint256).max : amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, amount));
        assertEq(token.allowance(deployer, spender), infinite ? type(uint256).max : 0);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function _approve(address owner, address authorized, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(authorized, amount));
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function _assertBalances(uint256 deployerHeld, uint256 aliceHeld, uint256 bobHeld, uint256 spenderHeld)
        internal
        view
    {
        assertEq(token.totalSupply(), SUPPLY, "total supply changed");
        assertEq(token.balanceOf(deployer), deployerHeld, "deployer balance");
        assertEq(token.balanceOf(alice), aliceHeld, "alice balance");
        assertEq(token.balanceOf(bob), bobHeld, "bob balance");
        assertEq(token.balanceOf(spender), spenderHeld, "spender balance");
        assertEq(token.balanceOf(address(0)), 0, "tokens credited to zero");
    }
}

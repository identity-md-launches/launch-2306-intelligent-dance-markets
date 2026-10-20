// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IDMToken} from "src/IDMToken.sol";
import {IDMTokenHandler} from "./handlers/IDMTokenHandler.sol";

/// @notice Supply, individual balances, authorization, and transfer liveness across random sequences.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IDMTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    IDMTokenHandler internal handler;
    IDMToken internal token;

    function setUp() public {
        handler = new IDMTokenHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferAboveBalance.selector;
        selectors[4] = handler.transferFromAboveAllowance.selector;
        selectors[5] = handler.transferFromAboveBalance.selector;
        selectors[6] = handler.transferToZero.selector;
        selectors[7] = handler.transferFromToZero.selector;
        selectors[8] = handler.approveZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixedAndAllTokensAreAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed after deployment");
        assertEq(sum, SUPPLY, "tokens appeared or disappeared from the closed actor set");
        assertEq(token.balanceOf(address(0)), 0, "zero address acquired tokens");
    }

    function invariant_eachBalanceMatchesAuthorizedTransfers() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "balance differs from the transfer ledger");
        }
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpending() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0, "zero spender was approved");
            assertEq(token.allowance(address(0), owner), 0, "zero owner granted an allowance");
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance changed without approval or successful spending"
                );
            }
        }
    }

    /// @dev After every campaign, every holder must still be able to move its entire balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < handler.ACTOR_COUNT(); ++i) {
            handler.transfer(i, 0, 2); // Amount seed 2 selects the holder's complete balance.
            assertEq(token.balanceOf(handler.actors(i)), 0, "holder could not transfer its whole balance");
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY, "full supply could not be reunited");
        invariant_supplyIsFixedAndAllTokensAreAccountedFor();
        invariant_eachBalanceMatchesAuthorizedTransfers();
        invariant_allowancesMatchApprovalsAndSuccessfulSpending();
    }
}

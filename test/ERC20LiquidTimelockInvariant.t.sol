// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20LiquidTimelockMock} from "./mocks/ERC20LiquidTimelockMock.sol";
import {ERC20LiquidTimelockHandler} from "./utils/ERC20LiquidTimelockHandler.sol";

/**
 * @notice Model-based stateful tests for arbitrary combinations of mints,
 *         transfers, burns, and block advances.
 */
contract ERC20LiquidTimelockInvariantTest is StdInvariant, Test {
    ERC20LiquidTimelockMock internal token;
    ERC20LiquidTimelockHandler internal handler;

    function setUp() public {
        token = new ERC20LiquidTimelockMock();
        handler = new ERC20LiquidTimelockHandler(token);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.mint.selector;
        selectors[1] = handler.transfer.selector;
        selectors[2] = handler.burnUnlocked.selector;
        selectors[3] = handler.attemptRestrictedBurn.selector;
        selectors[4] = handler.rollBlock.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /**
     * @dev The implementation must agree account-by-account with the shadow
     *      ledger after every generated action sequence.
     */
    function invariant_ShadowLedgerMatchesToken() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address account = handler.actorAt(i);
            uint256 modeledBalance = handler.modelBalance(account);
            uint256 modeledTimelocked = handler.modelTimelocked(account);

            assertEq(token.balanceOf(account), modeledBalance);
            assertEq(token.timelockedBalanceOf(account), modeledTimelocked);
            assertEq(token.unlockedBalanceOf(account), modeledBalance - modeledTimelocked);
            assertLe(modeledTimelocked, modeledBalance);
        }
    }

    /**
     * @dev Mints are the only operation that can increase active timelock in
     *      a block. Transfers conserve it and permitted burns leave it intact.
     */
    function invariant_TimelockedBalanceIsConservedWithinBlock() public view {
        uint256 observedTimelocked;

        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            observedTimelocked += token.timelockedBalanceOf(handler.actorAt(i));
        }

        assertEq(observedTimelocked, handler.modelTotalTimelocked());
        assertEq(observedTimelocked, handler.mintedInCurrentBlock());
        assertLe(observedTimelocked, token.totalSupply());
    }

    /**
     * @dev All supply remains inside the closed actor set, including after
     *      arbitrary splits, merges, transfer chains, and successful burns.
     */
    function invariant_TotalSupplyEqualsSumOfBalances() public view {
        uint256 observedSupply;

        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            observedSupply += token.balanceOf(handler.actorAt(i));
        }

        assertEq(observedSupply, token.totalSupply());
        assertEq(observedSupply, handler.modelTotalSupply());
    }

    /**
     * @dev Summed per-account unlocked balances equal total supply less the
     *      globally conserved active timelock.
     */
    function invariant_UnlockedSupplyAccountingIsExact() public view {
        uint256 observedUnlocked;

        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            observedUnlocked += token.unlockedBalanceOf(handler.actorAt(i));
        }

        assertEq(observedUnlocked, token.totalSupply() - handler.modelTotalTimelocked());
    }
}

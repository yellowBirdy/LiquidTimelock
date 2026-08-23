// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20LiquidTimelock
 * @notice Makes freshly minted ERC-20 tokens non-burnable for the remainder
 *         of their mint block without restricting transfers.
 * @dev A timelocked balance is an accounting property, not a frozen set of
 *      individual token units. Transfers spend unlocked balance first. If a
 *      transfer exceeds the sender's unlocked balance, the excess timelocked
 *      amount follows the transfer to the recipient.
 *
 *      For every block, ordinary transfers conserve the sum of all active
 *      timelocked balances. Mints increase that sum, burns cannot decrease it,
 *      and advancing to the next block expires every active restriction.
 *
 *      Expired records are ignored rather than eagerly deleted. Any later
 *      restricted receipt overwrites stale state, so expiry needs no global
 *      account iteration.
 */
contract ERC20LiquidTimelock is ERC20 {
    /**
     * @notice A burn exceeded an account's currently unlocked balance.
     * @param account Account from which the burn was attempted.
     * @param missingUnlockedBalance balance to be burned that is timelocked.
     */
    error ERC20InsufficientUnlockedBalance(address account, uint256 missingUnlockedBalance);

    /**
     * @dev Amount recorded as timelocked in `_timelockedAtBlock[account]`.
     */
    mapping(address account => uint256 amount) private _timelockedBalance;

    /**
     * @dev Block in which an account's recorded timelock is active.
     */
    mapping(address account => uint256 blockNumber) private _timelockedAtBlock;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /**
     * @notice Returns the part of `account`'s balance that cannot be burned in
     *         the current block.
     * @dev Returns zero for stale records from earlier blocks.
     */
    function timelockedBalanceOf(address account) public view virtual returns (uint256) {
        return _timelockedAtBlock[account] == block.number ? _timelockedBalance[account] : 0;
    }

    /**
     * @notice Returns the part of `account`'s balance currently available to
     *         burn.
     */
    function unlockedBalanceOf(address account) public view virtual returns (uint256) {
        uint256 accountBalance = balanceOf(account);
        uint256 timelockedBalance = timelockedBalanceOf(account);
        return accountBalance > timelockedBalance ? accountBalance - timelockedBalance : 0;
    }

    /**
     * @dev Applies timelock accounting to every ERC-20 mint, burn, and
     *      transfer performed through OpenZeppelin's standard internal API.
     *
     *      `super._update` runs first so balance and supply validation remains
     *      canonical and the accounting below reads post-operation balances.
     *      Any later revert rolls the parent state update back atomically.
     *
     *      Mint: the minted amount becomes timelocked on the recipient.
     *      Burn: only the account's unlocked balance may be consumed.
     *      Transfer: unlocked balance is consumed first; only the excess
     *      timelocked amount moves to the recipient.
     *
     *      Zero-value operations do not alter timelock state. Self-transfers
     *      retain the exact state while preserving ERC-20 balance checks.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
        // Zero-value operations and Self-transfers do not alter timelock state.
        if (value == 0 || from == to) return;

        // Mint: restrict the actual recipient after ERC-20 updates its balance.
        if (from == address(0)) {
            if (value != 0) _increaseTimelock(to, value);
            return;
        }

        uint256 fromTimelockedBalance = timelockedBalanceOf(from);
        uint256 fromPostBurnBalance = balanceOf(from);
        // If from account balance falls below timelocked balance
        // Burn is prevented
        // Timelocked fraction of the transfer amount is moved from the sender to the recipient's timelock.
        if (fromPostBurnBalance < fromTimelockedBalance) {
            // Burn: post-burn balance must still cover every timelocked token.
            uint256 touchedTimelockedValue = fromTimelockedBalance - fromPostBurnBalance;
            if (to == address(0)) {
                revert ERC20InsufficientUnlockedBalance(from, fromTimelockedBalance - fromPostBurnBalance);
            }

            // Transfer

            // Any timelocked tokens transfered are removed from the sender's timeloc and added to the recipient's timelock.

            _setTimelock(from, fromPostBurnBalance);
            _increaseTimelock(to, touchedTimelockedValue);
        }
    }

    /**
     * @dev Adds a restricted receipt to `account` in the current block.
     *      Existing active receipts accumulate; stale records are replaced.
     */
    function _increaseTimelock(address account, uint256 amount) private {
        _setTimelock(account, timelockedBalanceOf(account) + amount);
    }

    /**
     * @dev Stores an active restriction, deleting empty records to avoid
     *      leaving an unnecessary current-block marker.
     */
    function _setTimelock(address account, uint256 amount) private {
        if (amount == 0) {
            delete _timelockedBalance[account];
            delete _timelockedAtBlock[account];
        } else {
            _timelockedBalance[account] = amount;
            _timelockedAtBlock[account] = block.number;
        }
    }
}

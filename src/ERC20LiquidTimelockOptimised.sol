// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solady/tokens/ERC20.sol";

contract ERC20LiquidTimelockOptimised is ERC20 {
    error InsufficientUnlockedBalance();
    /// @dev bytes4(keccak256("_TIMELOCKS_SLOT_SEED")

    string private _name;
    string private _symbol;

    uint256 private constant _TIMELOCKS_SLOT_SEED = 0xa29895c4;
    /// @dev The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _TIMELOCKS_SLOT_SEED)
    ///     mstore(0x00, account)
    ///     let timelockSlot := keccak256(0x0c, 0x20)
    /// ```

    constructor(string memory name, string memory symbol) {
        _name = name;
        _symbol = symbol;
    }

    function timelock(address account) public view returns (uint56 lockedAt, uint200 amount) {
        assembly ("memory-safe") {
            mstore(0x0c, _TIMELOCKS_SLOT_SEED)
            mstore(0x00, account)
            amount := sload(keccak256(0x0c, 0x20))
            lockedAt := and(amount, 0xFFFFFFFFFFFFFF)
            amount := shr(56, amount)
        }
    }

    function timelockedBalanceOf(address account) public view returns (uint256) {
        (, uint200 amount) = timelock(account);
        return uint256(amount);
    }

    function unlockedBalanceOf(address account) public view returns (uint256) {
        return balanceOf(account) - timelockedBalanceOf(account);
    }

    function _setTimelock(address account, uint256 amount) private {
        assembly ("memory-safe") {
            mstore(0x0c, _TIMELOCKS_SLOT_SEED)
            mstore(0x00, account)
            sstore(keccak256(0x0c, 0x20), or(number(), shl(56, amount)))
        }
    }

    function _increaseTimelock(address account, uint256 amount) private {
        assembly ("memory-safe") {
            mstore(0x0c, _TIMELOCKS_SLOT_SEED)
            mstore(0x00, account)
            let slot := keccak256(0x0c, 0x20)
            let current := sload(slot)
            if eq(and(current, 0xFFFFFFFFFFFFFF), number()) { amount := add(amount, shr(56, current)) }
            sstore(slot, or(number(), shl(56, amount)))
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        /// @notice mint
        if (from == address(0)) {
            _increaseTimelock(to, amount);
            return;
        }

        /// @notice burn
        if (to == address(0)) {
            if (unlockedBalanceOf(from) < amount) revert InsufficientUnlockedBalance();
            return;
        }

        /// @notice transfer
        uint256 sendersUnlockedBalance = unlockedBalanceOf(from);
        uint256 sendersTimelockedBalance = timelockedBalanceOf(from);
        uint256 lockedAmountTransferred;
        if (amount > sendersUnlockedBalance) {
            lockedAmountTransferred = amount - sendersUnlockedBalance;
        }
        _increaseTimelock(to, lockedAmountTransferred);
        _setTimelock(from, sendersTimelockedBalance - lockedAmountTransferred);
        return;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }
}

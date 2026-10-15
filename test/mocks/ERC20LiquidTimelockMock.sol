// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20LiquidTimelock} from "../../src/ERC20LiquidTimelock.sol";

/**
 * @dev Permissionless mint/burn harness used only to exercise the base pattern.
 */
contract ERC20LiquidTimelockMock is ERC20LiquidTimelock {
    constructor() ERC20LiquidTimelock("Liquid Timelock", "LIQUID") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

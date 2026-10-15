// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20LiquidTimelock} from "../../src/ERC20LiquidTimelock.sol";
import {ERC20LiquidTimelockMock} from "../mocks/ERC20LiquidTimelockMock.sol";

/**
 * @notice Stateful fuzz handler with an independent shadow ledger.
 * @dev Every action updates both the token and a deliberately simple model.
 *      Invariants compare the two after arbitrary action sequences.
 */
contract ERC20LiquidTimelockHandler is Test {
    uint256 public constant ACTOR_COUNT = 6;
    uint256 private constant MAX_ACTION_AMOUNT = 1e24;

    ERC20LiquidTimelockMock public immutable token;

    mapping(address actor => uint256 balance) public modelBalance;
    mapping(address actor => uint256 amount) public modelTimelocked;

    uint256 public modelTotalSupply;
    uint256 public modelTotalTimelocked;
    uint256 public mintedInCurrentBlock;
    uint256 public rejectedRestrictedBurns;

    constructor(ERC20LiquidTimelockMock token_) {
        token = token_;
    }

    /**
     * @notice Mints a bounded amount to a fuzz-selected actor.
     */
    function mint(uint256 actorSeed, uint256 rawAmount) external {
        address account = actorAt(actorSeed);
        uint256 amount = bound(rawAmount, 0, MAX_ACTION_AMOUNT);

        token.mint(account, amount);

        modelBalance[account] += amount;
        modelTimelocked[account] += amount;
        modelTotalSupply += amount;
        modelTotalTimelocked += amount;
        mintedInCurrentBlock += amount;
    }

    /**
     * @notice Transfers any bounded balance, including zero, self, dust, and
     *         full-balance transfers.
     */
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actorAt(fromSeed);
        address to = actorAt(toSeed);
        uint256 amount = bound(rawAmount, 0, modelBalance[from]);

        vm.prank(from);
        bool success = token.transfer(to, amount);
        assertTrue(success);

        if (from == to) return;

        uint256 unlocked = modelBalance[from] - modelTimelocked[from];
        uint256 movedTimelocked = amount > unlocked ? amount - unlocked : 0;

        modelBalance[from] -= amount;
        modelBalance[to] += amount;
        modelTimelocked[from] -= movedTimelocked;
        modelTimelocked[to] += movedTimelocked;
    }

    /**
     * @notice Burns a fuzz-selected amount that the model says is unlocked.
     */
    function burnUnlocked(uint256 actorSeed, uint256 rawAmount) external {
        address account = actorAt(actorSeed);
        uint256 unlocked = modelBalance[account] - modelTimelocked[account];
        uint256 amount = bound(rawAmount, 0, unlocked);

        token.burn(account, amount);

        modelBalance[account] -= amount;
        modelTotalSupply -= amount;
    }

    /**
     * @notice Attempts a burn one unit beyond unlocked capacity and proves
     *         that the token rejects it without changing either ledger.
     */
    function attemptRestrictedBurn(uint256 actorSeed, uint256 rawExcess) external {
        address account = actorAt(actorSeed);
        uint256 timelocked = modelTimelocked[account];
        if (timelocked == 0) return;

        uint256 unlocked = modelBalance[account] - timelocked;
        uint256 excess = bound(rawExcess, 1, timelocked);
        uint256 amount = unlocked + excess;

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20LiquidTimelock.ERC20InsufficientUnlockedBalance.selector, account, unlocked, amount
            )
        );
        token.burn(account, amount);
        ++rejectedRestrictedBurns;
    }

    /**
     * @notice Advances at least one block, expiring every modeled timelock.
     */
    function rollBlock(uint8 rawDelta) external {
        uint256 delta = bound(uint256(rawDelta), 1, 8);
        vm.roll(block.number + delta);

        for (uint256 i; i < ACTOR_COUNT; ++i) {
            modelTimelocked[actorAt(i)] = 0;
        }

        modelTotalTimelocked = 0;
        mintedInCurrentBlock = 0;
    }

    /**
     * @notice Returns one member of the closed actor set used by the model.
     */
    function actorAt(uint256 seed) public pure returns (address) {
        uint256 index = seed % ACTOR_COUNT;
        if (index == 0) return address(0xA11CE);
        if (index == 1) return address(0xB0B);
        if (index == 2) return address(0xCA401);
        if (index == 3) return address(0xDA7E);
        if (index == 4) return address(0xE11E);
        return address(0xF12A);
    }
}

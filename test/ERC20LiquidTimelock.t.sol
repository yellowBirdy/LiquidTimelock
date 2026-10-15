// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20LiquidTimelock} from "../src/ERC20LiquidTimelock.sol";
import {ERC20LiquidTimelockMock} from "./mocks/ERC20LiquidTimelockMock.sol";

contract ERC20LiquidTimelockTest is Test {
    ERC20LiquidTimelockMock internal token;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);
    address internal constant DAVE = address(0xDA7E);

    function setUp() public {
        token = new ERC20LiquidTimelockMock();
    }

    function test_MintRestrictsRecipientRatherThanCaller() public {
        token.mint(ALICE, 100);

        assertEq(token.timelockedBalanceOf(ALICE), 100);
        assertEq(token.unlockedBalanceOf(ALICE), 0);
        assertEq(token.timelockedBalanceOf(address(this)), 0);
    }

    function test_TransferSpendsUnlockedBalanceFirstAndMovesOnlyRestrictedRemainder() public {
        token.mint(ALICE, 100);
        vm.roll(block.number + 1);
        token.mint(ALICE, 40);

        vm.prank(ALICE);
        token.transfer(BOB, 120);

        assertEq(token.timelockedBalanceOf(ALICE), 20);
        assertEq(token.timelockedBalanceOf(BOB), 20);
        assertEq(token.balanceOf(ALICE), 20);
        assertEq(token.balanceOf(BOB), 120);
    }

    function test_BurnRevertsWhenItConsumesRestrictedBalance() public {
        token.mint(ALICE, 100);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20LiquidTimelock.ERC20InsufficientUnlockedBalance.selector, ALICE, 0, 1)
        );
        token.burn(ALICE, 1);
    }

    function test_RestrictionExpiresAtTheStartOfTheNextBlock() public {
        token.mint(ALICE, 100);
        vm.roll(block.number + 1);

        assertEq(token.timelockedBalanceOf(ALICE), 0);
        assertEq(token.unlockedBalanceOf(ALICE), 100);

        token.burn(ALICE, 100);
        assertEq(token.totalSupply(), 0);
    }

    function test_MultipleRestrictedReceiptsInOneBlockAccumulate() public {
        token.mint(ALICE, 10);
        token.mint(ALICE, 15);
        token.mint(BOB, 20);

        vm.prank(BOB);
        token.transfer(ALICE, 20);

        assertEq(token.timelockedBalanceOf(ALICE), 45);
        assertEq(token.timelockedBalanceOf(BOB), 0);
        assertEq(token.unlockedBalanceOf(ALICE), 0);
    }

    function test_SplitAndMergeConservesTimelockedBalance() public {
        token.mint(ALICE, 100);

        vm.startPrank(ALICE);
        token.transfer(BOB, 31);
        token.transfer(CAROL, 69);
        vm.stopPrank();

        vm.prank(BOB);
        token.transfer(DAVE, 31);
        vm.prank(CAROL);
        token.transfer(DAVE, 69);

        assertEq(token.timelockedBalanceOf(ALICE), 0);
        assertEq(token.timelockedBalanceOf(BOB), 0);
        assertEq(token.timelockedBalanceOf(CAROL), 0);
        assertEq(token.timelockedBalanceOf(DAVE), 100);
    }

    function test_DustTransferCarriesOneUnitOfTimelockThroughChain() public {
        token.mint(ALICE, 100);

        vm.prank(ALICE);
        token.transfer(BOB, 1);
        vm.prank(BOB);
        token.transfer(CAROL, 1);
        vm.prank(CAROL);
        token.transfer(DAVE, 1);

        assertEq(token.timelockedBalanceOf(ALICE), 99);
        assertEq(token.timelockedBalanceOf(BOB), 0);
        assertEq(token.timelockedBalanceOf(CAROL), 0);
        assertEq(token.timelockedBalanceOf(DAVE), 1);
    }

    function test_SelfTransferDoesNotChangeTimelockAccounting() public {
        token.mint(ALICE, 100);

        vm.prank(ALICE);
        token.transfer(ALICE, 60);

        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.timelockedBalanceOf(ALICE), 100);
        assertEq(token.unlockedBalanceOf(ALICE), 0);
    }

    function test_ZeroTransferDoesNotChangeEitherAccountTimelock() public {
        token.mint(ALICE, 100);
        token.mint(BOB, 50);

        vm.prank(ALICE);
        token.transfer(BOB, 0);

        assertEq(token.timelockedBalanceOf(ALICE), 100);
        assertEq(token.timelockedBalanceOf(BOB), 50);
    }

    function test_ZeroMintDoesNotCreateRestriction() public {
        token.mint(ALICE, 0);

        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.timelockedBalanceOf(ALICE), 0);
    }

    function test_MintTransferBurnConsumesOnlyUnlockedTokens() public {
        // These tokens expire first and provide unlocked capacity after transfer.
        token.mint(ALICE, 50);
        vm.roll(block.number + 1);
        token.mint(ALICE, 30);

        vm.prank(ALICE);
        token.transfer(BOB, 60);

        assertEq(token.timelockedBalanceOf(ALICE), 20);
        assertEq(token.timelockedBalanceOf(BOB), 10);
        assertEq(token.unlockedBalanceOf(BOB), 50);

        token.burn(BOB, 50);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20LiquidTimelock.ERC20InsufficientUnlockedBalance.selector, BOB, 0, 1)
        );
        token.burn(BOB, 1);

        vm.roll(block.number + 1);
        token.burn(BOB, 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testFuzz_ArbitraryTransferChainPreservesRestriction(uint96 rawAmount, uint8 rawHops) public {
        uint256 amount = bound(uint256(rawAmount), 1, type(uint96).max);
        uint256 hops = bound(uint256(rawHops), 1, 4);
        address[5] memory actors = [ALICE, BOB, CAROL, DAVE, address(0xE11E)];

        token.mint(actors[0], amount);

        for (uint256 i; i < hops; ++i) {
            vm.prank(actors[i]);
            token.transfer(actors[i + 1], amount);

            assertEq(token.timelockedBalanceOf(actors[i]), 0);
            assertEq(token.timelockedBalanceOf(actors[i + 1]), amount);
        }
    }

    function testFuzz_SplittingAndMergingConservesRestriction(uint96 rawFirst, uint96 rawSecond) public {
        uint256 first = bound(uint256(rawFirst), 1, type(uint96).max);
        uint256 second = bound(uint256(rawSecond), 1, type(uint96).max);
        uint256 total = first + second;

        token.mint(ALICE, total);

        vm.startPrank(ALICE);
        token.transfer(BOB, first);
        token.transfer(CAROL, second);
        vm.stopPrank();

        vm.prank(BOB);
        token.transfer(DAVE, first);
        vm.prank(CAROL);
        token.transfer(DAVE, second);

        assertEq(token.timelockedBalanceOf(DAVE), total);
        assertEq(token.balanceOf(DAVE), total);
    }

    function testFuzz_TransfersUnlockedBalanceBeforeRestriction(
        uint96 rawUnlocked,
        uint96 rawRestricted,
        uint96 rawTransfer
    ) public {
        uint256 unlocked = uint256(rawUnlocked);
        uint256 restricted = uint256(rawRestricted);
        uint256 total = unlocked + restricted;
        uint256 transferAmount = bound(uint256(rawTransfer), 0, total);

        token.mint(ALICE, unlocked);
        vm.roll(block.number + 1);
        token.mint(ALICE, restricted);

        vm.prank(ALICE);
        token.transfer(BOB, transferAmount);

        uint256 expectedMoved = transferAmount > unlocked ? transferAmount - unlocked : 0;
        assertEq(token.timelockedBalanceOf(BOB), expectedMoved);
        assertEq(token.timelockedBalanceOf(ALICE), restricted - expectedMoved);
    }

    function testFuzz_BurnAcceptsExactlyUnlockedBalance(uint96 rawUnlocked, uint96 rawRestricted, uint96 rawBurn)
        public
    {
        uint256 unlocked = uint256(rawUnlocked);
        uint256 restricted = uint256(rawRestricted);
        uint256 total = unlocked + restricted;
        uint256 burnAmount = bound(uint256(rawBurn), 0, total);

        token.mint(ALICE, unlocked);
        vm.roll(block.number + 1);
        token.mint(ALICE, restricted);

        if (burnAmount <= unlocked) {
            token.burn(ALICE, burnAmount);
            assertEq(token.timelockedBalanceOf(ALICE), restricted);
            assertEq(token.balanceOf(ALICE), total - burnAmount);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ERC20LiquidTimelock.ERC20InsufficientUnlockedBalance.selector, ALICE, unlocked, burnAmount
                )
            );
            token.burn(ALICE, burnAmount);
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {MockStaking721} from "./MockStaking721.sol";
import {StakingToken} from "./StakingToken.sol";

contract Staking721Test is Test {
    MockStaking721 staking721;
    StakingToken stakingToken;

    address Alice = makeAddr("Alice");
    address Bob = makeAddr("Bob");

    function setUp() public {
        stakingToken = new StakingToken();
        staking721 = new MockStaking721(address(stakingToken));
    }

    function testStake() public {
        uint256[] memory aliceTokenIds = new uint256[](2);
        aliceTokenIds[0] = 1;
        aliceTokenIds[1] = 2;

        uint256[] memory bobTokenIds = new uint256[](2);
        bobTokenIds[0] = 3;
        bobTokenIds[1] = 4;

        _stake(aliceTokenIds, bobTokenIds);
    }

    function testGetStakeInfo() public {
        uint256[] memory aliceTokenIds = new uint256[](2);
        aliceTokenIds[0] = 1;
        aliceTokenIds[1] = 2;

        uint256[] memory bobTokenIds = new uint256[](2);
        bobTokenIds[0] = 3;
        bobTokenIds[1] = 4;

        _stake(aliceTokenIds, bobTokenIds);

        (uint256[] memory aliceTokens, uint256 aliceRewards) = staking721.getStakeInfo(Alice);
        assertEq(aliceTokens.length, 2, "Alice should have 2 tokens staked");
        assertEq(aliceRewards, 0, "Alice should have 0 rewards");

        (uint256[] memory bobTokens, uint256 bobRewards) = staking721.getStakeInfo(Bob);
        assertEq(bobTokens.length, 2, "Bob should have 2 tokens staked");
        assertEq(bobRewards, 0, "Bob should have 0 rewards");
    }

    function testWithdraw() public {
        uint256[] memory aliceTokenIds = new uint256[](2);
        aliceTokenIds[0] = 1;
        aliceTokenIds[1] = 2;

        uint256[] memory bobTokenIds = new uint256[](2);
        bobTokenIds[0] = 3;
        bobTokenIds[1] = 4;

        _stake(aliceTokenIds, bobTokenIds);
        vm.startPrank(Alice);
        staking721.withdraw(aliceTokenIds);
        vm.stopPrank();

        vm.startPrank(Bob);
        staking721.withdraw(bobTokenIds);
        vm.stopPrank();

        (uint256[] memory aliceTokens, uint256 aliceRewards) = staking721.getStakeInfo(Alice);
        assertEq(aliceTokens.length, 0, "Alice should have 0 tokens staked");
        assertEq(aliceRewards, 0, "Alice should have 0 rewards");

        (uint256[] memory bobTokens, uint256 bobRewards) = staking721.getStakeInfo(Bob);
        assertEq(bobTokens.length, 0, "Bob should have 0 tokens staked");
        assertEq(bobRewards, 0, "Bob should have 0 rewards");
    }

    function testClaimRewards() public {
        uint256[] memory aliceTokenIds = new uint256[](2);
        aliceTokenIds[0] = 1;
        aliceTokenIds[1] = 2;

        uint256[] memory bobTokenIds = new uint256[](2);
        bobTokenIds[0] = 3;
        bobTokenIds[1] = 4;

        _stake(aliceTokenIds, bobTokenIds);

        vm.startPrank(Alice);
        vm.expectRevert("No rewards");
        staking721.claimRewards();
        vm.stopPrank();

        vm.startPrank(Bob);
        vm.expectRevert("No rewards");
        staking721.claimRewards();
        vm.stopPrank();
    }

    function _stake(uint256[] memory aliceTokenIds, uint256[] memory bobTokenIds) internal {
        _mintTokens(Alice, aliceTokenIds);
        _mintTokens(Bob, bobTokenIds);

        vm.startPrank(Alice);
        stakingToken.approve(address(staking721), 1);
        stakingToken.approve(address(staking721), 2);
        staking721.stake(aliceTokenIds);
        vm.stopPrank();

        vm.startPrank(Bob);
        stakingToken.approve(address(staking721), 3);
        stakingToken.approve(address(staking721), 4);
        staking721.stake(bobTokenIds);
        vm.stopPrank();

        address ownerToken1 = staking721.stakerAddress(1);
        address ownerToken2 = staking721.stakerAddress(2);
        address ownerToken3 = staking721.stakerAddress(3);
        address ownerToken4 = staking721.stakerAddress(4);

        assertEq(ownerToken1, Alice, "Token 1 should be staked by Alice");
        assertEq(ownerToken2, Alice, "Token 2 should be staked by Alice");
        assertEq(ownerToken3, Bob, "Token 3 should be staked by Bob");
        assertEq(ownerToken4, Bob, "Token 4 should be staked by Bob");
    }

    function _mintTokens(address to, uint256[] memory tokenIds) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            stakingToken.mint(to, tokenIds[i]);
        }
    }
}

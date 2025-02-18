// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Staking721Optimized} from "../src/Staking721Optimized.sol";

contract MockStaking721Optimized is Staking721Optimized {
    constructor(address _stakingToken) Staking721Optimized(_stakingToken) {}

    function getRewardTokenBalance() external view override returns (uint256 _rewardsAvailableInContract) {
        _rewardsAvailableInContract = 100;
    }

    function _canSetStakeConditions() internal view override returns (bool) {
        return true;
    }

    function _mintRewards(address _staker, uint256 _rewards) internal override {}
}

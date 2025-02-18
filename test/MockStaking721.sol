// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Staking721} from "../src/Staking721.sol";

contract MockStaking721 is Staking721 {
    constructor(address _stakingToken) Staking721(_stakingToken) {}

    function getRewardTokenBalance() external view override returns (uint256 _rewardsAvailableInContract) {
        _rewardsAvailableInContract = 100;
    }

    function _canSetStakeConditions() internal view override returns (bool) {
        return true;
    }

    function _mintRewards(address _staker, uint256 _rewards) internal override {}
}

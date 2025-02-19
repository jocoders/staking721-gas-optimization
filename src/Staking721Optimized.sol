// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IStaking721} from "../interfaces/IStaking721.sol";

/**
 * @title Staking721Optimized
 * @notice An optimized contract for staking ERC-721 tokens and earning rewards.
 * @dev Implements staking conditions, reward calculations, and permission checks.
 */
abstract contract Staking721Optimized is IStaking721 {
    address public immutable stakingToken;
    uint64 private nextConditionId;
    uint8 internal isStaking = 1;

    mapping(uint256 => bool) public isIndexed;
    mapping(address => Staker) public stakers;
    mapping(uint256 => address) public stakerAddress;
    mapping(address => uint256[]) public stakerTokens;
    mapping(uint256 => StakingCondition) private stakingConditions;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    error NotAuthorized();

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    /**
     * @notice Initializes the staking contract with the given ERC-721 token.
     * @param _stakingToken The address of the ERC-721 token that can be staked.
     */
    constructor(address _stakingToken) {
        require(_stakingToken != address(0), "collection address 0");
        stakingToken = _stakingToken;
    }

    /**
     * @notice Allows a user to stake multiple NFTs.
     * @param _tokenIds The list of token IDs to stake.
     */
    function stake(uint256[] calldata _tokenIds) external nonReentrant {
        _stake(_tokenIds);
    }

    /**
     * @notice Allows a user to withdraw staked NFTs.
     * @param _tokenIds The list of token IDs to withdraw.
     */
    function withdraw(uint256[] calldata _tokenIds) external nonReentrant {
        _withdraw(_tokenIds);
    }

    /**
     * @notice Allows a user to claim earned rewards.
     */
    function claimRewards() external nonReentrant {
        _claimRewards();
    }

    /**
     * @notice Allows a user to set the time unit for staking rewards.
     * @param _timeUnit The time unit for staking rewards.
     */
    function setTimeUnit(uint256 _timeUnit) external virtual {
        if (!_canSetStakeConditions()) revert NotAuthorized();

        StakingCondition memory condition = stakingConditions[nextConditionId + 1];
        require(_timeUnit != condition.timeUnit, "Time-unit unchanged.");

        _setStakingCondition(_timeUnit, condition.rewardsPerUnitTime);
        emit UpdatedTimeUnit(condition.timeUnit, _timeUnit);
    }

    /**
     * @notice Allows a user to set the rewards per unit time for staking.
     * @param _rewardsPerUnitTime The rewards distributed per unit time.
     */
    function setRewardsPerUnitTime(uint256 _rewardsPerUnitTime) external virtual {
        if (!_canSetStakeConditions()) revert NotAuthorized();

        StakingCondition memory condition = stakingConditions[nextConditionId + 1];
        require(_rewardsPerUnitTime != condition.rewardsPerUnitTime, "Reward unchanged.");

        _setStakingCondition(condition.timeUnit, _rewardsPerUnitTime);
        emit UpdatedRewardsPerUnitTime(condition.rewardsPerUnitTime, _rewardsPerUnitTime);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice Handles the receipt of an ERC721 token.
     * @dev This function is called whenever an ERC721 token is transferred to this contract.
     * It ensures that the contract correctly implements the ERC721Receiver interface.
     */
    function getStakeInfo(address _staker)
        external
        view
        virtual
        returns (uint256[] memory _tokensStaked, uint256 _rewards)
    {
        _tokensStaked = stakerTokens[_staker];
        _rewards = _availableRewards(_staker);
    }

    /**
     * @notice Returns the time unit used for calculating staking rewards.
     * @return _timeUnit The time unit for rewards calculation.
     */
    function getTimeUnit() public view returns (uint256 _timeUnit) {
        _timeUnit = stakingConditions[nextConditionId + 1].timeUnit;
    }

    /**
     * @notice Returns the rewards per unit time for staking.
     * @return _rewardsPerUnitTime The rewards distributed per unit time.
     */
    function getRewardsPerUnitTime() public view returns (uint256 _rewardsPerUnitTime) {
        _rewardsPerUnitTime = stakingConditions[nextConditionId + 1].rewardsPerUnitTime;
    }

    /**
     * @notice Stakes multiple NFTs for the sender.
     * @dev Transfers the given token IDs from the sender to the contract and updates staking records.
     * @param _tokenIds The array of ERC-721 token IDs to be staked.
     */
    function _stake(uint256[] calldata _tokenIds) internal virtual {
        address staker = _stakeMsgSender();
        uint64 length = uint64(_tokenIds.length);
        require(length != 0, "Staking 0 tokens");

        address _stakingToken = stakingToken;

        if (stakers[staker].amountStaked > 0) {
            _updateUnclaimedRewardsForStaker(staker);
        } else {
            stakers[staker].timeOfLastUpdate = uint128(block.timestamp);
            stakers[staker].conditionIdOflastUpdate = nextConditionId + 1;
        }

        for (uint256 i = 0; i < length; ++i) {
            isStaking = 2;
            IERC721(_stakingToken).safeTransferFrom(staker, address(this), _tokenIds[i]);
            isStaking = 1;

            stakerAddress[_tokenIds[i]] = staker;

            if (!isIndexed[_tokenIds[i]]) {
                isIndexed[_tokenIds[i]] = true;
                stakerTokens[staker].push(_tokenIds[i]);
            }
        }
        stakers[staker].amountStaked += length;

        emit TokensStaked(staker, _tokenIds);
    }

    /**
     * @notice Withdraws multiple NFTs for the sender.
     * @dev Transfers the given token IDs from the contract back to the sender and updates staking records.
     * @param _tokenIds The array of ERC-721 token IDs to be withdrawn.
     */
    function _withdraw(uint256[] calldata _tokenIds) internal virtual {
        address staker = _stakeMsgSender();
        uint256 _amountStaked = stakers[staker].amountStaked;
        uint64 len = uint64(_tokenIds.length);
        require(len != 0, "Withdrawing 0 tokens");
        require(_amountStaked >= len, "Withdrawing more than staked");

        address _stakingToken = stakingToken;

        _updateUnclaimedRewardsForStaker(staker);

        if (_amountStaked == len) {
            delete stakerTokens[staker];
        }
        stakers[staker].amountStaked -= len;

        for (uint256 i = 0; i < len; ++i) {
            require(stakerAddress[_tokenIds[i]] == staker, "Not staker");
            stakerAddress[_tokenIds[i]] = address(0);
            IERC721(_stakingToken).safeTransferFrom(address(this), staker, _tokenIds[i]);
        }

        emit TokensWithdrawn(staker, _tokenIds);
    }

    /**
     * @notice Claims rewards for the sender.
     * @dev Calculates and transfers the rewards to the staker, then resets their unclaimed rewards.
     */
    function _claimRewards() internal virtual {
        address staker = _stakeMsgSender();
        uint256 rewards = stakers[staker].unclaimedRewards + _calculateRewards(msg.sender);
        require(rewards != 0, "No rewards");

        stakers[staker].timeOfLastUpdate = uint128(block.timestamp);
        stakers[staker].unclaimedRewards = 0;
        stakers[staker].conditionIdOflastUpdate = nextConditionId + 1;

        _mintRewards(staker, rewards);
        emit RewardsClaimed(staker, rewards);
    }

    /**
     * @notice Calculates the total available rewards for a given user.
     * @dev If the user has staked tokens, it sums their unclaimed rewards with newly calculated rewards.
     *      Otherwise, it returns only the unclaimed rewards.
     * @param _user The address of the user.
     * @return _rewards The total amount of rewards available for the user.
     */
    function _availableRewards(address _user) internal view virtual returns (uint256 _rewards) {
        if (stakers[_user].amountStaked == 0) {
            _rewards = stakers[_user].unclaimedRewards;
        } else {
            _rewards = stakers[_user].unclaimedRewards + _calculateRewards(_user);
        }
    }

    /**
     * @notice Updates unclaimed rewards for a given staker.
     * @param _staker The address of the staker.
     */
    function _updateUnclaimedRewardsForStaker(address _staker) internal virtual {
        uint256 rewards = _calculateRewards(_staker);
        stakers[_staker].unclaimedRewards += rewards;
        stakers[_staker].timeOfLastUpdate = uint128(block.timestamp);
        stakers[_staker].conditionIdOflastUpdate = nextConditionId + 1;
    }

    /**
     * @notice Sets new staking conditions.
     * @param _timeUnit The time unit for staking rewards.
     * @param _rewardsPerUnitTime The rewards distributed per unit time.
     */
    function _setStakingCondition(uint256 _timeUnit, uint256 _rewardsPerUnitTime) internal virtual {
        require(_timeUnit != 0, "time-unit can't be 0");
        uint256 conditionId = nextConditionId;
        nextConditionId += 1;

        stakingConditions[conditionId] = StakingCondition({
            timeUnit: _timeUnit,
            rewardsPerUnitTime: _rewardsPerUnitTime,
            startTimestamp: block.timestamp,
            endTimestamp: 0
        });

        if (conditionId > 0) {
            stakingConditions[conditionId - 1].endTimestamp = block.timestamp;
        }
    }

    /**
     * @notice Calculates the pending rewards for a staker.
     * @param _staker The address of the staker.
     * @return _rewards The amount of pending rewards.
     */
    function _calculateRewards(address _staker) internal view virtual returns (uint256 _rewards) {
        Staker memory staker = stakers[_staker];

        uint256 _stakerConditionId = staker.conditionIdOflastUpdate;
        uint256 _nextConditionId = nextConditionId;

        for (uint256 i = _stakerConditionId; i < _nextConditionId; i += 1) {
            StakingCondition memory condition = stakingConditions[i];

            uint256 startTime = i != _stakerConditionId ? condition.startTimestamp : staker.timeOfLastUpdate;
            uint256 endTime = condition.endTimestamp != 0 ? condition.endTimestamp : block.timestamp;

            uint256 timeStaked = endTime - startTime;
            uint256 rewardsProduct = timeStaked * staker.amountStaked * condition.rewardsPerUnitTime;
            _rewards += rewardsProduct / condition.timeUnit;
        }
    }

    /**
     * @notice Retrieves the address of the message sender in staking functions.
     * @return The address of the caller.
     */
    function _stakeMsgSender() internal virtual returns (address) {
        return msg.sender;
    }

    function getRewardTokenBalance() external view virtual returns (uint256 _rewardsAvailableInContract);
    function _mintRewards(address _staker, uint256 _rewards) internal virtual;
    function _canSetStakeConditions() internal view virtual returns (bool);
}

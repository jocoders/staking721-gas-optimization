// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import { IStaking721 } from '../interfaces/IStaking721.sol';

abstract contract Staking721 is IStaking721 {
  address public immutable stakingToken;
  uint64 private nextConditionId;
  uint8 internal isStaking = 1;

  address[] public stakersArray;
  uint256[] public indexedTokens;

  mapping(address => uint256[]) public stakerTokens;

  mapping(uint256 => bool) public isIndexed;
  mapping(address => Staker) public stakers;
  mapping(uint256 => address) public stakerAddress;
  mapping(uint256 => StakingCondition) private stakingConditions;

  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;
  uint256 private _status = _NOT_ENTERED;

  error NotAuthorized();

  modifier nonReentrant() {
    require(_status != _ENTERED, 'ReentrancyGuard: reentrant call');

    _status = _ENTERED;
    _;
    _status = _NOT_ENTERED;
  }

  constructor(address _stakingToken) {
    require(_stakingToken != address(0), 'collection address 0');
    stakingToken = _stakingToken;
  }

  function stake(uint256[] calldata _tokenIds) external nonReentrant {
    _stake(_tokenIds);
  }

  function withdraw(uint256[] calldata _tokenIds) external nonReentrant {
    _withdraw(_tokenIds);
  }

  function claimRewards() external nonReentrant {
    _claimRewards();
  }

  function setTimeUnit(uint256 _timeUnit) external virtual {
    if (!_canSetStakeConditions()) revert NotAuthorized();

    StakingCondition memory condition = stakingConditions[nextConditionId - 1];
    require(_timeUnit != condition.timeUnit, 'Time-unit unchanged.');

    _setStakingCondition(_timeUnit, condition.rewardsPerUnitTime);
    emit UpdatedTimeUnit(condition.timeUnit, _timeUnit);
  }

  function setRewardsPerUnitTime(uint256 _rewardsPerUnitTime) external virtual {
    if (!_canSetStakeConditions()) revert NotAuthorized();

    StakingCondition memory condition = stakingConditions[nextConditionId - 1];
    require(_rewardsPerUnitTime != condition.rewardsPerUnitTime, 'Reward unchanged.');

    _setStakingCondition(condition.timeUnit, _rewardsPerUnitTime);
    emit UpdatedRewardsPerUnitTime(condition.rewardsPerUnitTime, _rewardsPerUnitTime);
  }

  function getStakeInfo(
    address _staker
  ) external view virtual returns (uint256[] memory _tokensStaked, uint256 _rewards) {
    uint256[] memory _indexedTokens = indexedTokens;
    bool[] memory _isStakerToken = new bool[](_indexedTokens.length);

    uint256 indexedTokenCount = _indexedTokens.length;
    uint256 stakerTokenCount = 0;

    for (uint256 i = 0; i < indexedTokenCount; i++) {
      _isStakerToken[i] = stakerAddress[_indexedTokens[i]] == _staker;
      if (_isStakerToken[i]) stakerTokenCount += 1;
    }

    _tokensStaked = new uint256[](stakerTokenCount);
    uint256 count = 0;
    for (uint256 i = 0; i < indexedTokenCount; i++) {
      if (_isStakerToken[i]) {
        _tokensStaked[count] = _indexedTokens[i];
        count += 1;
      }
    }

    _rewards = _availableRewards(_staker);
  }

  function getTimeUnit() public view returns (uint256 _timeUnit) {
    _timeUnit = stakingConditions[nextConditionId - 1].timeUnit;
  }

  function getRewardsPerUnitTime() public view returns (uint256 _rewardsPerUnitTime) {
    _rewardsPerUnitTime = stakingConditions[nextConditionId - 1].rewardsPerUnitTime;
  }

  function _stake(uint256[] calldata _tokenIds) internal virtual {
    uint64 len = uint64(_tokenIds.length);
    require(len != 0, 'Staking 0 tokens');

    address _stakingToken = stakingToken;

    if (stakers[msg.sender].amountStaked > 0) {
      _updateUnclaimedRewardsForStaker(msg.sender);
    } else {
      stakersArray.push(msg.sender);
      stakers[msg.sender].timeOfLastUpdate = uint128(block.timestamp);
      stakers[msg.sender].conditionIdOflastUpdate = nextConditionId - 1;
    }
    for (uint256 i = 0; i < len; ++i) {
      isStaking = 2;
      IERC721(_stakingToken).safeTransferFrom(msg.sender, address(this), _tokenIds[i]);
      isStaking = 1;

      stakerAddress[_tokenIds[i]] = msg.sender;

      if (!isIndexed[_tokenIds[i]]) {
        isIndexed[_tokenIds[i]] = true;
        indexedTokens.push(_tokenIds[i]);
      }
    }
    stakers[msg.sender].amountStaked += len;

    emit TokensStaked(msg.sender, _tokenIds);
  }

  function _withdraw(uint256[] calldata _tokenIds) internal virtual {
    uint256 _amountStaked = stakers[msg.sender].amountStaked;
    uint64 len = uint64(_tokenIds.length);
    require(len != 0, 'Withdrawing 0 tokens');
    require(_amountStaked >= len, 'Withdrawing more than staked');

    address _stakingToken = stakingToken;

    _updateUnclaimedRewardsForStaker(msg.sender);

    if (_amountStaked == len) {
      address[] memory _stakersArray = stakersArray;
      for (uint256 i = 0; i < _stakersArray.length; ++i) {
        if (_stakersArray[i] == msg.sender) {
          stakersArray[i] = _stakersArray[_stakersArray.length - 1];
          stakersArray.pop();
          break;
        }
      }
    }
    stakers[msg.sender].amountStaked -= len;

    for (uint256 i = 0; i < len; ++i) {
      require(stakerAddress[_tokenIds[i]] == msg.sender, 'Not staker');
      stakerAddress[_tokenIds[i]] = address(0);
      IERC721(_stakingToken).safeTransferFrom(address(this), msg.sender, _tokenIds[i]);
    }

    emit TokensWithdrawn(msg.sender, _tokenIds);
  }

  function _claimRewards() internal virtual {
    uint256 rewards = stakers[msg.sender].unclaimedRewards + _calculateRewards(msg.sender);

    require(rewards != 0, 'No rewards');

    stakers[msg.sender].timeOfLastUpdate = uint128(block.timestamp);
    stakers[msg.sender].unclaimedRewards = 0;
    stakers[msg.sender].conditionIdOflastUpdate = nextConditionId - 1;

    _mintRewards(msg.sender, rewards);

    emit RewardsClaimed(msg.sender, rewards);
  }

  function _availableRewards(address _user) internal view virtual returns (uint256 _rewards) {
    if (stakers[_user].amountStaked == 0) {
      _rewards = stakers[_user].unclaimedRewards;
    } else {
      _rewards = stakers[_user].unclaimedRewards + _calculateRewards(_user);
    }
  }

  function _updateUnclaimedRewardsForStaker(address _staker) internal virtual {
    uint256 rewards = _calculateRewards(_staker);
    stakers[_staker].unclaimedRewards += rewards;
    stakers[_staker].timeOfLastUpdate = uint128(block.timestamp);
    stakers[_staker].conditionIdOflastUpdate = nextConditionId - 1;
  }

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

  function getRewardTokenBalance() external view virtual returns (uint256 _rewardsAvailableInContract);
  function _mintRewards(address _staker, uint256 _rewards) internal virtual;
  function _canSetStakeConditions() internal view virtual returns (bool);
}

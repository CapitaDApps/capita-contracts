// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

error PersonalFundMe__NotOwner();
error PersonalFundMe__NotFactory();
error PersonalFundMe__FundingPeriodOver();
error PersonalFundMe__AmountTooLow();
error PersonalFundMe__ExceedsMaxLimit();
error PersonalFundMe__FundingStillActive();
error PersonalFundMe__AlreadyWithdrawn();
error PersonalFundMe__NotApproved();
error PersonalFundMe__WithdrawFailed();

contract PersonalFundMe {
    address public owner;
    address public factory;
    uint256 public minFund;
    uint256 public maxFund;
    uint256 public endTime;
    bool public isWithdrawApproved;
    bool public isWithdrawn;

    mapping(address => uint256) public contributions;
    address[] public funders;

    bool public isPaused;

    event Deposited(address indexed funder, uint256 amount);
    event WithdrawApproved();
    event Withdrawn(address indexed owner, uint256 amount);
    event Paused(bool paused);

    modifier onlyOwner() {
        if (msg.sender != owner) revert PersonalFundMe__NotOwner();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert PersonalFundMe__NotFactory();
        _;
    }

    constructor(
        address _owner,
        uint256 _minFund,
        uint256 _maxFund,
        uint256 _duration
    ) {
        owner = _owner;
        factory = msg.sender;
        minFund = _minFund;
        maxFund = _maxFund;
        endTime = block.timestamp + _duration;
    }

    function deposit() external payable {
        if (block.timestamp > endTime)
            revert PersonalFundMe__FundingPeriodOver();
        if (msg.value < minFund) revert PersonalFundMe__AmountTooLow();
        if (maxFund > 0 && contributions[msg.sender] + msg.value > maxFund) {
            revert PersonalFundMe__ExceedsMaxLimit();
        }

        if (contributions[msg.sender] == 0) {
            funders.push(msg.sender);
        }

        contributions[msg.sender] += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    function approveWithdraw() external onlyFactory {
        if (block.timestamp <= endTime)
            revert PersonalFundMe__FundingStillActive();
        if (isWithdrawn) revert PersonalFundMe__AlreadyWithdrawn();

        isWithdrawApproved = true;
        emit WithdrawApproved();
    }

    function updatePause(bool pause) external onlyFactory {
        isPaused = pause;
        emit Paused(pause);
    }

    function withdraw() external onlyOwner {
        if (!isWithdrawApproved) revert PersonalFundMe__NotApproved();
        if (isWithdrawn) revert PersonalFundMe__AlreadyWithdrawn();

        uint256 balance = address(this).balance;
        isWithdrawn = true;
        (bool success, ) = payable(owner).call{value: balance}("");
        if (!success) revert PersonalFundMe__WithdrawFailed();

        emit Withdrawn(owner, balance);
    }

    function getFunders() external view returns (address[] memory) {
        return funders;
    }
}

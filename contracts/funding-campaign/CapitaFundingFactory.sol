// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PersonalFundMe.sol";

error CapitaFundingFactory__NotOwner();
error CapitaFundingFactory__NotModerator();
error CapitaFundingFactory__InsufficientFee();
error CapitaFundingFactory__WithdrawFailed();

contract CapitaFundingFactory {
    address public owner;
    uint256 public fee = 3 ether;
    address[] public deployedCampaigns;
    mapping(address => bool) public moderators;
    mapping(address => address[]) public userCampaigns; // Tracks each user's fundMe contracts

    event PersonalFundMeCreated(address indexed creator, address fundMeAddress);
    event ModeratorAdded(address indexed moderator);
    event ModeratorRemoved(address indexed moderator);

    modifier onlyOwner() {
        if (msg.sender != owner) revert CapitaFundingFactory__NotOwner();
        _;
    }

    modifier onlyModerator() {
        if (!moderators[msg.sender])
            revert CapitaFundingFactory__NotModerator();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addModerator(address _moderator) external onlyOwner {
        moderators[_moderator] = true;
        emit ModeratorAdded(_moderator);
    }

    function removeModerator(address _moderator) external onlyOwner {
        moderators[_moderator] = false;
        emit ModeratorRemoved(_moderator);
    }

    function createPersonalFundMe(
        uint256 _minFund,
        uint256 _maxFund,
        uint256 _duration
    ) external payable {
        if (msg.value < fee) revert CapitaFundingFactory__InsufficientFee();

        PersonalFundMe newFundMe = new PersonalFundMe(
            msg.sender,
            _minFund,
            _maxFund,
            _duration
        );
        deployedCampaigns.push(address(newFundMe));
        userCampaigns[msg.sender].push(address(newFundMe)); // Store campaign for creator

        emit PersonalFundMeCreated(msg.sender, address(newFundMe));
    }

    function approveWithdraw(address _fundMe) external onlyModerator {
        PersonalFundMe(_fundMe).approveWithdraw();
    }

    function pausePersonalFundMeContract(
        address _fundMe,
        bool pause
    ) external onlyModerator {
        PersonalFundMe(_fundMe).updatePause(pause);
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner).call{value: balance}("");
        if (!success) revert CapitaFundingFactory__WithdrawFailed();
    }

    function getDeployedCampaigns() external view returns (address[] memory) {
        return deployedCampaigns;
    }

    function getUserCampaigns(
        address _user
    ) external view returns (address[] memory) {
        return userCampaigns[_user];
    }
}

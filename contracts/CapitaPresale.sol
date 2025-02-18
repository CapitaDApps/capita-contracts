// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error CapitaPresale__LessThanMinBuyAmount();
error CapitaPresale__NotActive();
error CapitaPresale__Ended();
error CapitaPresale__NotStarted();
error CapitaPresale__ExceedsMaxBuy();
error CapitaPresale__PresaleFull();
error CapitaPresale__TokenAmountExceedsBalance();
error CapitaPresale__InsufficientTokensInPresale();

contract CapitaPresale is Ownable {
    receive() external payable {}

    event BoughtIntoPresale(uint256 ethAmount, uint256 tokenAmount);
    event TokenPriceUpdate(uint256 price);
    event PresaleStatusUpdate(bool status);
    event PresaleParamsUpdate(
        bool status,
        uint256 presalePrice,
        uint256 presaleSupply,
        uint256 minBuyAmountInUsd,
        uint8 maxPerWalletPercentage,
        uint256 totalSupply
    );
    event TokensAdded(uint256 amount);
    event UpdateTokenParam(uint8 maxPerWalletPercentage, uint256 totalSupply);
    event PresaleTimeUpdate(uint256 startTime, uint256 endTime);
    event MinBuyAmountUpdate(uint256 minBuyAmount);

    AggregatorV3Interface internal dataFeed;

    uint256 public presalePrice;
    uint256 public minBuyAmount = 20 ether; // 20 USD

    uint256 public totalSupply;
    uint256 public presaleSupply;

    uint8 public maxPerWalletPercentage;

    uint256 public maxperWallet;

    uint256 public startTime;

    uint256 public endTime;

    bool public presaleStatus;

    IERC20 public immutable i_capitaToken;

    uint256 public totalBought;
    address public presaleWallet;

    mapping(address => uint256) public addressToAmountBought;

    constructor(address dataFeedAddress, address capitaTokenAddress) Ownable() {
        dataFeed = AggregatorV3Interface(dataFeedAddress);
        i_capitaToken = IERC20(capitaTokenAddress);
    }

    modifier checkBuyAmount(uint256 amount) {
        if (amount < minBuyAmount) {
            revert CapitaPresale__LessThanMinBuyAmount();
        }
        _;
    }

    modifier presaleState() {
        if (!presaleStatus) {
            revert CapitaPresale__NotActive();
        }

        if (startTime == 0) {
            revert CapitaPresale__NotStarted();
        }

        if (endTime < block.timestamp) {
            revert CapitaPresale__Ended();
        }
        _;
    }

    function buyIntoPresale()
        public
        payable
        checkBuyAmount(getEthToUsd(msg.value))
        presaleState
    {
        uint256 tokens = getTokensForEth(msg.value);

        if (tokens + totalBought > presaleSupply) {
            revert CapitaPresale__PresaleFull();
        }

        if (i_capitaToken.balanceOf(address(this)) < tokens) {
            revert CapitaPresale__InsufficientTokensInPresale();
        }

        if (addressToAmountBought[msg.sender] + tokens > maxperWallet) {
            revert CapitaPresale__ExceedsMaxBuy();
        }

        i_capitaToken.transfer(msg.sender, tokens);

        addressToAmountBought[msg.sender] += tokens;

        totalBought += tokens;

        emit BoughtIntoPresale(msg.value, tokens);
    }

    function addTokens(uint256 _amount) public onlyOwner {
        i_capitaToken.transferFrom(msg.sender, address(this), _amount);
        emit TokensAdded(_amount);
    }

    function updatePresaleParams(
        bool _presaleStatus,
        uint256 _presalePrice,
        uint256 _presaleSupply,
        uint256 _minBuyAmountInUsd,
        uint8 _maxPerWalletPercentage,
        uint256 _totalSupply
    ) public onlyOwner {
        presaleStatus = _presaleStatus;
        presalePrice = _presalePrice;
        presaleSupply = _presaleSupply;
        minBuyAmount = _minBuyAmountInUsd;
        maxPerWalletPercentage = _maxPerWalletPercentage;
        totalSupply = _totalSupply;
        maxperWallet = (_totalSupply * _maxPerWalletPercentage) / 100;
        emit PresaleParamsUpdate(
            _presaleStatus,
            _presalePrice,
            _presaleSupply,
            _minBuyAmountInUsd,
            _maxPerWalletPercentage,
            _totalSupply
        );
    }

    function updateTokenPrice(uint256 _presalePrice) public onlyOwner {
        presalePrice = _presalePrice;

        emit TokenPriceUpdate(_presalePrice);
    }

    function updatePresaleStatus(bool _presaleStatus) public onlyOwner {
        presaleStatus = _presaleStatus;
        emit PresaleStatusUpdate(_presaleStatus);
    }

    function updateMinBuyAmount(uint256 _minBuyAmountInUsd) public onlyOwner {
        minBuyAmount = _minBuyAmountInUsd;
        emit MinBuyAmountUpdate(_minBuyAmountInUsd);
    }

    function updatePresaleTime(
        uint256 startTimeInSecs,
        uint256 endTimeInSecs
    ) public onlyOwner {
        startTime = block.timestamp + startTimeInSecs;
        endTime = block.timestamp + endTimeInSecs;

        emit PresaleTimeUpdate(startTime, endTime);
    }

    function updateTokenParams(
        uint8 _maxPerWalletPercentage,
        uint256 _totalSupply
    ) public onlyOwner {
        maxPerWalletPercentage = _maxPerWalletPercentage;
        totalSupply = _totalSupply;
        maxperWallet = (_totalSupply * _maxPerWalletPercentage) / 100;

        emit UpdateTokenParam(_maxPerWalletPercentage, _totalSupply);
    }

    function getPriceFeedAddress() public view returns (address) {
        return address(dataFeed);
    }

    function getTokensForEth(uint256 ethAmount) public view returns (uint256) {
        uint256 ethInUsd = getEthToUsd(ethAmount);

        uint256 tokens = (ethInUsd / presalePrice) * 10 ** 18;

        return tokens;
    }

    function getEthToUsd(uint256 ethAmount) public view returns (uint256) {
        int ethPriceInUsd = getChainlinkDataFeedLatestAnswer() * 10 ** 10;

        uint256 ethAmountInUsd = (uint256(ethPriceInUsd) * ethAmount) /
            10 ** 18;

        return ethAmountInUsd;
    }

    /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }

    function resuceETH(address to, uint256 amount) public onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function rescueTokens(address to, uint256 amount) public onlyOwner {
        uint256 balance = i_capitaToken.balanceOf(address(this));
        if (amount > balance) {
            revert CapitaPresale__TokenAmountExceedsBalance();
        }
        i_capitaToken.transfer(to, amount);
    }
}

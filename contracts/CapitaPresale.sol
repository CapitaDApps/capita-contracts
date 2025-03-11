// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PriceFeed} from "./lib/PriceFeed.sol";

error CapitaPresale__LessThanMinBuyAmount();
error CapitaPresale__NotActive();
error CapitaPresale__Ended();
error CapitaPresale__NotStarted();
error CapitaPresale__ExceedsMaxBuy();
error CapitaPresale__PresaleFull();
error CapitaPresale__TokenAmountExceedsBalance();
error CapitaPresale__InsufficientTokensInPresale();
error CapitaPresale__BuyerNotFound();
error CapitaPresale__TgeNotUpdated();
error CapitaPresale__ClaimedAllTokens();

contract CapitaPresale is Ownable {
    using PriceFeed for uint256;

    receive() external payable {}

    event BoughtIntoPresale(
        address buyer,
        uint256 ethAmount,
        uint256 tokenAmount
    );
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
    event TokensClaimed(address buyer, uint256 amount);
    event TgeDateUpdated(uint256 timeInSecs);

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
    uint256 public tgeDate;

    mapping(address => Buyer) public addressToBuyer;

    constructor(address dataFeedAddress, address capitaTokenAddress) Ownable() {
        dataFeed = AggregatorV3Interface(dataFeedAddress);
        i_capitaToken = IERC20(capitaTokenAddress);
    }

    struct Buyer {
        uint256 tokensBought;
        uint256 tokensReceived;
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
        presaleState
        checkBuyAmount(uint256(msg.value).ethToUsd(dataFeed))
    {
        uint256 tokens = getTokensForEth(msg.value);

        if (tokens + totalBought > presaleSupply) {
            revert CapitaPresale__PresaleFull();
        }

        if (i_capitaToken.balanceOf(address(this)) < tokens) {
            revert CapitaPresale__InsufficientTokensInPresale();
        }

        if (addressToBuyer[msg.sender].tokensBought + tokens > maxperWallet) {
            revert CapitaPresale__ExceedsMaxBuy();
        }

        uint256 tokensTransferrableNow = (tokens * 40) / 100;

        i_capitaToken.transfer(msg.sender, tokensTransferrableNow);

        addressToBuyer[msg.sender].tokensBought += tokens;
        addressToBuyer[msg.sender].tokensReceived += tokensTransferrableNow;

        totalBought += tokens;

        emit BoughtIntoPresale(msg.sender, msg.value, tokens);
    }

    function claimTokens() public {
        address sender = msg.sender;
        if (!buyerExists(sender)) {
            revert CapitaPresale__BuyerNotFound();
        }
        if (tgeDate == 0) {
            revert CapitaPresale__TgeNotUpdated();
        }
        Buyer memory buyer = addressToBuyer[sender];

        if (buyer.tokensBought == buyer.tokensReceived) {
            revert CapitaPresale__ClaimedAllTokens();
        }

        uint256 firstRelease = tgeDate + 20 days;
        uint256 secondRelease = tgeDate + 40 days;

        uint256 claimableTokens = 0;

        if (
            block.timestamp >= firstRelease && block.timestamp < secondRelease
        ) {
            claimableTokens = (buyer.tokensBought * 40) / 100;
        } else if (block.timestamp >= secondRelease) {
            claimableTokens = buyer.tokensBought - buyer.tokensReceived;
        }

        if (claimableTokens > 0) {
            buyer.tokensReceived += claimableTokens;
            i_capitaToken.transfer(sender, claimableTokens);
            emit TokensClaimed(sender, claimableTokens);
        }
    }

    function addTokens(uint256 _amount) public onlyOwner {
        i_capitaToken.transferFrom(msg.sender, address(this), _amount);
        emit TokensAdded(_amount);
    }

    function updateTgeDate(uint256 _tgeDateInSecs) public onlyOwner {
        tgeDate = _tgeDateInSecs;
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

    function buyerExists(address _buyer) public view returns (bool) {
        Buyer memory buyer = addressToBuyer[_buyer];

        if (buyer.tokensBought > 0) {
            return true;
        }
        return false;
    }

    function getPriceFeedAddress() public view returns (address) {
        return address(dataFeed);
    }

    function getTokensForEth(uint256 ethAmount) public view returns (uint256) {
        uint256 ethInUsd = ethAmount.ethToUsd(dataFeed);

        uint256 tokens = (ethInUsd / presalePrice) * 10 ** 18;

        return tokens;
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

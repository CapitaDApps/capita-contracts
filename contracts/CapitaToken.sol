// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

error CapitaToken__TradingNotEnabled();
error CapitaToken__MaxPerWalletExceeded();
error CapitaToken__UniswapPairCannotBeModified();
error CapitaToken__InvalidWallet();
error CapitaToken__InsufficientTokensForSwap();
error CapitaToken__BuyTaxCannotExceed_30();
error CapitaToken__InvalidDistribution();
error CapitaToken__UnAuthorized();

contract CapitaToken is ERC20, Ownable {
    event TradingStatus(bool status, bool limits);
    event LimitsInEffect(bool inEffect);
    event WalletExcluded(address walletAddress, bool excluded);
    event PairAdded(address pairAddress, bool added);
    event TaxesUpdated(uint256 buyTax);
    event WalletsUpdated(address indexed newDevelopmentWallet);

    bool public tradingEnabled = false;

    uint8 public maxPerWalletPercentage = 3;
    uint256 public maxPerWallet;

    address public marketingWallet;
    address public developmentWallet;

    uint256 public developmentSharePercentage = 70;
    uint256 public liquiditySharePercentage = 30;

    uint256 public buyTax = 4;
    uint256 public swapAmount;
    bool public limitsInEffect;

    address public i_uniswap_pair_address;
    IUniswapV2Router02 public i_UNISWAP_V2_ROUTER02;

    mapping(address => bool) public excludeFromLimits;
    mapping(address => bool) public AMMPairs;

    bool private inSwap;

    modifier lockSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint8 _decimals,
        address _uniswapV2Router
    ) ERC20(_tokenName, _tokenSymbol) Ownable() {
        i_UNISWAP_V2_ROUTER02 = IUniswapV2Router02(_uniswapV2Router);

        IUniswapV2Factory _uniswapV2Factory = IUniswapV2Factory(
            i_UNISWAP_V2_ROUTER02.factory()
        );

        i_uniswap_pair_address = _uniswapV2Factory.createPair(
            i_UNISWAP_V2_ROUTER02.WETH(),
            address(this)
        );

        AMMPairs[i_uniswap_pair_address] = true;

        excludeFromLimits[i_uniswap_pair_address] = true;
        excludeFromLimits[_uniswapV2Router] = true;
        excludeFromLimits[address(this)] = true;
        excludeFromLimits[msg.sender] = true;
        excludeFromLimits[address(0)] = true;
        excludeFromLimits[address(0xdead)] = true;

        _mint(msg.sender, 1000000000 * 10 ** _decimals);
    }

    function updateExcludeFromLimits(
        address _address,
        bool _exempt
    ) public onlyOwner {
        excludeFromLimits[_address] = _exempt;
    }

    function addAMMPair(address ammPair, bool include) public onlyOwner {
        if (ammPair == i_uniswap_pair_address) {
            revert CapitaToken__UniswapPairCannotBeModified();
        }
        AMMPairs[ammPair] = include;
        emit PairAdded(ammPair, include);
    }

    function updateTradingParams(
        bool _status,
        uint8 _maxPerWalletPercent,
        bool _limitsInEffect
    ) public onlyOwner {
        tradingEnabled = _status;
        limitsInEffect = _limitsInEffect;

        if (_maxPerWalletPercent > 0) {
            maxPerWalletPercentage = _maxPerWalletPercent;
            maxPerWallet = (totalSupply() * maxPerWalletPercentage) / 100;
        }

        emit TradingStatus(_status, _limitsInEffect);
    }

    function updateTradingStatus(
        bool _status,
        bool _limitsInEffect
    ) public onlyOwner {
        tradingEnabled = _status;
        limitsInEffect = _limitsInEffect;
        emit TradingStatus(_status, _limitsInEffect);
    }

    function updateWallets(address _newDevelopmentWallet) external onlyOwner {
        if (_newDevelopmentWallet == address(0)) {
            revert CapitaToken__InvalidWallet();
        }

        developmentWallet = _newDevelopmentWallet;
        emit WalletsUpdated(_newDevelopmentWallet);
    }

    function updateSwapAmount(uint256 _swapAmount) external onlyOwner {
        swapAmount = _swapAmount;
    }

    function updateDistribution(
        uint256 _developmentShare,
        uint256 _liquidityShare
    ) external onlyOwner {
        if (_developmentShare + _liquidityShare != 100) {
            revert CapitaToken__InvalidDistribution();
        }

        developmentSharePercentage = _developmentShare;
        liquiditySharePercentage = _liquidityShare;
    }

    function updateTaxes(uint256 _buyTax) external onlyOwner {
        if (_buyTax > 30) revert CapitaToken__BuyTaxCannotExceed_30();
        buyTax = _buyTax;
        emit TaxesUpdated(_buyTax);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        if (sender == address(0)) {
            revert CapitaToken__InvalidWallet();
        }
        if (recipient == address(0)) {
            revert CapitaToken__InvalidWallet();
        }
        bool from_isExcluded = excludeFromLimits[sender];
        bool to_isExcluded = excludeFromLimits[recipient];
        bool from_AMMPairs = AMMPairs[sender];

        if (!tradingEnabled) {
            if (sender == i_uniswap_pair_address || !from_isExcluded) {
                revert CapitaToken__TradingNotEnabled();
            }
        }

        uint256 tax = 0;

        if (!to_isExcluded && from_AMMPairs) {
            // on buy
            tax = (amount * buyTax) / 100;
        }

        if (!to_isExcluded) {
            if (limitsInEffect) {
                if (amount + balanceOf(recipient) > maxPerWallet) {
                    revert CapitaToken__MaxPerWalletExceeded();
                }
            }
        }

        if (tax > 0) {
            amount -= tax;
            super._transfer(sender, address(this), tax);
        }

        super._transfer(sender, recipient, amount);
    }

    function swapAndLiquifyTokens() public {
        if (msg.sender != developmentWallet) {
            revert CapitaToken__UnAuthorized();
        }
        if (balanceOf(address(this)) >= swapAmount && !inSwap) {
            _swapAndDistribute();
        }
    }

    function _swapAndDistribute() private lockSwap {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance < swapAmount) {
            revert CapitaToken__InsufficientTokensForSwap();
        }

        uint256 developmentShare = (contractBalance *
            developmentSharePercentage) / 100;
        uint256 liquidityShare = (contractBalance * liquiditySharePercentage) /
            100;

        _swapTokensForEth(developmentShare);

        uint256 contractEthBalance = address(this).balance;

        uint256 developmentEth = (contractEthBalance *
            developmentSharePercentage) / 100;

        payable(developmentWallet).transfer(developmentEth);

        uint256 halfLiq = liquidityShare / 2;
        uint256 otherHalfLiq = liquidityShare - halfLiq;
        uint256 ethLiq = address(this).balance;

        _swapTokensForEth(halfLiq);
        _addLiquidity(otherHalfLiq, ethLiq);
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        require(tokenAmount > 0, "Swap amount must be greater than zero");

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = i_UNISWAP_V2_ROUTER02.WETH();

        _approve(address(this), address(i_UNISWAP_V2_ROUTER02), tokenAmount);

        i_UNISWAP_V2_ROUTER02
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                address(this),
                block.timestamp
            );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(i_UNISWAP_V2_ROUTER02), tokenAmount);

        i_UNISWAP_V2_ROUTER02.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    receive() external payable {}
}

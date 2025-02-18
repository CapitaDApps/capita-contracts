// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

error CapitaToken__BuyTaxCannotExceed_30();
error CapitaToken__SellTaxCannotExceed_99();
error CapitaToken__TradingNotEnabled();
error CapitaToken__MaxPerWalletExceeded();
error CapitaToken__MaxPerTxExceeded();
error CapitaToken__InvalidWallet();
error CapitaToken__InsufficientTokensForSwap();

contract CapitaToken is ERC20, Ownable, ReentrancyGuard {

    uint256 public maxPerTx;
    uint256 public maxPerWallet;
    uint256 public swapAmount;
    bool public swapEnabled = true;
    bool public tradingEnabled = false;

    address public marketingWallet;
    address public developmentWallet;

    uint256 public buyTax = 3;
    uint256 public sellTax = 3;

    uint256 public marketingSharePercentage = 40;
    uint256 public developmentSharePercentage = 30;
    uint256 public liquiditySharePercentage = 30;

    IUniswapV2Router02 public uniswapRouter;
    address public immutable uniswapPair;

    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isExcludedFromMaxPerWallet;
    mapping(address => bool) public isExcludedFromMaxPerTx;
    mapping(address => bool) public isExcludedFromTax;

    bool private inSwap;
    modifier lockSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    event TradingStatusUpdated(bool enabled);
    event TaxesUpdated(uint256 buyTax, uint256 sellTax);
    event MaxLimitsUpdated(uint256 maxPerTx, uint256 maxPerWallet);
    event SwapAmountUpdated(uint256 newSwapAmount);
    event OwnershipRenounced(address indexed previousOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event WalletsUpdated(address indexed newMarketingWallet, address indexed newDevelopmentWallet);

    constructor(
        address _routerAddress,
        address _marketingWallet,
        address _developmentWallet,
        uint256 _swapAmount
    ) ERC20("CapitaToken", "CPT") {
        require(_routerAddress != address(0), "Invalid Router Address");
        require(_marketingWallet != address(0), "Invalid Marketing Wallet");
        require(_developmentWallet != address(0), "Invalid Development Wallet");

        marketingWallet = _marketingWallet;
        developmentWallet = _developmentWallet;
        swapAmount = _swapAmount;

        uniswapRouter = IUniswapV2Router02(_routerAddress);
        uniswapPair = IUniswapV2Factory(uniswapRouter.factory()).createPair(
            address(this),
            uniswapRouter.WETH()
        );

        _mint(msg.sender, 1e9 * 10 ** decimals());

        maxPerTx = totalSupply() * 3 / 100;
        maxPerWallet = totalSupply() * 3 / 100;

        isWhitelisted[msg.sender] = true;
        isWhitelisted[address(uniswapRouter)] = true;

        isExcludedFromMaxPerWallet[msg.sender] = true;
        isExcludedFromMaxPerWallet[address(uniswapRouter)] = true;
        isExcludedFromMaxPerTx[msg.sender] = true;
        isExcludedFromMaxPerTx[address(uniswapRouter)] = true;

        isExcludedFromTax[msg.sender] = true;
        isExcludedFromTax[address(uniswapRouter)] = true;
    }

    function enableTrading(bool _status) external onlyOwner {
        tradingEnabled = _status;
        emit TradingStatusUpdated(tradingEnabled);
    }

     function updateWallets(address _newMarketingWallet, address _newDevelopmentWallet) external onlyOwner {
        require(_newMarketingWallet != address(0), "Invalid Marketing Wallet");
        require(_newDevelopmentWallet != address(0), "Invalid Development Wallet");
        marketingWallet = _newMarketingWallet;
        developmentWallet = _newDevelopmentWallet;
        emit WalletsUpdated(_newMarketingWallet, _newDevelopmentWallet);
    }

    function updateSwapAmount(uint256 _swapAmount) external onlyOwner {
        swapAmount = _swapAmount;
        emit SwapAmountUpdated(_swapAmount);
    }
    
     function updateDistribution(uint256 _marketingShare, uint256 _developmentShare, uint256 _liquidityShare) external onlyOwner {
        require(
            _marketingShare + _developmentShare + _liquidityShare == 100,
            "Total distribution must be 100%"
        );
        marketingSharePercentage = _marketingShare;
        developmentSharePercentage = _developmentShare;
        liquiditySharePercentage = _liquidityShare;
    }

    function updateTaxes(uint256 _buyTax, uint256 _sellTax) external onlyOwner {
        if (_buyTax > 30) revert CapitaToken__BuyTaxCannotExceed_30();
        if (_sellTax > 99) revert CapitaToken__SellTaxCannotExceed_99();
        buyTax = _buyTax;
        sellTax = _sellTax;
        emit TaxesUpdated(_buyTax, _sellTax);
    }

    function updateWhitelist(address _account, bool _status) external onlyOwner {
        isWhitelisted[_account] = _status;
    }

     function excludeFromTax(address _account, bool _status) external onlyOwner {
        isExcludedFromTax[_account] = _status;

        }

    function _transfer(address from, address to, uint256 amount) internal override {
        if (!tradingEnabled && !isWhitelisted[from] && !isWhitelisted[to]) {
            revert CapitaToken__TradingNotEnabled();
        }

        if (!isExcludedFromMaxPerTx[from] && !isExcludedFromMaxPerTx[to]) {
            require(amount <= maxPerTx, "Transfer exceeds max per transaction limit");
        }

        if (!isExcludedFromMaxPerWallet[to]) {
            require(balanceOf(to) + amount <= maxPerWallet, "Transfer exceeds max wallet limit");
        }
        
     function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(owner(), newOwner);
        _transferOwnership(newOwner);
    }

    function renounceOwnership() public override onlyOwner {
        emit OwnershipRenounced(owner());
        _transferOwnership(address(0));
    }

    function recoverTokens(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(owner(), amount);
    }

       
        uint256 taxAmount = 0;
        if (!isExcludedFromTax[from] && !isExcludedFromTax[to]) {
            if (from == uniswapPair) {
                taxAmount = amount * buyTax / 100;
            } else if (to == uniswapPair) {
                taxAmount = amount * sellTax / 100;
            }

            if (taxAmount > 0) {
                super._transfer(from, address(this), taxAmount);
                amount -= taxAmount;
            }
        }

        super._transfer(from, to, amount);

        if (balanceOf(address(this)) >= swapAmount && !inSwap && from != uniswapPair && swapEnabled) {
            _swapAndDistribute();
        }
    }

    function _swapAndDistribute() private lockSwap nonReentrant {
        uint256 contractBalance = balanceOf(address(this));
        require(contractBalance >= swapAmount, "Insufficient tokens for swap");

        uint256 marketingShare = contractBalance * marketingSharePercentage / 100;
        uint256 developmentShare = contractBalance * developmentSharePercentage / 100;
        uint256 liquidityShare = contractBalance * liquiditySharePercentage / 100;

        _swapTokensForEth(marketingShare + developmentShare);

        uint256 contractEthBalance = address(this).balance;
        uint256 marketingEth = contractEthBalance * marketingSharePercentage / 100;
        uint256 developmentEth = contractEthBalance * developmentSharePercentage / 100;

        payable(marketingWallet).transfer(marketingEth);
        payable(developmentWallet).transfer(developmentEth);

        uint256 halfLiq = liquidityShare / 2;
        uint256 otherHalfLiq = liquidityShare - halfLiq;
        uint256 ethLiq = address(this).balance;

        _swapTokensForEth(halfLiq);
        _addLiquidity(otherHalfLiq, ethLiq);
    } 

    function _swapTokensForEth(uint256 tokenAmount) private {
        address;
        path[0] = address(this);
        path[1] = uniswapRouter.WETH();

        _approve(address(this), address(uniswapRouter), tokenAmount);

        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapRouter), tokenAmount);

        uniswapRouter.addLiquidityETH{value: ethAmount}(
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
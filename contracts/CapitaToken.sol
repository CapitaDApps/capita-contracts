// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

error CapitaToken__BuyTaxCannotExceed_30();
error CapitaToken__SellTaxCannotExceed_99();
error CapitaToken__TradingNotEnabled();
error CapitaToken__MaxPerWalletExceeded();
error CapitaToken__UniswapPairCannotBeModified();
error CapitaToken__MaxPerTxExceeded();
error CapitaToken__InvalidWallet();
error CapitaToken__InsufficientTokensForSwap();

contract CapitaToken is ERC20, Ownable {
    fallback() external payable {}

    receive() external payable {}

    event TradingStatus(bool status, bool limits);
    event TaxChange(uint8 buyTax, uint8 sellTax);
    event WalletsChange(
        address marketingWallet,
        address developmentWallet,
        address liquidityWallet
    );
    event LimitsInEffect(bool inEffect);
    event WalletExcluded(address walletAddress, bool excluded);
    event PairAdded(address pairAddress, bool added);

    bool public tradingEnabled = false;

    uint8 public maxPerWalletPercentage = 3;
    uint256 public maxPerWallet;

    uint256 public maxPerTxPercentage = 10;
    uint256 public maxPerTx;

    uint256 public swapAmountPercentage = 10;
    uint256 public swapAmount;

    uint8 public buyTax = 3;
    uint8 public sellTax = 3; // starting taxes

    address public marketingWallet;
    address public developmentWallet;
    address public liquidityWallet;

    uint256 public marketingWalletPercent = 30;
    uint256 public developmentWalletPercent = 50;
    uint256 public liquidityWalletPercent = 20;

    bool public limitsInEffect;

    bool private swapping;

    IUniswapV2Router02 public i_UNISWAP_V2_ROUTER02;

    address public immutable i_uniswap_pair_address;

    mapping(address => bool) public excludedFromFees;
    mapping(address => bool) public excludeFromMaxTx;
    mapping(address => bool) public AMMPairs;

    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint8 _decimals,
        address _uniswapV2Router
    ) ERC20(_tokenName, _tokenSymbol) Ownable() {
        excludedFromFees[msg.sender] = true;
        excludedFromFees[address(this)] = true;
        // excludedFromLimits[_uniswapV2Router] = true;
        excludedFromFees[address(0)] = true;
        excludedFromFees[address(0xdead)] = true;

        i_UNISWAP_V2_ROUTER02 = IUniswapV2Router02(_uniswapV2Router);

        IUniswapV2Factory _uniswapV2Factory = IUniswapV2Factory(
            i_UNISWAP_V2_ROUTER02.factory()
        );

        i_uniswap_pair_address = _uniswapV2Factory.createPair(
            i_UNISWAP_V2_ROUTER02.WETH(),
            address(this)
        );

        AMMPairs[i_uniswap_pair_address] = true;

        excludeFromMaxTx[_uniswapV2Router] = true;
        excludeFromMaxTx[address(this)] = true;
        excludeFromMaxTx[msg.sender] = true;
        excludeFromMaxTx[address(0)] = true;
        excludeFromMaxTx[address(0xdead)] = true;

        _mint(msg.sender, 1000000000 * 10 ** _decimals);
    }

    function updateExcludedFromFees(
        address _address,
        bool _exempt
    ) public onlyOwner {
        excludedFromFees[_address] = _exempt;
        emit WalletExcluded(_address, _exempt);
    }

    function updateExcludeFromMaxTx(
        address _address,
        bool _exempt
    ) public onlyOwner {
        excludeFromMaxTx[_address] = _exempt;
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
        uint256 _maxPerTxPercentage,
        uint256 _swapAmountPercentage,
        bool _limitsInEffect
    ) public onlyOwner {
        tradingEnabled = _status;
        limitsInEffect = _limitsInEffect;

        if (_maxPerWalletPercent > 0) {
            maxPerWalletPercentage = _maxPerWalletPercent;
            maxPerWallet = (totalSupply() * maxPerWalletPercentage) / 100;
        }

        // percentage 0.1% is equivalent to 1%
        // therefore 0.1/100 == 1/1000

        if (_maxPerTxPercentage > 0) {
            maxPerTxPercentage = _maxPerTxPercentage;
            maxPerTx = (totalSupply() * maxPerTxPercentage) / 1000;
        }
        if (_swapAmountPercentage > 0) {
            swapAmountPercentage = _swapAmountPercentage;
            swapAmount = (totalSupply() * _swapAmountPercentage) / 1000;
        }

        emit TradingStatus(_status, _limitsInEffect);
    }

    function updateWallets(
        address _marketingWallet,
        address _developmentWallet,
        address _liquidityWallet
    ) public onlyOwner {
        if (_marketingWallet == address(0)) {
            revert CapitaToken__InvalidWallet();
        }
        if (_developmentWallet == address(0)) {
            revert CapitaToken__InvalidWallet();
        }
        if (_liquidityWallet == address(0)) {
            revert CapitaToken__InvalidWallet();
        }

        marketingWallet = _marketingWallet;
        developmentWallet = _developmentWallet;
        liquidityWallet = _liquidityWallet;

        emit WalletsChange(
            _marketingWallet,
            _developmentWallet,
            _liquidityWallet
        );
    }

    function updateTaxes(uint8 _buyTax, uint8 _sellTax) public onlyOwner {
        if (_buyTax > 30) {
            revert CapitaToken__BuyTaxCannotExceed_30();
        }
        if (_sellTax > 99) {
            revert CapitaToken__SellTaxCannotExceed_99();
        }
        buyTax = _buyTax;
        sellTax = _sellTax;

        emit TaxChange(_buyTax, _sellTax);
    }

    function updateTradingStatus(
        bool _status,
        bool _limitsInEffect
    ) public onlyOwner {
        tradingEnabled = _status;
        limitsInEffect = _limitsInEffect;
        emit TradingStatus(_status, _limitsInEffect);
    }

    // tax 3% on buy and 3% on sell
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
        bool from_isExcluded = excludedFromFees[sender];
        bool to_isExcluded = excludedFromFees[recipient];
        bool to_AMMPairs = AMMPairs[recipient];
        bool from_AMMPairs = AMMPairs[sender];

        if (!tradingEnabled) {
            if (!from_isExcluded && !to_isExcluded) {
                revert CapitaToken__TradingNotEnabled();
            }
        }

        uint256 contractTokenBal = balanceOf(address(this));
        bool canTransfer = contractTokenBal >= swapAmount;

        if (
            to_AMMPairs &&
            !to_isExcluded &&
            !from_isExcluded &&
            canTransfer &&
            !swapping
        ) {
            transferTokens(contractTokenBal);
        }

        uint256 tax = 0;
        if (!to_isExcluded && from_AMMPairs) {
            // on buy
            // take tax and check max per wallet
            if (limitsInEffect) {
                if (!excludeFromMaxTx[recipient]) {
                    if (amount > maxPerTx) {
                        revert CapitaToken__MaxPerTxExceeded();
                    }

                    if (amount + balanceOf(recipient) > maxPerWallet) {
                        revert CapitaToken__MaxPerWalletExceeded();
                    }
                }
            }
            // tax
            tax = (amount * buyTax) / 100;
        } else if (!from_isExcluded && to_AMMPairs) {
            // on sell
            if (!excludeFromMaxTx[sender]) {
                if (amount > maxPerTx) {
                    revert CapitaToken__MaxPerTxExceeded();
                }
            }
            // tax
            tax = (amount * sellTax) / 100;
        } else if (!to_isExcluded) {
            if (limitsInEffect) {
                if (amount + balanceOf(recipient) > maxPerWallet) {
                    revert CapitaToken__MaxPerWalletExceeded();
                }
            }
        }

        if (from_AMMPairs) {
            amount -= tax;
            if (tax > 0) {
                super._transfer(sender, address(this), tax);
            }
        } else if (to_AMMPairs) {
            uint256 totalSwapAmount = amount + tax;
            if (balanceOf(sender) < totalSwapAmount) {
                revert CapitaToken__InsufficientTokensForSwap();
            }
            if (tax > 0) {
                super._transfer(sender, address(this), tax);
            }
        }

        super._transfer(sender, recipient, amount);
    }

    function transferTokens(uint256 tokens) private {
        if (swapping) return;
        swapping = true;
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(tokens);

        uint256 ethBalance = address(this).balance - (initialETHBalance);

        uint256 ethToMarketing = (ethBalance * marketingWalletPercent) / 100;
        uint256 ethToDev = (ethBalance * developmentWalletPercent) / 100;
        uint256 ethToLq = (ethBalance * liquidityWalletPercent) / 100;

        (bool success, ) = marketingWallet.call{value: ethToMarketing}("");
        require(success, "Marketing transfer failed");

        (bool success_dev, ) = developmentWallet.call{value: ethToDev}("");
        require(success_dev, "Dev transfer failed");

        (bool success_liq, ) = liquidityWallet.call{value: ethToLq}("");
        require(success_liq, "Liquidity transfer failed");

        swapping = false;
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = i_UNISWAP_V2_ROUTER02.WETH();

        _approve(address(this), address(i_UNISWAP_V2_ROUTER02), tokenAmount);

        // make the swap
        i_UNISWAP_V2_ROUTER02
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmount,
                0, // accept any amount of ETH
                path,
                address(this),
                block.timestamp
            );
    }

    function rescueETH(address to, uint256 amount) public onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }
}

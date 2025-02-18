import { artifacts, ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";

const uniswapV2RouterAddr = "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24"; // Base
const uniswapV2FactoryAddr = "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6"; // Base

function txDeadline() {
  return Math.ceil(Date.now() / 1000 + 300); // 5mins
}

async function uniswap(tokenAddress: string) {
  const v2RouterArtifact = await artifacts.readArtifact("UniswapV2Router02");

  const UniswapV2Router = await ethers.getContractAtFromArtifact(
    v2RouterArtifact,
    uniswapV2RouterAddr
  );

  const WETH_addr = await UniswapV2Router.WETH();

  const v2FactoryArtifact = await artifacts.readArtifact("UniswapV2Factory");
  const UniswapV2Facotry = await ethers.getContractAtFromArtifact(
    v2FactoryArtifact,
    uniswapV2FactoryAddr
  );

  const pair = await UniswapV2Facotry.getPair(WETH_addr, tokenAddress);

  return { UniswapV2Facotry, UniswapV2Router, pair, WETH_addr };
}

async function addLq(
  token: any,
  ethAmount: string,
  tokenAmount: string,
  account: any
) {
  // function addLiquidityETH(
  //   address token,
  //   uint amountTokenDesired,
  //   uint amountTokenMin,
  //   uint amountETHMin,
  //   address to,
  //   uint deadline
  // ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

  const tokenAddress = token.target.toString();

  const { UniswapV2Router } = await uniswap(tokenAddress);

  const parseTokenAmount = ethers.parseEther(tokenAmount);

  await token.connect(account).approve(uniswapV2RouterAddr, parseTokenAmount);

  return await UniswapV2Router.connect(account).addLiquidityETH(
    tokenAddress,
    parseTokenAmount,
    0,
    0,
    account.address,
    txDeadline(),
    { value: ethers.parseEther(ethAmount) }
  );
}

async function buyTokens(
  tokenAddress: string,
  ethAmount: string,
  account: any
) {
  // function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
  // external
  // payable
  // returns (uint[] memory amounts);
  const { UniswapV2Router, WETH_addr } = await uniswap(tokenAddress);
  const pair = [WETH_addr, tokenAddress];
  return await UniswapV2Router.connect(account).swapExactETHForTokens(
    0,
    pair,
    account.address,
    txDeadline(),
    { value: ethers.parseEther(ethAmount) }
  );
}

async function sellTokens(token: any, tokenAmount: bigint, account: any) {
  // function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
  // external
  // returns (uint[] memory amounts);
  const tokenAddress = token.target.toString();

  const { UniswapV2Router, WETH_addr } = await uniswap(tokenAddress);
  const pair = [tokenAddress, WETH_addr];

  await token.connect(account).approve(uniswapV2RouterAddr, tokenAmount);

  const [_, out] = await amountsOut(tokenAddress, tokenAmount, [
    tokenAddress,
    WETH_addr,
  ]);

  const amountOutMin = BigInt((Number(out) * 95) / 100);

  console.log(ethers.formatEther(out), ethers.formatEther(amountOutMin));

  return await UniswapV2Router.connect(account).swapExactTokensForETH(
    tokenAmount,
    amountOutMin,
    pair,
    account.address,
    txDeadline()
  );
}

async function amountsOut(
  tokenAddress: string,
  amountIn: bigint,
  pair: string[]
) {
  // function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts);
  const { UniswapV2Router } = await uniswap(tokenAddress);

  const amounts = await UniswapV2Router.getAmountsOut(amountIn, pair);

  return amounts;
}

describe("CapitaToken", function () {
  async function deployTokenFixture() {
    const [owner, acct_2, taxWallet, acct_4, acct_5, acct_6, acct_7] =
      await ethers.getSigners();

    const CapitaToken = await ethers.getContractFactory("CapitaToken");
    const capitaToken = await CapitaToken.deploy(
      "CapitaToken",
      "CPT",
      18,
      uniswapV2RouterAddr
    );

    return {
      owner,
      acct_2,
      taxWallet,
      acct_4,
      acct_5,
      acct_6,
      acct_7,
      capitaToken,
    };
  }

  describe("Deployment", function () {
    it("should mint correct amount of tokens", async function () {
      const { capitaToken } = await loadFixture(deployTokenFixture);

      const totalSupply = await capitaToken.totalSupply();

      expect(totalSupply).to.eq(ethers.parseEther("1000000000"));
    });

    it("should set correct owner address", async function () {
      const { capitaToken, owner } = await loadFixture(deployTokenFixture);
      expect(await capitaToken.owner()).to.eq(owner.address);
    });

    it("should create corresponding pair on deployment", async function () {
      const { capitaToken } = await loadFixture(deployTokenFixture);

      const pairAddress = await capitaToken.i_uniswap_pair_address();

      const { pair } = await uniswap(capitaToken.target.toString());

      expect(pairAddress).to.eq(pair);
    });
  });

  describe("Buy", function () {
    it("should disallow purchase until trading enabled", async () => {
      const { capitaToken, owner, acct_2 } = await loadFixture(
        deployTokenFixture
      );

      await addLq(capitaToken, "15", "100000000", owner);

      const tx = buyTokens(capitaToken.target.toString(), "0.1", acct_2);

      await expect(tx).to.be.reverted;
    });

    it("should allow purchase after trading enabled", async () => {
      const { capitaToken, owner, acct_2 } = await loadFixture(
        deployTokenFixture
      );

      await addLq(capitaToken, "25", "200000000", owner);

      // enable trading
      await capitaToken.updateTradingParams(true, 3, 5, 1, true);

      const tokenAddress = capitaToken.target.toString();

      const { WETH_addr } = await uniswap(tokenAddress);

      const buyAmount = "0.1";

      const result = await amountsOut(
        tokenAddress,
        ethers.parseEther(buyAmount),
        [WETH_addr, tokenAddress]
      );

      console.log({
        in: ethers.formatEther(result[0]),
        out: ethers.formatEther(result[1]),
      });

      const tx = buyTokens(tokenAddress, buyAmount, acct_2);

      await expect(tx).to.not.be.reverted;
    });

    it("should not allow purchase above the max tx limit", async function () {
      const { capitaToken, owner, acct_2 } = await loadFixture(
        deployTokenFixture
      );
      const tokenAddress = capitaToken.target.toString();

      const { WETH_addr } = await uniswap(tokenAddress);

      await addLq(capitaToken, "25", "200000000", owner);

      // enable trading
      await capitaToken.updateTradingParams(true, 3, 5, 1, true);

      const buyAmount = "10";

      const result = await amountsOut(
        tokenAddress,
        ethers.parseEther(buyAmount),
        [WETH_addr, tokenAddress]
      );

      console.log({
        in: ethers.formatEther(result[0]),
        out: ethers.formatEther(result[1]),
      });

      const tx = buyTokens(tokenAddress, buyAmount, acct_2);

      await expect(tx).to.be.reverted;
    });
  });

  describe("Sell", function () {
    it("should sell bought tokens", async function () {
      const { capitaToken, owner, acct_2 } = await loadFixture(
        deployTokenFixture
      );

      await addLq(capitaToken, "25", "200000000", owner);

      // enable trading
      await capitaToken.updateTradingParams(true, 3, 10, 1, true);

      await buyTokens(capitaToken.target.toString(), "1", acct_2);

      const bal = await capitaToken.balanceOf(acct_2.address);

      const allowedAmount = BigInt((Number(bal) * 97) / 100);

      const tokenBalBeforeSell = await capitaToken.balanceOf(acct_2.address);

      const tx = await sellTokens(capitaToken, allowedAmount, acct_2);

      const tokenBalAfterSell = await capitaToken.balanceOf(acct_2.address);

      await expect(tokenBalBeforeSell).to.be.greaterThan(tokenBalAfterSell);
    });

    it("should remove tax automatically on sells", async () => {
      const {
        capitaToken,
        owner,
        acct_2,
        taxWallet,
        acct_4,
        acct_5,
        acct_6,
        acct_7,
      } = await loadFixture(deployTokenFixture);

      await addLq(capitaToken, "25", "200000000", owner);

      // enable trading
      await capitaToken.updateTradingParams(true, 5, 10, 1, true);

      // update tax wallet
      await capitaToken.updateWallets(
        taxWallet.address,
        acct_4.address,
        acct_5.address
      );

      // Buy tokens
      const tokenAddress = capitaToken.target.toString();

      await buyTokens(tokenAddress, "1", acct_2);

      await buyTokens(tokenAddress, "1", acct_6);

      await buyTokens(tokenAddress, "1", acct_7);
      await buyTokens(tokenAddress, "1", acct_7);

      const bal_2 = await capitaToken.balanceOf(acct_2.address);
      const bal_6 = await capitaToken.balanceOf(acct_6.address);
      const bal_7 = await capitaToken.balanceOf(acct_7.address);

      const allowedAmount_2 = BigInt((Number(bal_2) * 97) / 100);
      const allowedAmount_6 = BigInt((Number(bal_6) * 97) / 100);
      const allowedAmount_7 = BigInt((Number(bal_7) * 97) / 100);

      const capitaContractBalBeforeSell = ethers.formatEther(
        await capitaToken.balanceOf(tokenAddress)
      );

      await sellTokens(capitaToken, allowedAmount_2, acct_2);
      await sellTokens(capitaToken, allowedAmount_6, acct_6);

      // await sellTokens(capitaToken, allowedAmount_7, acct_7);

      const capitaContractBalAfterSell = ethers.formatEther(
        await capitaToken.balanceOf(tokenAddress)
      );

      console.log({ capitaContractBalBeforeSell, capitaContractBalAfterSell });
    });
  });
});

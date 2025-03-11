import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

const uniswapV2RouterAddr = "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24";
const ethPriceFeed = "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70";

describe("CapitaPresale", function () {
  async function deploymentFixture() {
    const [owner, acct_2] = await ethers.getSigners();

    const CapitaToken = await ethers.getContractFactory("CapitaToken");
    const capitalToken = await CapitaToken.deploy(
      "CapitaToken",
      "CPT",
      18,
      uniswapV2RouterAddr
    );

    // deploy pricefeed lib contract

    const PriceFeed = await ethers.getContractFactory("PriceFeed");
    const priceFeed = await PriceFeed.deploy();

    const CapitaPresale = await ethers.getContractFactory("CapitaPresale", {
      libraries: {
        PriceFeed: priceFeed.target.toString(),
      },
    });
    const capitaPresale = await CapitaPresale.deploy(
      ethPriceFeed,
      capitalToken.target.toString()
    );

    await capitalToken.updateTradingParams(true, 3, true);
    return { capitaPresale, capitalToken, owner, acct_2 };
  }
  describe("Deployment", function () {
    it("should deploy with correct price feed", async () => {
      const { capitaPresale, owner } = await loadFixture(deploymentFixture);

      expect(await capitaPresale.getPriceFeedAddress()).to.eq(ethPriceFeed);
      expect(await capitaPresale.owner()).to.eq(owner.address);
    });
  });

  describe("buyIntoPresale", function () {
    it("should not buy if presale is not active", async () => {
      const { capitaPresale, acct_2 } = await loadFixture(deploymentFixture);

      const buyIntoPresaleTx = capitaPresale.connect(acct_2).buyIntoPresale();

      await expect(buyIntoPresaleTx).to.revertedWithCustomError(
        capitaPresale,
        "CapitaPresale__NotActive"
      );
    });

    it("should not buy if start time is not set", async () => {
      const { capitaPresale, acct_2 } = await loadFixture(deploymentFixture);

      await capitaPresale.updatePresaleStatus(true);

      const buyIntoPresaleTx = capitaPresale.connect(acct_2).buyIntoPresale();

      await expect(buyIntoPresaleTx).to.revertedWithCustomError(
        capitaPresale,
        "CapitaPresale__NotStarted"
      );
    });

    it("should not buy if amount is less than min buy amount", async () => {
      const { capitaPresale, acct_2 } = await loadFixture(deploymentFixture);

      await capitaPresale.updatePresaleStatus(true);
      const startTime = Math.floor(Date.now() / 1000);
      const endTime = BigInt(startTime + 86400);
      await capitaPresale.updatePresaleTime(BigInt(startTime), endTime);
      await capitaPresale.updateTokenPrice(ethers.parseEther("0.0025"));
      const buyIntoPresaleTx = capitaPresale
        .connect(acct_2)
        .buyIntoPresale({ value: ethers.parseEther("0.005") });

      await expect(buyIntoPresaleTx).to.revertedWithCustomError(
        capitaPresale,
        "CapitaPresale__LessThanMinBuyAmount"
      );
    });

    it("should not buy if not tokens in presale contract", async () => {
      const { capitaPresale, acct_2 } = await loadFixture(deploymentFixture);
      const startTime = Math.floor(Date.now() / 1000);
      const endTime = BigInt(startTime + 86400);
      await capitaPresale.updatePresaleTime(BigInt(startTime), endTime);
      await capitaPresale.updatePresaleParams(
        true,
        ethers.parseEther("0.0025"), // price
        ethers.parseEther("200000000"), // presale supply
        ethers.parseEther("20"), // min buy amount in USD
        3, // max per wallet percentage
        ethers.parseEther("1000000000") // token total supply
      );
      const buyIntoPresaleTx = capitaPresale
        .connect(acct_2)
        .buyIntoPresale({ value: ethers.parseEther("0.01") });

      await expect(buyIntoPresaleTx).to.revertedWithCustomError(
        capitaPresale,
        "CapitaPresale__InsufficientTokensInPresale"
      );
    });

    it("should buy into presale and release only 40% of bought tokens", async () => {
      const { capitaPresale, capitalToken, acct_2 } = await loadFixture(
        deploymentFixture
      );
      const startTime = Math.floor(Date.now() / 1000);
      const endTime = BigInt(startTime + 86400);
      await capitaPresale.updatePresaleTime(BigInt(startTime), endTime);

      const presaleSupply = ethers.parseEther("200000000");
      await capitaPresale.updatePresaleParams(
        true,
        ethers.parseEther("0.0025"), // price
        presaleSupply,
        ethers.parseEther("20"), // min buy amount in USD
        3, // max per wallet percentage
        ethers.parseEther("1000000000") // token total supply
      );

      await capitalToken.updateExcludeFromLimits(
        capitaPresale.target.toString(),
        true
      );
      await capitalToken.updateExcludeFromLimits(
        capitaPresale.target.toString(),
        true
      );

      console.log(
        await capitalToken.excludeFromLimits(capitaPresale.target.toString())
      );

      await capitalToken.transfer(
        capitaPresale.target.toString(),
        presaleSupply
      );

      const buyAmount = "0.05";

      const tokensBought =
        (Number(
          await capitaPresale.getTokensForEth(ethers.parseEther(buyAmount))
        ) *
          40) /
        100;

      await capitaPresale
        .connect(acct_2)
        .buyIntoPresale({ value: ethers.parseEther(buyAmount) });

      expect(BigInt(tokensBought)).to.eq(
        await capitalToken.balanceOf(acct_2.address)
      );
    });
  });
});

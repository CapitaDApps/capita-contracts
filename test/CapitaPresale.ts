import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

const ethPriceFeed = "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70";

describe("CapitaPresale", function () {
  async function deploymentFixture() {
    const [owner, acct_2] = await ethers.getSigners();

    const CapitaPresale = await ethers.getContractFactory("CapitaPresale");
    const capitaPresale = await CapitaPresale.deploy(
      ethPriceFeed,
      acct_2.address
    );

    return { capitaPresale, owner, acct_2 };
  }
  describe("Deployment", function () {
    it("Should deploy with correct price feed", async () => {
      const { capitaPresale } = await loadFixture(deploymentFixture);
      await capitaPresale.updateTokenPrice(ethers.parseEther("0.0025"));
      console.log(
        ethers.formatEther(
          await capitaPresale.getTokensForEth(ethers.parseEther("0.1"))
        ),

        ethers.formatEther(
          await capitaPresale.getEthToUsd(ethers.parseEther("0.1"))
        )
      );
      expect(await capitaPresale.getPriceFeedAddress()).to.eq(ethPriceFeed);
    });
  });
});

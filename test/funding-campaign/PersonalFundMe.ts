import { expect } from "chai";
import { ethers } from "hardhat";
import {
  CapitaFundingFactory,
  PersonalFundMe,
  MockV3Aggregator,
} from "../../typechain-types";

describe("CapitaFundingFactory & PersonalFundMe", function () {
  let factory: CapitaFundingFactory;
  let mockAggregator: MockV3Aggregator;
  let deployer: any, user: any, moderator: any;
  const feeInUsd = ethers.parseEther("3"); // Fee required in USD (18 decimals for compatibility)
  const minFund = ethers.parseEther("0.01"); // Minimum fund requirement
  const maxFund = ethers.parseEther("1"); // Maximum fund limit
  const duration = 60 * 60 * 24; // 1-day campaign duration

  // Mock Chainlink Price Feed Parameters
  const DECIMALS = 8;
  const INITIAL_ANSWER = ethers.parseUnits("2000", DECIMALS); // Simulating ETH price as $2000

  beforeEach(async function () {
    // Get test accounts
    [deployer, user, moderator] = await ethers.getSigners();

    // Deploy a mock Chainlink Price Feed
    const MockV3AggregatorFactory = await ethers.getContractFactory(
      "MockV3Aggregator"
    );
    mockAggregator = await MockV3AggregatorFactory.deploy(
      DECIMALS,
      INITIAL_ANSWER
    );
    await mockAggregator.waitForDeployment();

    // deploy library and connect to factory
    const PriceFeedLibrary = await ethers.getContractFactory("PriceFeed");
    const priceFeedLibrary = await PriceFeedLibrary.deploy();
    priceFeedLibrary.waitForDeployment();

    // Deploy the factory contract with the mock price feed address
    const CapitaFundingFactoryFactory = await ethers.getContractFactory(
      "CapitaFundingFactory",
      {
        libraries: {
          PriceFeed: await priceFeedLibrary.getAddress(),
        },
      }
    );
    factory = await CapitaFundingFactoryFactory.deploy(
      await mockAggregator.getAddress()
    );
    await factory.waitForDeployment();

    // Add a moderator for testing
    await factory.addModerator(moderator.address);
  });

  describe("createPersonalFundMe", function () {
    it("should revert if msg.value (converted to USD) is less than the required fee", async function () {
      const insufficientFee = ethers.parseEther("0.001"); // Less than required fee

      await expect(
        factory.connect(user).createPersonalFundMe(minFund, maxFund, duration, {
          value: insufficientFee,
        })
      ).to.be.revertedWithCustomError(
        factory,
        "CapitaFundingFactory__InsufficientFee"
      );
    });

    it("should create a PersonalFundMe contract when fee is met and track it", async function () {
      const feeProvided = ethers.parseEther("0.002");

      // Creating a new PersonalFundMe contract
      const tx = await factory
        .connect(user)
        .createPersonalFundMe(minFund, maxFund, duration, {
          value: feeProvided,
        });
      const receipt = await tx.wait();

      // Extracting event logs to find the contract address
      const event = receipt?.logs.find(
        (log) => log.fragment.name === "PersonalFundMeCreated"
      );
      expect(event).to.not.be.undefined;
      const personalFundMeAddress = event?.args[1];
      expect(personalFundMeAddress).to.be.properAddress;

      // Ensure it's added to the deployed campaigns list
      const deployedCampaigns = await factory.getDeployedCampaigns();
      expect(deployedCampaigns).to.include(personalFundMeAddress);

      // Ensure the campaign is tracked for the user
      const userCampaigns = await factory.getUserCampaigns(user.address);
      expect(userCampaigns).to.include(personalFundMeAddress);
    });
  });

  describe("PersonalFundMe functionality", function () {
    let fundMe: PersonalFundMe;

    beforeEach(async function () {
      const feeProvided = ethers.parseEther("0.002");

      // Create a new PersonalFundMe contract
      const tx = await factory
        .connect(user)
        .createPersonalFundMe(minFund, maxFund, duration, {
          value: feeProvided,
        });
      const receipt = await tx.wait();
      const event = receipt?.logs.find(
        (log) => log.fragment.name === "PersonalFundMeCreated"
      );
      const personalFundMeAddress = event?.args[1];

      // Attach the contract instance
      fundMe = await ethers.getContractAt(
        "PersonalFundMe",
        personalFundMeAddress
      );
    });

    it("should allow valid deposits within the funding period", async function () {
      const depositAmount = ethers.parseEther("0.02");

      await expect(fundMe.connect(user).deposit({ value: depositAmount }))
        .to.emit(fundMe, "Deposited")
        .withArgs(user.address, depositAmount);

      // Check the contribution mapping
      const contribution = await fundMe.contributions(user.address);
      expect(contribution).to.equal(depositAmount);
    });

    it("should revert deposit if amount is below the minimum funding requirement", async function () {
      const smallDeposit = ethers.parseEther("0.001");

      await expect(
        fundMe.connect(user).deposit({ value: smallDeposit })
      ).to.be.revertedWithCustomError(fundMe, "PersonalFundMe__AmountTooLow");
    });

    it("should revert deposit if it exceeds the maximum fund limit", async function () {
      const firstDeposit = ethers.parseEther("0.5");
      await fundMe.connect(user).deposit({ value: firstDeposit });

      const secondDeposit = ethers.parseEther("0.6");
      await expect(
        fundMe.connect(user).deposit({ value: secondDeposit })
      ).to.be.revertedWithCustomError(
        fundMe,
        "PersonalFundMe__ExceedsMaxLimit"
      );
    });

    it("should allow the factory moderator to pause a campaign", async function () {
      await expect(
        factory
          .connect(moderator)
          .pausePersonalFundMeContract(await fundMe.getAddress(), true)
      )
        .to.emit(fundMe, "Paused")
        .withArgs(true);

      expect(await fundMe.isPaused()).to.equal(true);
    });

    it("should not allow withdrawal approval before the funding period ends", async function () {
      await expect(
        factory.connect(moderator).approveWithdraw(await fundMe.getAddress())
      ).to.be.revertedWithCustomError(
        fundMe,
        "PersonalFundMe__FundingStillActive"
      );
    });

    it("should allow withdrawal approval after the funding period and then allow withdrawal", async function () {
      const depositAmount = ethers.parseEther("0.05");
      await fundMe.connect(user).deposit({ value: depositAmount });

      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [duration + 1]);
      await ethers.provider.send("evm_mine", []);

      await expect(
        factory.connect(moderator).approveWithdraw(await fundMe.getAddress())
      ).to.emit(fundMe, "WithdrawApproved");

      // Track user balance before withdrawal
      const balanceBefore = await ethers.provider.getBalance(user.address);

      // Withdraw funds
      const txResponse = await fundMe.connect(user).withdraw();
      const receipt = await txResponse.wait();
      const gasUsed = BigInt(
        Number(receipt?.gasUsed) * Number(receipt?.gasPrice)
      );

      // Balance after withdrawal
      const balanceAfter = await ethers.provider.getBalance(user.address);
      expect(balanceAfter).to.be.closeTo(
        balanceBefore + depositAmount - gasUsed,
        ethers.parseEther("0.001")
      );
    });

    it("should revert withdrawal if it has not been approved", async function () {
      const depositAmount = ethers.parseEther("0.03");
      await fundMe.connect(user).deposit({ value: depositAmount });

      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [duration + 1]);
      await ethers.provider.send("evm_mine", []);

      await expect(
        fundMe.connect(user).withdraw()
      ).to.be.revertedWithCustomError(fundMe, "PersonalFundMe__NotApproved");
    });
  });

  describe("Factory fee withdrawal", function () {
    it("should allow only the owner to withdraw collected fees", async function () {
      const feeProvided = ethers.parseEther("0.002");
      await factory
        .connect(user)
        .createPersonalFundMe(minFund, maxFund, duration, {
          value: feeProvided,
        });

      const factoryBalance = await ethers.provider.getBalance(
        await factory.getAddress()
      );
      expect(factoryBalance).to.be.gt(0);

      await expect(factory.withdrawFees()).to.not.be.reverted;
    });

    it("should revert fee withdrawal if called by non-owner", async function () {
      await expect(
        factory.connect(user).withdrawFees()
      ).to.be.revertedWithCustomError(
        factory,
        "CapitaFundingFactory__NotOwner"
      );
    });
  });
});

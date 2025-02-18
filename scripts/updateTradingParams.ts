import { ethers } from "hardhat";

async function main() {
  const [owner] = await ethers.getSigners();

  console.log("Updating trading params....");
  const CapitaToken = await ethers.getContractAt(
    "CapitaToken",
    "0x85145d98b885c9585862C36cbdA9C231f68A76b7",
    owner
  );

  await CapitaToken.updateTradingParams(true, 3, 10, 1, true);

  console.log("Trading params updated.", await CapitaToken.tradingEnabled());
}

main().catch((error) => {
  console.log(error);
  process.exitCode = 1;
});

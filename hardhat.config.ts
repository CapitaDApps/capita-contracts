import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition-ethers";
import dotenv from "dotenv";
import "hardhat-gas-reporter";
dotenv.config();

const alchemyEndpointKey = process.env.ALCHEMY_ENDPOINT_KEY || "";
const coinmarketcapAPIKey = process.env.COINMARKETCAP_API_KEY || "";
const etherscanAPIKey = process.env.ETHERSCAN_API_KEY || "";
const privateKey = process.env.PRIVATE_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.5.16",
      },
      { version: "0.6.6" },
      { version: "0.8.20" },
    ],
  },

  networks: {
    hardhat: {
      forking: {
        url: `https://base-mainnet.g.alchemy.com/v2/${alchemyEndpointKey}`,
      },
    },

    base: {
      url: `https://base-mainnet.g.alchemy.com/v2/${alchemyEndpointKey}`,
    },

    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${alchemyEndpointKey}`,
      accounts: [privateKey],
    },

    local: {
      // url: "http://54.164.65.171:8545",
      url: "http://127.0.0.1:8545",
    },
  },

  gasReporter: {
    enabled: false,
    currency: "USD",
    L2: "base",
    coinmarketcap: coinmarketcapAPIKey,
    L1Etherscan: etherscanAPIKey,
  },
};

export default config;

// (5827914 * 0.000000001456 * 2745) - token

// (1584941 * 0.000000001456 * 2745) - prezsale

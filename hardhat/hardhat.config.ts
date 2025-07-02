import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const ETHEREUM_URL = process.env.ETHEREUM_URL ?? "";
const PRIVATE_KEY = process.env.PRIVATE_KEY ?? "";
const ETHER_API_KEY = process.env.ETHER_API_KEY ?? "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    sepolia: {
      url: ETHEREUM_URL,
      accounts: [PRIVATE_KEY],
    },
    ethereum: {
      url: ETHEREUM_URL,
      accounts: [PRIVATE_KEY],
      chainId: 11155111,
    },
  },
  sourcify: {
    enabled: true,
  },
  etherscan: {
    apiKey: ETHER_API_KEY,
    customChains: [
      {
        network: "eth",
        chainId: 11155111,
        urls: {
          apiURL: "https://api-sepolia.etherscan.io/api",
          browserURL: "https://sepolia.etherscan.io/",
        },
      },
    ],
  },
};

export default config;
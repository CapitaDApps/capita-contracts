import { ethers, artifacts, network } from "hardhat";
import { Factory, factoryAddresses, Router, routerAddresses } from "../config";

async function uniswap(tokenAddress: string, network: string) {
  const v2RouterArtifact = await artifacts.readArtifact("UniswapV2Router02");

  const { uniswapV2FactoryAddr, uniswapV2RouterAddr } =
    getRouterAndFactory(network);

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
  tokenAddress: string,
  network: string,
  tokenAmount: string,
  ethAmount: string,
  to: string
) {
  const { UniswapV2Router, WETH_addr } = await uniswap(tokenAddress, network);

  console.log({ WETH_addr, tokenAddress });

  const parseTokenAmount = ethers.parseEther(tokenAmount);
  const { uniswapV2RouterAddr } = getRouterAndFactory(network);

  await token.approve(uniswapV2RouterAddr, parseTokenAmount);

  return await UniswapV2Router.addLiquidityETH(
    tokenAddress,
    parseTokenAmount,
    0,
    0,
    to,
    txDeadline(),
    { value: ethers.parseEther(ethAmount) }
  );
}

function getRouterAndFactory(network: string) {
  const uniswapV2RouterAddr = routerAddresses[network as Router];
  const uniswapV2FactoryAddr = factoryAddresses[network as Factory];

  return { uniswapV2RouterAddr, uniswapV2FactoryAddr };
}

function txDeadline() {
  return Math.ceil(Date.now() / 1000 + 300);
}

async function main() {
  const [owner] = await ethers.getSigners();
  const tokenAddress = "0xAA5c5496e2586F81d8d2d0B970eB85aB088639c2";
  const net = network.name;
  const CapitaToken = await ethers.getContractAt(
    "CapitaToken",
    tokenAddress,
    owner
  );
  const tokenAmount = "20000000";
  const ethAmount = "20";

  console.log("Adding liquidity...");
  await addLq(
    CapitaToken,
    tokenAddress,
    net,
    tokenAmount,
    ethAmount,
    owner.address
  );

  console.log("Liquidity Added.");
}

main().catch((error) => {
  console.log(error);
  process.exitCode = 1;
});

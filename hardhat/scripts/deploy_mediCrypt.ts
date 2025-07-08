import { ethers } from "hardhat";

async function main() {
  console.log("Starting MediCrypt contract deployment...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log(
    "Account balance:",
    (await ethers.provider.getBalance(deployer.address)).toString()
  );

  const MediCrypt = await ethers.getContractFactory("MediCrypt");
  console.log("Deploying MediCrypt contract...");

  const contract = await MediCrypt.deploy();
  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();
  console.log(`MediCrypt contract deployed to: ${contractAddress}`);

  const owner = await contract.owner();
  console.log(`Contract owner: ${owner}`);
  console.log(`Contract name: ${await contract.name()}`);
  console.log(`Contract symbol: ${await contract.symbol()}`);

  console.log("✅ Deployment completed successfully!");
  console.log(`📝 Contract address: ${contractAddress}`);
  console.log(`🔗 Add this address to your frontend configuration`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
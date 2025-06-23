const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying DecentralizedExchange contract...");

  // Get the ContractFactory and Signers here
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Deploy the contract
  const DecentralizedExchange = await ethers.getContractFactory("DecentralizedExchange");
  const dex = await DecentralizedExchange.deploy();

  await dex.deployed();

  console.log("DecentralizedExchange contract deployed to:", dex.address);
  console.log("Transaction hash:", dex.deployTransaction.hash);
  
  // Log some additional deployment info
  console.log("Contract owner:", await dex.owner());
  console.log("Fee rate: 0.3%");
  console.log("Ready to create trading pools!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

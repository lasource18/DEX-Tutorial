const { ethers } = require('hardhat')
const { CRYPTO_DEVS_TOKEN_CONTRACT_ADDRESS } = require('../constants')

async function main() {
  const cryptoDevTokenAddress = CRYPTO_DEVS_TOKEN_CONTRACT_ADDRESS
  
  const exchangeContract = await ethers.getContractFactory('Exchange')

  const deployedExchangeContract = await exchangeContract.deploy(cryptoDevTokenAddress)

  await deployedExchangeContract.deployed()

  console.log("Exchange Contract Address:", deployedExchangeContract.address)
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e)
    process.exit(1)
  })
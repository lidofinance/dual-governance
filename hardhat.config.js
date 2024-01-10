require("@nomicfoundation/hardhat-chai-matchers")
require("@nomicfoundation/hardhat-foundry")
require("@nomicfoundation/hardhat-toolbox")
require("solidity-coverage")

module.exports = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: {
          optimizer: {
            enabled: false,
          }
        },
      },
    ],
  },
}

var HDWalletProvider = require("truffle-hdwallet-provider");
var mnemonic = "liar notice craft castle blood candy pitch situate other frequent dune proof";

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*",
    }
  },
  compilers: {
    solc: {
      version: "^0.4.24"
    }
  }
};

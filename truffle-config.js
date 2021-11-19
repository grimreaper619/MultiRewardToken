const HDWalletProvider = require('@truffle/hdwallet-provider');
require('dotenv').config();
module.exports = {
 networks: {
  development: {
   host: '127.0.0.1', // Localhost (default: none)
   port: 8545, // Standard Ethereum port (default: none)
   network_id: '*', // Any network (default: none)
   gas: 12000000,
   from: process.env.OWNER,
  },
  ropsten: {
   provider: () =>
    new HDWalletProvider(process.env.MNEMONIC, process.env.ROPSTEN, 0),
   network_id: 3,
   gas: 12000000,
   gasPrice: 10000000000,
   timeoutBlocks: 5000000, // # of blocks before a deployment times out  (minimum/default: 50)
   skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
   // confirmations: 2,    // # of confs to wait between deployments. (default: 0)
   // timeoutBlocks: 200,  // # of blocks before a deployment times out  (minimum/default: 50)
   // skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
  },
  rinkeby: {
   provider: () =>
    new HDWalletProvider(process.env.MNEMONIC, process.env.RINKEBY),
   network_id: 4,
   gas: 12000000,
   gasPrice: 10000000000,
   skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
  },
  bsctestnet: {
   provider: () =>
    new HDWalletProvider(process.env.MNEMONIC, process.env.BSCTESTNET),
   network_id: 97,
   gas: 12000000,
   skipDryRun: true,
  },
  bscmainnet: {
    provider: () =>
     new HDWalletProvider(process.env.MNEMONIC, process.env.BSCMAINNET),
    network_id: 56,
    skipDryRun: true,
    },
  mainnet: {
   provider: () =>
    new HDWalletProvider(process.env.MNEMONIC, process.env.MAINNET, 0),
   network_id: 1,
   gas: 8000000,
   gasPrice: 50000000000,
   timeoutBlocks: 5000000, // # of blocks before a deployment times out  (minimum/default: 50)
   skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
   from: process.env.ACCOUNT,
  },
 },
 //
 // Configure your compilers
 compilers: {
  solc: {
   version: '0.8.8', // Fetch exact version from solc-bin (default: truffle's version)
   // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
   settings: {
    // See the solidity docs for advice about optimization and evmVersion
    optimizer: {
     enabled: true,
     runs: 9999,
    },
    //  evmVersion: "byzantium"
   },
  },
 },

 plugins: ['truffle-plugin-verify'],
 api_keys: {
  etherscan: process.env.ETHERAPI, // Add  API key
  bscscan: process.env.BSCSCAN,
 },
};

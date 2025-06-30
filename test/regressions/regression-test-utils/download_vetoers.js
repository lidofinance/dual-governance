const path = require("path");
const {
  blockscoutDownloadTokenHolders,
} = require("./blockscout_download_token_holders");

const NETWORK_NAME = "mainnet";
const FILENAME_PREFIX = "";

const ST_ETH_ADDRESS = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";
const ST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 3;
const ST_ETH_HOLDERS_CHUNK_ADDRESSES_AMOUNT = 1000;
const ST_ETH_HOLDERS_FILE_NAME = path.join(
  __dirname,
  "..",
  "complete-rage-quit-files",
  `${FILENAME_PREFIX}steth_vetoers.json`
);
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES = new Set([
  "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0".toLowerCase(), // WstETH
  "0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1".toLowerCase(), // WithdrawalQueue
  "0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c".toLowerCase(), // Aragon Agent
]);
const ST_ETH_TOTAL_SUPPLY_PERCENTAGE = 35; // Currently WstETH contract holds approximately 47% of StEth, so no need to collect this 47% of WstEth (StEth) holders.

const WST_ETH_ADDRESS = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";
const WST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 1;
const WST_ETH_HOLDERS_FILE_NAME = path.join(
  __dirname,
  "..",
  "complete-rage-quit-files",
  `${FILENAME_PREFIX}wsteth_vetoers.json`
);

async function main() {
  console.log(
    "---------------------------------------------------------------------------------------"
  );
  console.log(`This script downloads the addresses of StEth holders having approximately 50% of StEth and the first
300 WStEth holders at the current block of network ${NETWORK_NAME} from Blockscout and saves it to the files 
"${FILENAME_PREFIX}steth_vetoers.json" and "${FILENAME_PREFIX}wsteth_vetoers.json" 
appropriately that is intended for use in Multiple-Rounds-RageQuit regression test. After updating the StEth/WStEth holders' data files 
don't forget to update the env variable FORK_BLOCK_NUMBER with the actual block number before running the regression test.`);
  console.log(
    "---------------------------------------------------------------------------------------"
  );
  console.log("Downloading StETH holders");

  await blockscoutDownloadTokenHolders(
    NETWORK_NAME,
    ST_ETH_ADDRESS,
    ST_ETH_HOLDERS_LOAD_CHUNKS_COUNT,
    ST_ETH_HOLDERS_FILE_NAME,
    ST_ETH_HOLDERS_EXCLUDE_ADDRESSES,
    ST_ETH_TOTAL_SUPPLY_PERCENTAGE,
    ST_ETH_HOLDERS_CHUNK_ADDRESSES_AMOUNT
  );

  console.log(
    "---------------------------------------------------------------------------------------"
  );
  console.log("Downloading WStETH holders");

  await blockscoutDownloadTokenHolders(
    NETWORK_NAME,
    WST_ETH_ADDRESS,
    WST_ETH_HOLDERS_LOAD_CHUNKS_COUNT,
    WST_ETH_HOLDERS_FILE_NAME,
    undefined
  );

  console.log(
    "---------------------------------------------------------------------------------------"
  );
}

main();

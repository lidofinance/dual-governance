const path = require("path");
const { blockscoutDownloadTokenHolders } = require('./blockscout_download_token_holders');

const NETWORK_NAME = "holesky";
const FILENAME_PREFIX = "holesky_";

const ST_ETH_ADDRESS = "0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034";
const ST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 3;
const ST_ETH_HOLDERS_CHUNK_ADDRESSES_AMOUNT = 1000;
const ST_ETH_HOLDERS_FILE_NAME = path.join(
    __dirname,
    "..",
    "complete-rage-quit-files",
    `${FILENAME_PREFIX}steth_vetoers.json`
);
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES = new Set([
    "0x8d09a4502Cc8Cf1547aD300E066060D043f6982D".toLowerCase(), // WstETH
    "0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50".toLowerCase(), // WithdrawalQueue
    "0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d".toLowerCase(), // Aragon Agent
]);
const ST_ETH_TOTAL_SUPPLY_PERCENTAGE = 50;

const WST_ETH_ADDRESS = "0x8d09a4502Cc8Cf1547aD300E066060D043f6982D";
const WST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 1;
const WST_ETH_HOLDERS_FILE_NAME = path.join(
    __dirname,
    "..",
    "complete-rage-quit-files",
    `${FILENAME_PREFIX}wsteth_vetoers.json`
);

async function main() {
    console.log("---------------------------------------------------------------------------------------");
    console.log(`This script downloads the addresses of StEth holders having approximately 50% of StEth and the first
300 WStEth holders at the current block of network ${NETWORK_NAME} from Blockscout and saves it to the files 
"${FILENAME_PREFIX}steth_vetoers.json" and "${FILENAME_PREFIX}wsteth_vetoers.json" 
appropriately that is intended for use in Multiple-Rounds-RageQuit regression test. After updating the StEth/WStEth holders' data files 
don't forget to update the env variable FORK_BLOCK_NUMBER with the actual block number before running the regression test.`);
    console.log("---------------------------------------------------------------------------------------");
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

    console.log("---------------------------------------------------------------------------------------");
    console.log("Downloading WStETH holders");

    await blockscoutDownloadTokenHolders(
        NETWORK_NAME,
        WST_ETH_ADDRESS,
        WST_ETH_HOLDERS_LOAD_CHUNKS_COUNT,
        WST_ETH_HOLDERS_FILE_NAME,
        undefined
    );


    console.log("---------------------------------------------------------------------------------------");
}

main();

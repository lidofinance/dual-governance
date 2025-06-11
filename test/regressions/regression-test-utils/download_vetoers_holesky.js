const { blockscoutDownloadTokenHolders } = require('./blockscout_download_token_holders');

const NETWORK_NAME = "holesky";
const FILENAME_PREFIX = "holesky_";

const ST_ETH_ADDRESS = "0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034";
const ST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 80;
const ST_ETH_HOLDERS_FILE_NAME = `../complete-rage-quit-files/${FILENAME_PREFIX}steth_vetoers.json`;
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES = new Set([
    "0x8d09a4502Cc8Cf1547aD300E066060D043f6982D", // WstETH
    "0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50" // WithdrawalQueue
]);
const ST_ETH_TOTAL_SUPPLY_PERCENTAGE = 50;

const WST_ETH_ADDRESS = "0x8d09a4502Cc8Cf1547aD300E066060D043f6982D";
const WST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 6;
const WST_ETH_HOLDERS_FILE_NAME = `../complete-rage-quit-files/${FILENAME_PREFIX}wsteth_vetoers.json`;

const UNST_ETH_ADDRESS = "0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50";
const UNST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 6;
const UNST_ETH_HOLDERS_FILE_NAME = `../complete-rage-quit-files/${FILENAME_PREFIX}unsteth_vetoers.json`;

async function main() {
    console.log("---------------------------------------------------------------------------------------");
    console.log(`This script downloads the addresses of the first 4000 (approx) StEth holders and the first
300 WStEth and UnStEth holders at the current block of network ${NETWORK_NAME} from Blockscout and saves it to the files 
"${FILENAME_PREFIX}steth_vetoers.json", "${FILENAME_PREFIX}wsteth_vetoers.json" and "${FILENAME_PREFIX}unsteth_vetoers.json" 
appropriately that is intended for use in 4-Rounds-RageQuit regression test. After updating the StEth/WStEth holders' data files
don't forget to update the env variable FORK_BLOCK_NUMBER with the actual block number before running the regression test.`);
    console.log("---------------------------------------------------------------------------------------");
    console.log("Downloading StETH holders");

    await blockscoutDownloadTokenHolders(
        NETWORK_NAME,
        ST_ETH_ADDRESS,
        ST_ETH_HOLDERS_LOAD_CHUNKS_COUNT,
        ST_ETH_HOLDERS_FILE_NAME,
        ST_ETH_HOLDERS_EXCLUDE_ADDRESSES,
        ST_ETH_TOTAL_SUPPLY_PERCENTAGE
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
    console.log("Downloading UnStETH holders");

    await blockscoutDownloadTokenHolders(
        NETWORK_NAME,
        UNST_ETH_ADDRESS,
        UNST_ETH_HOLDERS_LOAD_CHUNKS_COUNT,
        UNST_ETH_HOLDERS_FILE_NAME,
        undefined
    );
}

main();

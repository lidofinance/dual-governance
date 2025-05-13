const { blockscoutDownloadTokenHolders } = require('./blockscout_download_token_holders');

const NETWORK_NAME = "hoodi";
const FILENAME_PREFIX = "hoodi_";

const ST_ETH_ADDRESS = "0x3508A952176b3c15387C97BE809eaffB1982176a";
const ST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 80;
const ST_ETH_HOLDERS_FILE_NAME = `../complete-rage-quit-files/${FILENAME_PREFIX}steth_vetoers.json`;
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES = new Set([
    "0x7E99eE3C66636DE415D2d7C880938F2f40f94De4", // WstETH
    "0xfe56573178f1bcdf53F01A6E9977670dcBBD9186" // WithdrawalQueue
]);
const ST_ETH_TOTAL_SUPPLY_PERCENTAGE = 50;

const WST_ETH_ADDRESS = "0x7E99eE3C66636DE415D2d7C880938F2f40f94De4";
const WST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 6;
const WST_ETH_HOLDERS_FILE_NAME = `../complete-rage-quit-files/${FILENAME_PREFIX}wsteth_vetoers.json`;

async function main() {
    console.log("---------------------------------------------------------------------------------------");
    console.log(`This script downloads the addresses of the first 4000 (approx) StEth holders and the first
300 WStEth holders at the current block of network ${NETWORK_NAME} from Blockscout and saves it to the files 
"${FILENAME_PREFIX}steth_vetoers.json" and "${FILENAME_PREFIX}wsteth_vetoers.json" appropriately that is 
intended for use in 4-Rounds-RageQuit regression test. After updating the StEth/WStEth holders' data files 
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
}

main();

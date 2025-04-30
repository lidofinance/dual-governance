const {blockscoutDownloadTokenHolders} = require('./blockscout_download_token_holders');

const ST_ETH_ADDRESS = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";
const ST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 80;
const ST_ETH_HOLDERS_FILE_NAME = "../complete-rage-quit-files/steth_vetoers.json";
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES = new Set([
    "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0", // WstETH
    "0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1" // WithdrawalQueue
]);
const ST_ETH_TOTAL_SUPPLY_PERCENTAGE = 50;

const WST_ETH_ADDRESS = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";
const WST_ETH_HOLDERS_LOAD_CHUNKS_COUNT = 6;
const WST_ETH_HOLDERS_FILE_NAME = "../complete-rage-quit-files/wsteth_vetoers.json";

async function main() {
    console.log("---------------------------------------------------------------------------------------");
    console.log(`This script downloads the addresses of the first 4000 (approx) StEth holders and the first
300 WStEth holders at the current block from Blockscout and saves it to the files "steth_vetoers.json"
"wsteth_vetoers.json" appropriately that is intended for use in 4-Rounds-RageQuit regression test.
After updating the StEth/WStEth holders' data files don't forget to update the env variable
FORK_BLOCK_NUMBER with the actual block number before running the regression test.`);
    console.log("---------------------------------------------------------------------------------------");
    console.log("Downloading StETH holders");
    
    await blockscoutDownloadTokenHolders(
        ST_ETH_ADDRESS,
        ST_ETH_HOLDERS_LOAD_CHUNKS_COUNT,
        ST_ETH_HOLDERS_FILE_NAME,
        ST_ETH_HOLDERS_EXCLUDE_ADDRESSES,
        ST_ETH_TOTAL_SUPPLY_PERCENTAGE
    );

    console.log("---------------------------------------------------------------------------------------");
    console.log("Downloading WStETH holders");

    await blockscoutDownloadTokenHolders(
        WST_ETH_ADDRESS,
        WST_ETH_HOLDERS_LOAD_CHUNKS_COUNT,
        WST_ETH_HOLDERS_FILE_NAME,
        undefined
    );
}

main();



const { downloadVetoersSet } = require("./download_vetoers_set");

const NETWORK_NAME = "holesky";

const ST_ETH_ADDRESS = "0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034";
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES = new Set([
    "0x8d09a4502Cc8Cf1547aD300E066060D043f6982D".toLowerCase(), // WstETH
    "0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50".toLowerCase(), // WithdrawalQueue
    "0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d".toLowerCase(), // Aragon Agent
]);

// Exclude WithdrawalQueue and Aragon Agent contracts at this step and keep WstETH as counted, due to WstEth token holders will be enumerated separately at the second step.
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES_FROM_PERCENTAGE_COUNT = new Set([
    "0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50".toLowerCase(), // WithdrawalQueue
    "0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d".toLowerCase(), // Aragon Agent
]);

const WST_ETH_ADDRESS = "0x8d09a4502Cc8Cf1547aD300E066060D043f6982D";

async function main() {
    await downloadVetoersSet(
        NETWORK_NAME,
        {
            stEthAddress: ST_ETH_ADDRESS,
            desiredPercentage: 80,
            addressesPerChunk: 1000,
            excludeAddresses: ST_ETH_HOLDERS_EXCLUDE_ADDRESSES,
            excludeAddressesFromPercentageCount: ST_ETH_HOLDERS_EXCLUDE_ADDRESSES_FROM_PERCENTAGE_COUNT,
            fileName: 'holesky_steth_vetoers.json'
        },
        {
            wstEthAddress: WST_ETH_ADDRESS,
            desiredPercentage: 95,
            fileName: 'holesky_wsteth_vetoers.json'
        }
    );
}

main();

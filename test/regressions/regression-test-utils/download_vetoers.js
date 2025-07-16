const { downloadVetoersSet } = require("./download_vetoers_set");

const NETWORK_NAME = "mainnet";

const ST_ETH_ADDRESS = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES = new Set([
    "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0".toLowerCase(), // WstETH
    "0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1".toLowerCase(), // WithdrawalQueue
    "0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c".toLowerCase(), // Aragon Agent
]);

// Exclude WithdrawalQueue and Aragon Agent contracts at this step and keep WstETH as counted, due to WstEth token holders will be enumerated separately at the second step.
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES_FROM_PERCENTAGE_COUNT = new Set([
    "0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1".toLowerCase(), // WithdrawalQueue
    "0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c".toLowerCase(), // Aragon Agent
]);

const WST_ETH_ADDRESS = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";

async function main() {
    await downloadVetoersSet(
        NETWORK_NAME,
        {
            stEthAddress: ST_ETH_ADDRESS,
            desiredPercentage: 80,
            addressesPerChunk: 1000,
            excludeAddresses: ST_ETH_HOLDERS_EXCLUDE_ADDRESSES,
            excludeAddressesFromPercentageCount: ST_ETH_HOLDERS_EXCLUDE_ADDRESSES_FROM_PERCENTAGE_COUNT,
            fileName: 'steth_vetoers.json'
        },
        {
            wstEthAddress: WST_ETH_ADDRESS,
            desiredPercentage: 95,
            fileName: 'wsteth_vetoers.json'
        }
    );
}

main();

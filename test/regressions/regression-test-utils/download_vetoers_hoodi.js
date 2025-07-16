const { downloadVetoersSet } = require("./download_vetoers_set");

const NETWORK_NAME = "hoodi";

const ST_ETH_ADDRESS = "0x3508A952176b3c15387C97BE809eaffB1982176a";
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES = new Set([
    "0x7E99eE3C66636DE415D2d7C880938F2f40f94De4".toLowerCase(), // WstETH
    "0xfe56573178f1bcdf53F01A6E9977670dcBBD9186".toLowerCase(), // WithdrawalQueue
    "0x0534aA41907c9631fae990960bCC72d75fA7cfeD".toLowerCase(), // Aragon Agent
]);

// Exclude WithdrawalQueue and Aragon Agent contracts at this step and keep WstETH as counted, due to WstEth token holders will be enumerated separately at the second step.
const ST_ETH_HOLDERS_EXCLUDE_ADDRESSES_FROM_PERCENTAGE_COUNT = new Set([
    "0xfe56573178f1bcdf53F01A6E9977670dcBBD9186".toLowerCase(), // WithdrawalQueue
    "0x0534aA41907c9631fae990960bCC72d75fA7cfeD".toLowerCase(), // Aragon Agent
]);

const WST_ETH_ADDRESS = "0x7E99eE3C66636DE415D2d7C880938F2f40f94De4";

async function main() {
    await downloadVetoersSet(
        NETWORK_NAME,
        {
            stEthAddress: ST_ETH_ADDRESS,
            desiredPercentage: 80,
            addressesPerChunk: 1000,
            excludeAddresses: ST_ETH_HOLDERS_EXCLUDE_ADDRESSES,
            excludeAddressesFromPercentageCount: ST_ETH_HOLDERS_EXCLUDE_ADDRESSES_FROM_PERCENTAGE_COUNT,
            fileName: 'hoodi_steth_vetoers.json'
        },
        {
            wstEthAddress: WST_ETH_ADDRESS,
            desiredPercentage: 95,
            fileName: 'hoodi_wsteth_vetoers.json'
        }
    );
}

main();

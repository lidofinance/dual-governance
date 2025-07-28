const path = require("path");
const {
    blockscoutDownloadTokenHolders,
} = require("./blockscout_download_token_holders");

const filePath = (fileName) => path.join(
    __dirname,
    "..",
    "complete-rage-quit-files",
    fileName
);

/**
 * @typedef {StEthHoldersDownloadSettings}
 * @property {string} stEthAddress
 * @property {number} desiredPercentage
 * @property {number} addressesPerChunk
 * @property {Set<string>} excludeAddresses
 * @property {Set<string>} excludeAddressesFromPercentageCount
 * @property {string} fileName
 */

/**
 * @typedef {WStEthHoldersDownloadSettings}
 * @property {string} wstEthAddress
 * @property {number} desiredPercentage
 * @property {string} fileName
 */

/**
 * @param {string} networkName 
 * @param {StEthHoldersDownloadSettings} stEthSettings 
 * @param {WStEthHoldersDownloadSettings} wstEthSettings 
 */
async function downloadVetoersSet(networkName, stEthSettings, wstEthSettings) {
    console.log(
        "---------------------------------------------------------------------------------------"
    );
    console.log(`This script downloads the addresses of token holders having approximately ${stEthSettings.desiredPercentage}% of StEth and 
approximately ${wstEthSettings.desiredPercentage}% of WStEth at the current block of network ${networkName} from Blockscout and saves it
to the files "${stEthSettings.fileName}" and "${wstEthSettings.fileName}" appropriately that is intended 
for use in Multiple-Rounds-RageQuit regression test. After updating the StEth/WStEth holders' data files don't forget to update the
env variable ${networkName.toUpperCase()}_FORK_BLOCK_NUMBER with the actual block number before running the regression test.`);
    console.log(
        "---------------------------------------------------------------------------------------"
    );
    console.log("Downloading StETH holders");

    await blockscoutDownloadTokenHolders(
        networkName,
        stEthSettings.stEthAddress,
        filePath(stEthSettings.fileName),
        stEthSettings.desiredPercentage,
        {
            addresses: stEthSettings.excludeAddresses,
            percentageCount: stEthSettings.excludeAddressesFromPercentageCount
        },
        stEthSettings.addressesPerChunk
    );

    console.log(
        "---------------------------------------------------------------------------------------"
    );
    console.log("Downloading WStETH holders");

    await blockscoutDownloadTokenHolders(
        networkName,
        wstEthSettings.wstEthAddress,
        filePath(wstEthSettings.fileName),
        wstEthSettings.desiredPercentage
    );

    console.log(
        "---------------------------------------------------------------------------------------"
    );
}

module.exports = { downloadVetoersSet };

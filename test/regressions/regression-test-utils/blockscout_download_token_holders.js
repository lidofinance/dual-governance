const { writeFile } = require('node:fs/promises');

const MAX_ITERATIONS = 200;
const DELAY_BETWEEN_QUERIES = 2000;

// --------------------------------
// HTTP requests retries settings
// --------------------------------
const REQUEST_TIMEOUT = 30000; // Max response wait time for single request; 30s
const DELAY_BETWEEN_RETRIES_INITIAL = 1000; // 1s
const DELAY_MULTIPLIER_BASE = 2; // Actual Delay between retries = DELAY_MULTIPLIER_BASE ^ (attempt number) * DELAY_BETWEEN_RETRIES_INITIAL
const MAX_RETRIES_COUNT = 5;
// Given the constants above values 30000, 1000, 2, 5 the waiting sequence for a single query will look the next:
// [30 + 1, 30 + 2, 30 + 8, 30 + 16, 30 + 32] => The single request may take 3 minutes and 29 seconds max.

const supportedNetworkPrefixes = {
    MAINNET: "eth",
    HOLESKY: "eth-holesky",
    HOODI: "eth-hoodi"
};

const networkUrlPrefix = (networkName) => supportedNetworkPrefixes[`${networkName}`.toUpperCase()] || "";
const getTokenInfoBaseUrl = (networkName, tokenAddress) => `https://${networkUrlPrefix(networkName)}.blockscout.com/api/v2/tokens/${tokenAddress}`;
const getHoldersBaseUrl = (networkName, tokenAddress) => `https://${networkUrlPrefix(networkName)}.blockscout.com/api?module=token&action=getTokenHolders&contractaddress=${tokenAddress}`;
const getBlocksBaseUrl = (networkName) => `https://${networkUrlPrefix(networkName)}.blockscout.com/api/v2/blocks`;

/**
 * @typedef {Object} TokenHoldersAddresses
 * @property {Array<string>} addresses
 */

/**
 * @typedef {Object} ExcludeHoldersParameters
 * @property {Set<string>} [addresses] - set of addresses to exclude from token holders list
 * @property {Set<string>} [percentageCount] - set of addresses to exclude from percentage count, when `totalSupplyPercentage` parameter provided
 */

/**
 * 
 * @param {string} networkName 
 * @param {string} tokenAddress 
 * @param {string} holdersFileName - file name where to save downloaded holders' addresses
 * @param {number} totalSupplyPercentage
 * @param {ExcludeHoldersParameters} [exclude]
 * @param {number} [chunkAddressesAmount]
 */
async function blockscoutDownloadTokenHolders(
    networkName,
    tokenAddress,
    holdersFileName,
    totalSupplyPercentage,
    exclude,
    chunkAddressesAmount = 300,
) {
    checkNetworkName(networkName);

    if (totalSupplyPercentage > 100 || totalSupplyPercentage < 0.1) {
        throw new Error(`Invalid totalSupplyPercentage: ${totalSupplyPercentage} - should be between 0.1 and 100%`);
    }

    const startBlockNumber = await getLatestBlockNumber(getBlocksBaseUrl(networkName));

    const holders = await loadHoldersByPercentage(networkName, tokenAddress, totalSupplyPercentage, chunkAddressesAmount, exclude || {});

    console.log("Total addresses", holders.addresses.length);

    try {
        const endBlockNumber = await getLatestBlockNumber(getBlocksBaseUrl(networkName));

        const blocksRangeMsg =
            endBlockNumber != startBlockNumber
                ? `blocks between ${startBlockNumber} and ${endBlockNumber}`
                : `block ${startBlockNumber}`;
        console.log(`Holders data is actual for the ${blocksRangeMsg}`);
    } catch (e) {
        console.error("Error loading blocks data", e);
    }

    try {
        await writeFile(holdersFileName, JSON.stringify(holders, null, 2), 'utf8');
        console.log(`Data successfully saved to ${holdersFileName}`);
    } catch (error) {
        console.log("An error has occurred", error);
    }
}

/**
 * @param {string} networkName 
 * @param {string} tokenAddress 
 * @param {number} totalSupplyPercentage
 * @param {number} addressesPerChunk 
 * @param {ExcludeHoldersParameters} exclude 
 * @returns {Promise<TokenHoldersAddresses>}
 */
async function loadHoldersByPercentage(
    networkName,
    tokenAddress,
    totalSupplyPercentage,
    addressesPerChunk,
    exclude
) {
    /** @type {TokenHoldersAddresses} */
    const holders = {
        addresses: []
    };

    const tokenInfo = await loadTokenInfo(getTokenInfoBaseUrl(networkName, tokenAddress));
    console.log("Token total_supply", tokenInfo.total_supply);
    const totalSupply = BigInt(tokenInfo.total_supply);

    const desiredHoldersValue = totalSupply * BigInt(totalSupplyPercentage) / BigInt(100);
    console.log("desiredHoldersValue", desiredHoldersValue.toString(), `(${totalSupplyPercentage}%)`);

    let holdersValueAcc = BigInt(0);
    let iter = 0;
    while (holdersValueAcc < desiredHoldersValue && iter < MAX_ITERATIONS) {
        const chunk = await loadHoldersChunk(getHoldersBaseUrl(networkName, tokenAddress), iter + 1, addressesPerChunk);

        holdersValueAcc += processHoldersChunk(holders, chunk, exclude);
        iter++;
    }

    if (iter >= MAX_ITERATIONS) {
        console.log("Iterations limit reached, consider increasing MAX_ITERATIONS or decreasing totalSupplyPercentage");
    }

    return holders;
}

/**
 * @param {TokenHoldersAddresses} acc 
 * @param {Record<string, unknown>} chunk 
 * @param {ExcludeHoldersParameters} exclude 
 * @returns {bigint}
 */
function processHoldersChunk(acc, chunk, exclude) {
    if (chunk.message != "OK") {
        console.log(chunk);
        throw new Error("Invalid data format", chunk);
    }

    let chunkValue = BigInt(0);
    const items = chunk.result;
    for (let i = 0; i < items.length; i++) {
        if (!exclude || !exclude.addresses || !exclude.addresses.has(items[i].address.toLowerCase())) {
            acc.addresses.push(items[i].address);
        }
        if (!exclude || !exclude.percentageCount || !exclude.percentageCount.has(items[i].address.toLowerCase())) {
            chunkValue += BigInt(items[i].value);
        }
    }
    return chunkValue;
}

/**
 * @param {string} url 
 * @returns {Promise<number>}
 */
async function getLatestBlockNumber(url) {
    const data = await loadBlocksData(url);
    return (data.items && data.items[0] && data.items[0]?.height) || 0;
}

/**
 * @param {string} url 
 * @param {(response: Response) => Promise<Record<string, unknown> | undefined>} responseProcessor 
 * @returns {Record<string, unknown>}
 */
async function loadData(url, responseProcessor = getCorrectJsonResponse) {
    const dataProvider = () => fetch(url, {
        signal: AbortSignal.timeout(REQUEST_TIMEOUT),
    });

    const jsonData = await loadDataWithRetries(dataProvider, responseProcessor);
    await delay(DELAY_BETWEEN_QUERIES);
    return jsonData;
}

/**
 * 
 * @param {Response} response 
 * @returns {Promise<Record<string, unknown> | undefined>}
 */
async function getCorrectJsonResponse(response) {
    if (!response.ok) {
        console.error("HTTP Error", response.status);
        return undefined;
    }
    // Response status ~=200

    let responseText;
    try {
        responseText = await response.text();
    } catch (e) {
        console.error("Error getting response", e);
        return undefined;
    }
    // Response body received as text

    let jsonData;
    try {
        jsonData = JSON.parse(responseText);
    } catch (e) {
        console.error("Error parsing JSON", e);
        return undefined;
    }
    // Response body is correct JSON

    return jsonData;
}

/**
 * 
 * @param {Response} response 
 * @returns {Promise<Record<string, unknown> | undefined>}
 */
async function getCorrectHoldersDataResponse(response) {
    const jsonData = await getCorrectJsonResponse(response);

    if (jsonData === undefined) {
        return undefined;
    }

    if (jsonData.message != "OK") {
        console.error("Invalid data format", jsonData);
        return undefined;
    }

    return jsonData;
}

/**
 * @param {string} url
 * @returns {Promise<Record<string, unknown>>}
 */
async function loadTokenInfo(url) {
    console.log("Loading token info", url);
    return loadData(url);
}

/**
 * @param {string} baseUrl
 * @param {number} page
 * @param {number} chunkAddressesAmount
 * @returns {Promise<Record<string, unknown>>}
 */
async function loadHoldersChunk(baseUrl, page, chunkAddressesAmount) {
    const url = makeHoldersChunkUrl(baseUrl, page, chunkAddressesAmount);
    console.log("Loading", url);
    return loadData(url, getCorrectHoldersDataResponse);
}

/**
 * @param {string} url 
 * @returns {Promise<Record<string, unknown>>}
 */
async function loadBlocksData(url) {
    console.log("Loading blocks data", url);
    return loadData(url);
}

/**
 * @param {string} baseUrl
 * @param {number} page
 * @param {number} chunkAddressesAmount
 * @returns {string}
 */
function makeHoldersChunkUrl(baseUrl, page, chunkAddressesAmount) {
    return `${baseUrl}&page=${page}&offset=${chunkAddressesAmount}`;
}

/**
 * @param {number} duration 
 * @returns {Promise<void>}
 */
async function delay(duration) {
    return new Promise((resolve) => {
        setTimeout(resolve, duration);
    });
}

/**
 * @param {string} name 
 */
function checkNetworkName(name) {
    if (!networkUrlPrefix(name)) {
        throw new Error(`Unsupported network: '${name}'. Allowed: ${Object.keys(supportedNetworkPrefixes)}`);
    }
}

/**
 * 
 * @param {() => Promise<Response>} dataLoader
 * @param {(response: Response) => Promise<Record<string, unknown> | undefined>} responseProcessor 
 * @returns {Promise<Record<string, unknown>}
 */
async function loadDataWithRetries(dataLoader, responseProcessor) {
    for (let tryIdx = 0; tryIdx < MAX_RETRIES_COUNT; tryIdx++) {
        try {
            const response = await dataLoader();
            const data = await responseProcessor(response);
            if (data !== undefined) {
                return data;
            }
            console.log("Incorrect response returned on retry #", tryIdx + 1);
        } catch (error) {
            console.error("Error on retry #", tryIdx + 1, error);
        }

        const actualPauseMs = Math.pow(DELAY_MULTIPLIER_BASE, tryIdx) * DELAY_BETWEEN_RETRIES_INITIAL;
        console.log("Wait", actualPauseMs, "ms");
        await delay(actualPauseMs);
    }

    throw new Error(`Retry attempts exhausted after ${MAX_RETRIES_COUNT} tries`);
}


module.exports = { blockscoutDownloadTokenHolders };

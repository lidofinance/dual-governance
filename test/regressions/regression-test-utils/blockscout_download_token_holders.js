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
 * 
 * @param {string} networkName 
 * @param {string} tokenAddress 
 * @param {number} chunksCount - each chunk contains approximately 300 addresses by default
 * @param {string} holdersFileName - file name where to save downloaded holders' addresses
 * @param {Set<string>} [excludeAddresses]
 * @param {number} [totalSupplyPercentage]
 * @param {number} [chunkAddressesAmount]
 */
async function blockscoutDownloadTokenHolders(networkName, tokenAddress, chunksCount, holdersFileName, excludeAddresses, totalSupplyPercentage, chunkAddressesAmount = 300) {
    checkNetworkName(networkName);

    const holders = {
        addresses: []
    };

    let desiredHoldersValue;

    const startBlockNumber = await getLatestBlockNumber(getBlocksBaseUrl(networkName));

    await delay(DELAY_BETWEEN_QUERIES);

    if (totalSupplyPercentage !== undefined) {
        if (totalSupplyPercentage > 100) {
            throw new Error(`Invalid totalSupplyPercentage: ${totalSupplyPercentage} - should not exceed 100%`);
        }

        const tokenInfo = await loadTokenInfo(getTokenInfoBaseUrl(networkName, tokenAddress));
        console.log("Token total_supply", tokenInfo.total_supply);
        const totalSupply = BigInt(tokenInfo.total_supply);

        desiredHoldersValue = totalSupply * BigInt(totalSupplyPercentage) / BigInt(100);
        console.log("desiredHoldersValue", desiredHoldersValue.toString());
    }

    if (desiredHoldersValue !== undefined) {
        let holdersValueAcc = BigInt(0);
        let iter = 0;
        while (holdersValueAcc < desiredHoldersValue && iter < MAX_ITERATIONS) {
            const chunk = await loadHoldersChunk(getHoldersBaseUrl(networkName, tokenAddress), iter + 1, chunkAddressesAmount);

            holdersValueAcc += processHoldersChunk(holders, chunk, excludeAddresses);
            iter++;
            await delay(DELAY_BETWEEN_QUERIES);
        }

        if (iter >= MAX_ITERATIONS) {
            console.log("Iterations limit reached, consider increasing MAX_ITERATIONS or decreasing totalSupplyPercentage");
        }
    } else {
        for (let i = 0; i < chunksCount; ++i) {
            const chunk = await loadHoldersChunk(getHoldersBaseUrl(networkName, tokenAddress), i + 1, chunkAddressesAmount);

            processHoldersChunk(holders, chunk, excludeAddresses);
            await delay(DELAY_BETWEEN_QUERIES);
        }
    }

    console.log("Total addresses", holders.addresses.length);

    await delay(DELAY_BETWEEN_QUERIES);

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

function processHoldersChunk(acc, chunk, excludeAddresses) {
    if (chunk.message != "OK") {
        console.log(chunk);
        throw new Error("Invalid data format", chunk);
    }

    let chunkValue = BigInt(0);
    const items = chunk.result;
    for (let i = 0; i < items.length; i++) {
        if (!excludeAddresses || !excludeAddresses.has(items[i].address.toLowerCase())) {
            acc.addresses.push(items[i].address);
            chunkValue += BigInt(items[i].value);
        }
    }
    return chunkValue;
}

async function getLatestBlockNumber(url) {
    const data = await loadBlocksData(url);
    return (data.items && data.items[0] && data.items[0]?.height) || 0;
}

async function loadData(url, responseProcessor = getCorrectJsonResponse) {
    const dataProvider = () => fetch(url, {
        signal: AbortSignal.timeout(REQUEST_TIMEOUT),
    });

    const jsonData = await loadDataWithRetries(dataProvider, responseProcessor);

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

async function loadTokenInfo(url) {
    console.log("Loading token info", url);
    return loadData(url);
}

async function loadHoldersChunk(baseUrl, page, chunkAddressesAmount) {
    const url = makeUrl(baseUrl, page, chunkAddressesAmount);
    console.log("Loading", url);
    return loadData(url, getCorrectHoldersDataResponse);
}

async function loadBlocksData(url) {
    console.log("Loading blocks data", url);
    return loadData(url);
}

function makeUrl(baseUrl, page, chunkAddressesAmount) {
    return `${baseUrl}&page=${page}&offset=${chunkAddressesAmount}`;
}

async function delay(duration) {
    return new Promise((resolve) => {
        setTimeout(resolve, duration);
    });
}

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

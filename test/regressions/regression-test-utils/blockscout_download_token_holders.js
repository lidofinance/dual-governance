const { writeFile } = require('node:fs/promises');

const MAX_ITERATIONS = 2000;
const DELAY_BETWEEN_QUERIES = 500;
const NEXT_CHUNK_REQUEST_DEFAULT_DATA = {
    address_hash: "",
    items_count: 0,
    value: "",
    hasMoreData: true
};

const supportedNetworkPrefixes = {
    MAINNET: "eth",
    HOLESKY: "eth-holesky",
    HOODI: "eth-hoodi"
};

const networkUrlPrefix = (networkName) => supportedNetworkPrefixes[`${networkName}`.toUpperCase()] || "";
const getTokenInfoBaseUrl = (networkName, tokenAddress) => `https://${networkUrlPrefix(networkName)}.blockscout.com/api/v2/tokens/${tokenAddress}`;
const getHoldersBaseUrl = (networkName, tokenAddress) => `https://${networkUrlPrefix(networkName)}.blockscout.com/api/v2/tokens/${tokenAddress}/holders`;
const getBlocksBaseUrl = (networkName) => `https://${networkUrlPrefix(networkName)}.blockscout.com/api/v2/blocks`;

/**
 * 
 * @param {string} networkName 
 * @param {string} tokenAddress 
 * @param {number} chunksCount - each chunk contains 50 addresses
 * @param {string} holdersFileName - file name where to save downloaded holders' addresses
 * @param {Set<string>} [excludeAddresses]
 * @param {number} [totalSupplyPercentage]
 */
async function blockscoutDownloadTokenHolders(networkName, tokenAddress, chunksCount, holdersFileName, excludeAddresses, totalSupplyPercentage) {
    checkNetworkName(networkName);

    const holders = {
        addresses: []
    };

    let nextChunkParams = { ...NEXT_CHUNK_REQUEST_DEFAULT_DATA };

    let desiredHoldersValue;

    const startBlockNumber = await getLatestBlockNumber(getBlocksBaseUrl(networkName));

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
        while (holdersValueAcc < desiredHoldersValue && iter < MAX_ITERATIONS && nextChunkParams.hasMoreData) {
            const chunk = await loadHoldersChunk(getHoldersBaseUrl(networkName, tokenAddress), nextChunkParams.address_hash, nextChunkParams.items_count, nextChunkParams.value);

            nextChunkParams = getNextChunkData(chunk);
            holdersValueAcc += processHoldersChunk(holders, chunk, excludeAddresses);
            iter++;
            await delay(DELAY_BETWEEN_QUERIES);
        }

        if (iter >= MAX_ITERATIONS) {
            console.log("Iterations limit reached, consider increasing MAX_ITERATIONS or decreasing totalSupplyPercentage");
        }

        if (!nextChunkParams.hasMoreData) {
            console.log("Data provider has no more holders data for the requested token");
        }
    } else {
        for (let i = 0; i < chunksCount && nextChunkParams.hasMoreData; ++i) {
            const chunk = await loadHoldersChunk(getHoldersBaseUrl(networkName, tokenAddress), nextChunkParams.address_hash, nextChunkParams.items_count, nextChunkParams.value);

            nextChunkParams = getNextChunkData(chunk);
            processHoldersChunk(holders, chunk, excludeAddresses);
            await delay(DELAY_BETWEEN_QUERIES);
        }

        if (!nextChunkParams.hasMoreData) {
            console.log("Data provider has no more holders data for the requested token");
        }
    }

    console.log("Total addresses", holders.addresses.length);
    const endBlockNumber = await getLatestBlockNumber(getBlocksBaseUrl(networkName));

    const blocksRangeMsg =
        endBlockNumber != startBlockNumber
            ? `blocks between ${startBlockNumber} and ${endBlockNumber}`
            : `block ${startBlockNumber}`;
    console.log(`Holders data is actual for the ${blocksRangeMsg}`);

    try {
        await writeFile(holdersFileName, JSON.stringify(holders, null, 2), 'utf8');
        console.log(`Data successfully saved to ${holdersFileName}`);
    } catch (error) {
        console.log('An error has occurred', error);
    }
}

function getNextChunkData(chunk) {
    if (!chunk.next_page_params) {
        return {
            ...NEXT_CHUNK_REQUEST_DEFAULT_DATA,
            hasMoreData: false
        };
    }

    return {
        ...NEXT_CHUNK_REQUEST_DEFAULT_DATA,
        address_hash: chunk.next_page_params.address_hash,
        items_count: chunk.next_page_params.items_count,
        value: chunk.items[chunk.items.length - 1].value // value is stored here as a string, which is required for query param
    };
}

function processHoldersChunk(acc, chunk, excludeAddresses) {
    let chunkValue = BigInt(0);
    const items = chunk.items;
    for (let i = 0; i < items.length; i++) {
        if (!excludeAddresses || !excludeAddresses.has(items[i].address.hash)) {
            acc.addresses.push(items[i].address.hash);
            chunkValue += BigInt(items[i].value);
        }
    }
    return chunkValue;
}

async function getLatestBlockNumber(url) {
    const data = await loadBlocksData(url);
    return (data.items && data.items[0] && data.items[0]?.height) || 0;
}

async function loadData(url) {
    const dataRaw = await fetch(url);
    const text = await dataRaw.text();
    return JSON.parse(text);
}

async function loadTokenInfo(url) {
    console.log("Loading token info", url);
    return loadData(url);
}

async function loadHoldersChunk(baseUrl, address_hash = "", items_count = 0, value = "") {
    const url = makeUrl(baseUrl, address_hash, items_count, value);
    console.log("Loading", url);
    return loadData(url);
}

async function loadBlocksData(url) {
    console.log("Loading blocks data", url);
    return loadData(url);
}

function makeUrl(baseUrl, address_hash = "", items_count = 0, value = "") {
    if (address_hash.length == 0) {
        return baseUrl;
    }
    return `${baseUrl}?address_hash=${address_hash}&items_count=${items_count}&value=${value}`;
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


module.exports = { blockscoutDownloadTokenHolders };

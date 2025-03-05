const { writeFile } = require('node:fs/promises');

const MAX_ITERATIONS = 2000;
const DELAY_BETWEEN_QUERIES = 500;
const getTokenInfoBaseUrl = (tokenAddress) => `https://eth.blockscout.com/api/v2/tokens/${tokenAddress}`;
const getHoldersBaseUrl = (tokenAddress) => `https://eth.blockscout.com/api/v2/tokens/${tokenAddress}/holders`;

/**
 * 
 * @param {string} tokenAddress 
 * @param {number} chunksCount - each chunk contains 50 addresses
 * @param {string} holdersFileName - file name where to save downloaded holders' addresses
 * @param {Set<string>} [excludeAddresses]
 * @param {number} [totalSupplyPercentage]
 */
async function blockscoutDownloadTokenHolders(tokenAddress, chunksCount, holdersFileName, excludeAddresses, totalSupplyPercentage) {
    const holders = {
        addresses: []
    };

    const nextChunkParams = {
        address_hash: "",
        items_count: 0,
        value: ""
    };

    let desiredHoldersValue;

    if (totalSupplyPercentage !== undefined) {
        if (totalSupplyPercentage > 100) {
            throw new Error(`Invalid totalSupplyPercentage: ${totalSupplyPercentage} - should not exceed 100%`);
        }

        const tokenInfo = await loadTokenInfo(getTokenInfoBaseUrl(tokenAddress));
        console.log("Token total_supply", tokenInfo.total_supply);
        const totalSupply = BigInt(tokenInfo.total_supply);

        desiredHoldersValue = totalSupply * BigInt(totalSupplyPercentage) / BigInt(100);
        console.log("desiredHoldersValue", desiredHoldersValue.toString());
    }

    if (desiredHoldersValue !== undefined) {
        let holdersValueAcc = BigInt(0);
        let iter = 0;
        while (holdersValueAcc < desiredHoldersValue && iter < MAX_ITERATIONS) {
            const chunk = await loadHoldersChunk(getHoldersBaseUrl(tokenAddress), nextChunkParams.address_hash, nextChunkParams.items_count, nextChunkParams.value);

            nextChunkParams.address_hash = chunk.next_page_params.address_hash;
            nextChunkParams.items_count = chunk.next_page_params.items_count;
            nextChunkParams.value = chunk.items[chunk.items.length - 1].value; // value as string

            holdersValueAcc += processHoldersChunk(holders, chunk, excludeAddresses);
            iter++;
            await delay(DELAY_BETWEEN_QUERIES);
        }
        if (iter >= MAX_ITERATIONS) {
            console.log("Iterations limit reached, consider increasing MAX_ITERATIONS or decreasing totalSupplyPercentage");
        }
    } else {
        for (let i = 0; i < chunksCount; ++i) {
            const chunk = await loadHoldersChunk(getHoldersBaseUrl(tokenAddress), nextChunkParams.address_hash, nextChunkParams.items_count, nextChunkParams.value);

            nextChunkParams.address_hash = chunk.next_page_params.address_hash;
            nextChunkParams.items_count = chunk.next_page_params.items_count;
            nextChunkParams.value = chunk.items[chunk.items.length - 1].value; // value as string

            processHoldersChunk(holders, chunk, excludeAddresses);
            await delay(DELAY_BETWEEN_QUERIES);
        }
    }

    console.log("Total addresses", holders.addresses.length);

    try {
        await writeFile(holdersFileName, JSON.stringify(holders, null, 2), 'utf8');
        console.log(`Data successfully saved to ${holdersFileName}`);
    } catch (error) {
        console.log('An error has occurred', error);
    }
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

async function loadTokenInfo(url) {
    console.log("Loading token info", url);
    const dataRaw = await fetch(url);
    const text = await dataRaw.text();
    return JSON.parse(text);
}

async function loadHoldersChunk(baseUrl, address_hash = "", items_count = 0, value = "") {
    const url = makeUrl(baseUrl, address_hash, items_count, value);
    console.log("Loading", url);
    const chunk = await fetch(url);
    const chunkText = await chunk.text();
    return JSON.parse(chunkText);
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

module.exports = { blockscoutDownloadTokenHolders };

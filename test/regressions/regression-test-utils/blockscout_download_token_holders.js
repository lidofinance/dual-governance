const { writeFile } = require('node:fs/promises');

const getBaseUrl = (tokenAddress) => `https://eth.blockscout.com/api/v2/tokens/${tokenAddress}/holders`;

async function blockscoutDownloadTokenHolders(tokenAddress, chunksCount, holdersFileName, excludeAddresses) {
    const holders = {
        addresses: []
    };

    const nextChunkParams = {
        address_hash: "",
        items_count: 0,
        value: ""
    };

    for (let i = 0; i < chunksCount; ++i) {
        const chunk = await loadHoldersChunk(getBaseUrl(tokenAddress), nextChunkParams.address_hash, nextChunkParams.items_count, nextChunkParams.value);

        nextChunkParams.address_hash = chunk.next_page_params.address_hash;
        nextChunkParams.items_count = chunk.next_page_params.items_count;
        nextChunkParams.value = chunk.items[chunk.items.length - 1].value; // value as string

        processHoldersChunk(holders, chunk, excludeAddresses);
    }

    console.log("Total", holders.addresses.length);

    try {
        await writeFile(holdersFileName, JSON.stringify(holders, null, 2), 'utf8');
        console.log('Data successfully saved to disk');
    } catch (error) {
        console.log('An error has occurred ', error);
    }
}

function processHoldersChunk(acc, chunk, excludeAddresses) {
    const items = chunk.items;
    for (let i = 0; i < items.length; i++) {
        if (!excludeAddresses || !excludeAddresses.has(items[i].address.hash)) {
            acc.addresses.push(items[i].address.hash);
        }
    }
}

async function loadHoldersChunk(baseUrl, address_hash = "", items_count = 0, value = "") {
    const url = makeUrl(baseUrl, address_hash, items_count, value);
    console.log("Loading", url);
    const chunk = await fetch(url);
    const chunkText = await chunk.text();
    return JSON.parse(chunkText)
}

function makeUrl(baseUrl, address_hash = "", items_count = 0, value = "") {
    if (address_hash.length == 0) {
        return baseUrl;
    }
    return `${baseUrl}?address_hash=${address_hash}&items_count=${items_count}&value=${value}`;
}

module.exports = { blockscoutDownloadTokenHolders };

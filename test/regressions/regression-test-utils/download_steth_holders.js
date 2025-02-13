const {blockscoutDownloadTokenHolders} = require('./blockscout_download_token_holders');

const ST_ETH_ADDRESS = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";
const LOAD_CHUNKS_COUNT = 80;
const FILE_NAME = "steth_vetoers.json";
const EXCLUDE_ADDRESSES = new Set(["0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"]); // WstETH

blockscoutDownloadTokenHolders(
    ST_ETH_ADDRESS,
    LOAD_CHUNKS_COUNT,
    FILE_NAME,
    EXCLUDE_ADDRESSES
);

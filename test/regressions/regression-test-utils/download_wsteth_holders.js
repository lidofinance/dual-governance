const {blockscoutDownloadTokenHolders} = require('./blockscout_download_token_holders');

const ST_ETH_ADDRESS = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";
const LOAD_CHUNKS_COUNT = 6;
const FILE_NAME = "wsteth_vetoers.json";

blockscoutDownloadTokenHolders(
    ST_ETH_ADDRESS,
    LOAD_CHUNKS_COUNT,
    FILE_NAME,
    undefined
);

import "dotenv/config";
import * as fs from "fs";
import * as path from "path";

import { PermissionsLayout } from "./src/permissions-config";
import { EventsCollector, DecodedEvent } from "./src/events-collector";

const BLOCKS_PER_REQUEST = 15_000;
const EVENTS_DIR_PATH = path.join(__dirname, "events");

interface FetchedEvents {
  fromBlock: number;
  toBlock: number;
  events: DecodedEvent[];
}

async function main() {
  const network = process.env.NETWORK || "mainnet";
  let rpcURL: string | undefined = undefined;

  const permissionsConfig = PermissionsLayout.load(network);

  if (network === "mainnet") {
    rpcURL = process.env.MAINNET_RPC_URL;
  } else if (network === "holesky") {
    rpcURL = process.env.HOLESKY_RPC_URL;
  } else if (network === "hoodi") {
    rpcURL = process.env.HOODI_RPC_URL;
  } else {
    throw new Error(`Unsupported network "${network}"`);
  }

  if (!rpcURL) {
    throw new Error(`"${network.toUpperCase()}_RPC_URL" env variable not set`);
  }

  const eventsFilePath = path.join(EVENTS_DIR_PATH, `${network}.json`);

  const fetchedEvents: FetchedEvents = fs.existsSync(eventsFilePath)
    ? JSON.parse(fs.readFileSync(eventsFilePath, "utf-8"))
    : {
        fromBlock: permissionsConfig.getGenesisBlockNumber(),
        toBlock: permissionsConfig.getGenesisBlockNumber(),
        events: [],
      };

  let fromBlock = fetchedEvents.toBlock;
  const currentBlockNumber = 11473216; // await fetchBlockNumber(rpcURL);

  console.log("Network:", network);
  console.log("Current block number:", currentBlockNumber);
  console.log("Last processed block number:", fromBlock);

  if (fromBlock >= currentBlockNumber) {
    console.log("Data is up to date. Exiting...");
    return;
  }

  const acl = permissionsConfig.getAragonACLAddress();
  const ozContractAddresses = Object.entries(permissionsConfig.getOZConfig()).map(([label]) =>
    permissionsConfig.getAddressByLabel(label)
  );
  const eventsCollector = new EventsCollector(rpcURL, acl, ozContractAddresses);

  while (fromBlock < currentBlockNumber) {
    const toBlock = Math.min(fromBlock + BLOCKS_PER_REQUEST, currentBlockNumber);

    console.log(`Fetching events for blocks [${fromBlock}, ${toBlock})...`);

    fetchedEvents.events.push(...(await eventsCollector.collect({ fromBlock, toBlock })));

    fromBlock = toBlock + 1;
    fetchedEvents.toBlock = fromBlock;

    console.log("Saving data...");

    if (!fs.existsSync(EVENTS_DIR_PATH)) {
      fs.mkdirSync(EVENTS_DIR_PATH, { recursive: true });
    }
    fs.writeFileSync(eventsFilePath, JSON.stringify(fetchedEvents, null, 2), "utf-8");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

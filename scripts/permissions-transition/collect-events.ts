import "dotenv/config";
import * as fs from "fs";
import * as path from "path";

import { PermissionsConfig } from "./src/permissions-config";
import { EventsCollector, DecodedEvent } from "./src/events-collector";
import { JsonRpcProvider } from "ethers";

const BLOCKS_PER_REQUEST = 5_000;
const EVENTS_DIR_PATH = path.join(__dirname, "events");

interface FetchedEvents {
  fromBlock: number;
  toBlock: number;
  events: DecodedEvent[];
}

async function main() {
  const network = process.env.NETWORK || "mainnet";
  let rpcURL: string | undefined = undefined;

  const permissionsConfig = PermissionsConfig.load(network);

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

  const provider = new JsonRpcProvider(rpcURL);

  const eventsFilePath = path.join(EVENTS_DIR_PATH, `${network}.json`);

  const doesFetchedEventsFileExists = fs.existsSync(eventsFilePath);

  const fetchedEvents: FetchedEvents = doesFetchedEventsFileExists
    ? JSON.parse(fs.readFileSync(eventsFilePath, "utf-8"))
    : {
        fromBlock: permissionsConfig.getGenesisBlockNumber(),
        toBlock: permissionsConfig.getGenesisBlockNumber(),
        events: [],
      };

  const currentBlockNumber = await provider.getBlockNumber();

  let fromBlock = doesFetchedEventsFileExists ? fetchedEvents.toBlock + 1 : fetchedEvents.fromBlock;

  if (fromBlock > currentBlockNumber) {
    throw new Error(`Invalid events file: "fromBlock" ${fromBlock} > "currentBlockNumber" ${currentBlockNumber}`);
  } else if (fromBlock === currentBlockNumber) {
    console.log("Data is up to date. Exiting...");
    return;
  }

  console.log("Network:", network);
  console.log("Current block number:", currentBlockNumber);

  if (doesFetchedEventsFileExists) {
    console.log("Last processed block number:", fetchedEvents.toBlock);
  } else {
    console.log("Fetching roles starting from genesis block:", fetchedEvents.fromBlock);
  }

  const acl = permissionsConfig.getAragonACLAddress();
  const ozContractAddresses = Object.entries(permissionsConfig.getOZConfig()).map(([label]) =>
    permissionsConfig.getAddressByLabel(label)
  );
  const eventsCollector = new EventsCollector(provider, acl, ozContractAddresses);

  while (fromBlock < currentBlockNumber) {
    const toBlock = Math.min(fromBlock + BLOCKS_PER_REQUEST, currentBlockNumber);

    console.log(`Fetching events for blocks [${fromBlock}, ${toBlock}]...`);

    fetchedEvents.events.push(...(await eventsCollector.collect({ fromBlock, toBlock })));

    fetchedEvents.toBlock = toBlock;
    fromBlock = toBlock + 1;

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

import "dotenv/config";
import * as fs from "fs";
import * as path from "path";

import { PermissionsMarkdownFormatter } from "./src/permissions-markdown-formatter";
import { PermissionsConfig } from "./src/permissions-config";
import { EventsReducer } from "./src/events-reducer";
import { DecodedEvent } from "./src/events-collector";
import { JsonRpcProvider } from "ethers";

const EVENTS_DIR_PATH = path.join(__dirname, "events");
const TRANSITION_PLANS_DIR_PATH = path.join(__dirname, "transition-plans");

interface EventsCache {
  fromBlock: number;
  toBlock: number;
  events: DecodedEvent[];
}

async function main() {
  const network = process.env.NETWORK || "mainnet";
  let rpcURL: string | undefined = undefined;

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
  const eventsFileName = path.join(EVENTS_DIR_PATH, `${network}.json`);

  if (!fs.existsSync(eventsFileName)) {
    throw new Error(
      [
        `Events file ${eventsFileName} for network "${network}" not found`,
        `Use "scripts/permissions-transition/collect-events script to collect onchain events"`,
      ].join("\n")
    );
  }

  const eventFilesContent: EventsCache = JSON.parse(fs.readFileSync(eventsFileName, "utf-8"));

  const rolesReducer = new EventsReducer(eventFilesContent.toBlock);
  for (const event of eventFilesContent.events) {
    rolesReducer.process(event);
  }

  const snapshot = rolesReducer.getSnapshot();

  const mdPermissionsFormatter = new PermissionsMarkdownFormatter(provider, PermissionsConfig.load(network), snapshot);

  console.log(`Preparing transition plan for the network ${network} at block ${snapshot.snapshotBlockNumber}...`);

  const result = await mdPermissionsFormatter.format();

  if (!fs.existsSync(TRANSITION_PLANS_DIR_PATH)) {
    fs.mkdirSync(TRANSITION_PLANS_DIR_PATH, { recursive: true });
  }
  const transitionPlanFilePath = path.join(TRANSITION_PLANS_DIR_PATH, `${network}-${snapshot.snapshotBlockNumber}.md`);
  fs.writeFileSync(transitionPlanFilePath, result, "utf-8");
  console.log(`Transition plan was saved into ${transitionPlanFilePath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

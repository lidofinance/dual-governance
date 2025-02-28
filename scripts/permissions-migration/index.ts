import "dotenv/config";
import { JsonRpcProvider } from "ethers";

import oz from "./src/oz-roles";
import aragon from "./src/aragon-permissions";
import managed from "./src/managed-contracts";
import { retrieveDeployConfiguration } from "./src/aragon-deploy";

import {
  ARAGON_CONTRACT_ROLES_CONFIG,
  MANAGED_CONTRACTS,
  OZ_CONTRACT_ROLES_CONFIG,
} from "./config/agent-transfer-permissions-config";

const RPC_URL = process.env.RPC_URL;

if (!RPC_URL) {
  throw new Error("RPC_URL env variable not set");
}

async function main() {
  const provider = new JsonRpcProvider(RPC_URL);
  console.log(`## Lido Permissions Transitions`);
  console.log(
    aragon.formatContractPermissionsSection(
      await aragon.collectPermissionsData(
        provider,
        ARAGON_CONTRACT_ROLES_CONFIG
      )
    )
  );
  console.log(
    oz.formatContractRolesSection(
      await oz.collectRolesInfo(provider, OZ_CONTRACT_ROLES_CONFIG)
    )
  );
  console.log(
    managed.formatControlledContractsSection(
      await managed.collectManagedContractsInfo(provider, MANAGED_CONTRACTS)
    )
  );
  console.log(await retrieveDeployConfiguration(provider));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

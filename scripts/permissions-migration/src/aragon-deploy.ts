import { ethers, id, JsonRpcProvider, getAddress } from "ethers";

import { MAINNET_PERMISSIONS_CONFIG } from "../config/mainnet";

const txHash = "0x3feabd79e8549ad68d1827c074fa7123815c80206498946293d5373a160fd866";

export async function retrieveDeployConfiguration(provider: JsonRpcProvider) {
  const txReceipt = await provider.getTransactionReceipt(txHash);
  const iface = new ethers.Interface(["event SetApp(bytes32 indexed namespace, bytes32 indexed appId, address app)"]);

  const deployedApps: Set<string> = new Set();

  if (!txReceipt) return;

  for (const log of txReceipt.logs) {
    const mutableLog = { ...log, topics: [...log.topics] };
    if (mutableLog.topics[0] === id("SetApp(bytes32,bytes32,address)")) {
      const decoded = iface.parseLog(mutableLog);

      if (decoded) {
        deployedApps.add(decoded.args[2]);
      }
    }
  }

  for (const lidoContract of Object.entries(MAINNET_PERMISSIONS_CONFIG.labels)) {
    const [name, address] = lidoContract;
    const normalizedAddress = getAddress(address);

    if (deployedApps.has(normalizedAddress)) {
      deployedApps.delete(normalizedAddress);
      deployedApps.add(name);
    }
  }

  const result = ["Deployed apps"];

  for (const app of deployedApps) {
    result.push(app);
  }

  return result.join("\n");
}

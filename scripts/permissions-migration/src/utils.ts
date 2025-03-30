import fetch from "node-fetch";
import { AbiCoder, id } from "ethers";
import bytes, { Address, HexStrPrefixed } from "./bytes";

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
export const ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000";

export async function makeContractCall(
  rpcURL: string,
  address: Address,
  methodName: string,
  argTypes: string[] = [],
  argValues: any[] = []
) {
  const methodId = id(methodName + `(${argTypes.join(",")})`).slice(0, 10);

  return bytes.normalize(
    await fetchEthCall(
      rpcURL,
      address,
      argTypes.length > 0 ? bytes.join(methodId, AbiCoder.defaultAbiCoder().encode(argTypes, argValues)) : methodId
    )
  );
}

export async function fetchBlockNumber(rpcURL: string) {
  const response = await fetch(rpcURL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ id: 1, jsonrpc: "2.0", method: "eth_blockNumber", params: [] }),
  });
  const result = await response.json();
  // @ts-ignore
  return parseInt(result.result, 16);
}

async function fetchEthCall(
  rpcURL: string,
  to: Address,
  data?: string,
  gas?: number,
  gasPrice?: number,
  value?: number
) {
  data = data || "0x";
  const gasHex = "0x" + (gas || 30_000_000).toString(16);
  const gasPriceHex = "0x" + (gasPrice || 0).toString(16);
  const valueHex = "0x" + (value || 0).toString(16);

  const response = await fetch(rpcURL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      id: 1,
      jsonrpc: "2.0",
      method: "eth_call",
      params: [{ to, gas: gasHex, gasPrice: gasPriceHex, value: valueHex, data }],
    }),
  });

  const result = await response.json();
  if (result.error) {
    throw new Error(`JSON RPC ERROR: ${JSON.stringify(result.error)}`);
  }

  return result.result;
}

export function decodeAddress(encodedAddress: string): Address {
  return bytes.slice(encodedAddress, 12, 32);
}

export function decodeBytes32(encodedBytes32: string): HexStrPrefixed {
  return bytes.normalize(encodedBytes32);
}

export function decodeBool(encodedBool: string): boolean {
  const intValue = parseInt(bytes.normalize(encodedBool), 16);
  if (!Number.isInteger(intValue) && intValue > 1) {
    throw new Error(`Invalid encoded bool value "${encodedBool}"`);
  }
  return intValue === 1;
}

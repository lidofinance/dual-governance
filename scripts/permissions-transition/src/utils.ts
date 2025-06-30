import { AbiCoder, id, JsonRpcProvider } from "ethers";
import bytes, { Address, HexStrPrefixed } from "./bytes";

const defaultCoder = AbiCoder.defaultAbiCoder();
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
export const ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000";

interface ContractCallData {
  address: Address;
  methodName: string;
  argTypes?: string[];
  argValues?: string[];
  blockTag?: number | string;
}

export async function makeContractCall(provider: JsonRpcProvider, callData: ContractCallData) {
  const argTypes = callData.argTypes ?? [];
  const argValues = callData.argValues ?? [];
  const blockTag = callData.blockTag;

  const methodId = id(callData.methodName + `(${argTypes.join(",")})`).slice(0, 10);

  return bytes.normalize(
    await provider.call({
      to: callData.address,
      data: argTypes.length > 0 ? bytes.join(methodId, defaultCoder.encode(argTypes, argValues)) : methodId,
      blockTag,
    })
  );
}

export function decodeAddress(encodedAddress: string): Address {
  return bytes.normalize(defaultCoder.decode(["address"], encodedAddress)[0]);
}

export function decodeBytes32(encodedBytes32: string): HexStrPrefixed {
  return bytes.normalize(encodedBytes32);
}

export function decodeBool(encodedBool: string): boolean {
  return defaultCoder.decode(["bool"], encodedBool)[0];
}

import { AbiCoder, id, JsonRpcProvider, Log } from "ethers";
import bytes, { Address, HexStrPrefixed } from "./bytes";

export function startCase(text: string) {
  return (
    text
      // Replace any non-alphanumeric sequences with a space
      .replace(/([A-Z])/g, " $1") // Insert space before uppercase letters
      .replace(/[_-]+/g, " ") // Replace underscores and hyphens with spaces
      .trim() // Remove extra spaces at the start and end
      .split(/\s+/) // Split by one or more spaces
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()) // Capitalize each word
      .join(" ")
  ); // Join words with a single space
}

export async function makeContractCall(
  provider: JsonRpcProvider,
  address: Address,
  methodName: string,
  argTypes: string[] = [],
  argValues: any[] = []
) {
  const methodId = id(methodName + `(${argTypes.join(",")})`).slice(0, 10);
  return bytes.normalize(
    await provider.call({
      to: address,
      data:
        argTypes.length > 0
          ? bytes.join(
              methodId,
              AbiCoder.defaultAbiCoder().encode(argTypes, argValues)
            )
          : methodId,
    })
  );
}

export function sortLogs(logs: Log[]) {
  return logs.sort((a, b) => {
    if (a.blockNumber !== b.blockNumber) {
      return a.blockNumber - b.blockNumber; // Sort by block number
    }
    return a.index - b.index; // Sort by log index
  });
}

export function decodeAddress(encodedAddress: string): Address {
  return bytes.normalize(
    AbiCoder.defaultAbiCoder().decode(["address"], encodedAddress)[0]
  );
}

export function decodeBool(encodedBool: string): boolean {
  return AbiCoder.defaultAbiCoder().decode(["bool"], encodedBool)[0] as boolean;
}

export function decodeBytes32(encodedBytes32: string): HexStrPrefixed {
  return bytes.normalize(
    AbiCoder.defaultAbiCoder().decode(["bytes32"], encodedBytes32)[0]
  );
}

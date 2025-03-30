export type Address = `0x${string}`;
export type HexStrNonPrefixed = string;
export type HexStrPrefixed = `0x${HexStrNonPrefixed}`;
export type HexStr = HexStrPrefixed | HexStrNonPrefixed;

function normalize<T extends HexStr>(bytes: T): HexStrPrefixed {
  return prefix0x(bytes.toLowerCase() as T);
}

function prefix0x<T extends HexStr>(bytes: T): HexStrPrefixed {
  return is0xPrefixed(bytes) ? bytes : (("0x" + bytes) as HexStrPrefixed);
}

function strip0x(bytes: HexStr): HexStrNonPrefixed {
  return bytes.startsWith("0x") ? bytes.slice(2) : bytes;
}

function join(...bytes: HexStr[]): HexStrPrefixed {
  return prefix0x(bytes.reduce((res, b) => res + strip0x(b), ""));
}

function is0xPrefixed(bytes: HexStr): bytes is HexStrPrefixed {
  return bytes.startsWith("0x");
}

function slice(str: HexStr, start: number, end: number) {
  if (end === undefined) {
    end = length(str);
  }
  return normalize(strip0x(str).slice(start * 2, end * 2));
}

function length(str: HexStr) {
  const hexStrLen = strip0x(str).length;

  if (hexStrLen % 2 === 1) {
    throw new Error("Invalid HexStr length");
  }

  return hexStrLen / 2;
}

export default {
  join,
  slice,
  normalize,
  prefix0x,
  strip0x
};

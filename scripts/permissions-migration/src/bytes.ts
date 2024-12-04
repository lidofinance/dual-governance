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

export default {
  join,
  normalize,
};

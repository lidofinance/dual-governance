import bytes, { Address } from "../src/bytes";

export const LIDO_GENESIS_BLOCK = 11473216;

export type LidoContractName =
  | `Unknown(${Address})`
  | "None"
  | "DualGovernance"
  | keyof typeof LIDO_CONTRACTS;

export const LIDO_CONTRACTS = {
  // Core Protocol
  LidoLocator: "0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb",
  Lido: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
  StakingRouter: "0xFdDf38947aFB03C621C71b06C9C70bce73f12999",
  DepositSecurityModule: "0xffa96d84def2ea035c7ab153d8b991128e3d72fd",
  ExecutionLayerRewardsVault: "0x388C818CA8B9251b393131C08a736A67ccB19297",
  WithdrawalQueueERC721: "0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1",
  WithdrawalVault: "0xb9d7934878b5fb9610b3fe8a5e441e8fad7e293f",
  Burner: "0xD15a672319Cf0352560eE76d9e89eAB0889046D3",
  MEVBoostRelayAllowedList: "0xF95f069F9AD107938F6ba802a3da87892298610E",

  // Oracle Contracts
  AccountingOracle: "0x852deD011285fe67063a08005c71a85690503Cee",
  AccountingOracleHashConsensus: "0xD624B08C83bAECF0807Dd2c6880C3154a5F0B288",
  ValidatorExitBusOracle: "0x0De4Ea0184c2ad0BacA7183356Aea5B8d5Bf5c6e",
  ValidatorExitBusHashConsensus: "0x7FaDB6358950c5fAA66Cb5EB8eE5147De3df355a",
  OracleReportSanityChecker: "0x6232397ebac4f5772e53285B26c47914E9461E75",
  OracleDaemonConfig: "0xbf05A929c3D7885a6aeAd833a992dA6E5ac23b09",
  LegacyOracle: "0x442af784A788A5bd6F42A01Ebe9F287a871243fb",

  // DAO Contracts
  DAOKernel: "0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc",
  Voting: "0x2e59A20f205bB85a89C53f1936454680651E618e",
  Agent: "0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c",
  TokenManager: "0xf73a1260d222f447210581DDf212D915c09a3249",
  Finance: "0xB9E5CBB9CA5b0d659238807E84D0176930753d86",
  ACL: "0x9895f0f17cc1d1891b6f18ee0b483b6f221b37bb",
  AragonPM: "0x0cb113890b04b49455dfe06554e2d784598a29c9",
  VotingRepo: "0x4ee3118e3858e8d7164a634825bfe0f73d99c792",
  LidoRepo: "0xF5Dc67E54FC96F993CD06073f71ca732C1E654B1",
  LegacyOracleRepo: "0xF9339DE629973c60c4d2b76749c81E6F40960E3A",
  CuratedModuleRepo: "0x0D97E876ad14DB2b183CFeEB8aa1A5C788eB1831",
  SimpleDVTRepo: "0x2325b0a607808dE42D918DB07F925FFcCfBb2968",
  OraclesGateSeal: "0x79243345edbe01a7e42edff5900156700d22611c",
  EVMScriptRegistry: "0x853cc0D5917f49B57B8e9F89e491F5E18919093A",

  // Staking Modules
  CuratedModule: "0x55032650b14df07b85bF18A3a3eC8E0Af2e028d5",
  SimpleDVT: "0xaE7B191A31f627b4eB1d4DaC64eaB9976995b433",
  CSModule: "0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F",
  CSAccounting: "0x4d72BFF1BeaC69925F8Bd12526a39BAAb069e5Da",
  CSFeeDistributor: "0xD99CC66fEC647E68294C6477B40fC7E0F6F618D0",
  CSGateSeal: "0x5cFCa30450B1e5548F140C24A47E36c10CE306F0",
  CSFeeOracle: "0x4D4074628678Bd302921c20573EEa1ed38DdF7FB",
  CSHashConsensus: "0x71093efF8D8599b5fA340D665Ad60fA7C80688e4",
  CSCommitteeMultisig: "0xc52fc3081123073078698f1eac2f1dc7bd71880f",
  CSVerifier: "0x3dfc50f22aca652a0a6f28a0f892ab62074b5583",

  // Anchor Integration
  AnchorVault: "0xA2F987A546D4CD1c607Ee8141276876C26b72Bdf",
  bETH: "0x707f9118e33a9b8998bea41dd0d46f38bb963fc8",

  // EasyTrack
  EasyTrack: "0xF0211b7660680B49De1A7E9f25C65660F0a13Fea",
  EasyTrackEvmScriptExecutor: "0xFE5986E06210aC1eCC1aDCafc0cc7f8D63B3F977",

  // Easy Track Factories for token transfers
  LOLStETH_AllowedRecipientsRegistry:
    "0x48c4929630099b217136b64089E8543dB0E5163a",
  RewardsShareStETH_AllowedRecipientsRegistry:
    "0xdc7300622948a7AdaF339783F6991F9cdDD79776",
  LegoLDO_AllowedRecipientsRegistry:
    "0x97615f72c3428A393d65A84A3ea6BBD9ad6C0D74",
  LegoStablecoins_AllowedRecipientsRegistry:
    "0xb0FE4D300334461523D9d61AaD90D0494e1Abb43",
  RCCStableCoins_AllowedRecipientsRegistry:
    "0xDc1A0C7849150f466F07d48b38eAA6cE99079f80",
  RCCStETH_AllowedRecipientsRegistry:
    "0xAAC4FcE2c5d55D1152512fe5FAA94DB267EE4863",
  PMLStablecoins_AllowedRecipientsRegistry:
    "0xDFfCD3BF14796a62a804c1B16F877Cf7120379dB",
  PMLStETH_AllowedRecipientsRegistry:
    "0x7b9B8d00f807663d46Fb07F87d61B79884BC335B",
  ATCStablecoins_AllowedRecipientsRegistry:
    "0xe07305F43B11F230EaA951002F6a55a16419B707",
  ATCStETH_AllowedRecipientsRegistry:
    "0xd3950eB3d7A9B0aBf8515922c0d35D13e85a2c91",
  TRPLDO_AllowedRecipientsRegistry:
    "0x231Ac69A1A37649C6B06a71Ab32DdD92158C80b8",
  GasSupplyStETH_AllowedRecipientsRegistry:
    "0x49d1363016aA899bba09ae972a1BF200dDf8C55F",
  AllianceOpsStablecoins_AllowedRecipientsRegistry:
    "0x3B525F4c059F246Ca4aa995D21087204F30c9E2F",
  StonksStETH_AllowedRecipientsRegistry:
    "0x1a7cFA9EFB4D5BfFDE87B0FaEb1fC65d653868C0",
  StonksStablecoins_AllowedRecipientsRegistry:
    "0x3f0534CCcFb952470775C516DC2eff8396B8A368",
  AllowedTokensRegistry: "0x4AC40c34f8992bb1e5E856A448792158022551ca",

  // Arbitrum
  L1ERC20TokenGateway_Arbitrum: "0x0F25c1DC2a9922304f2eac71DCa9B07E310e8E5a",

  // Optimism
  TokenRateNotifier_Optimism: "0xe6793B9e4FbA7DE0ee833F9D02bba7DB5EB27823",
  L1TokensBridge_Optimism: "0x76943C0D61395d8F2edF9060e1533529cAe05dE6",

  // Polygon
  ERC20Predicate_Polygon: "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",

  // Base
  L1ERC20TokenBridge_Base: "0x9de443AdC5A411E83F1878Ef24C3F52C61571e72",

  // zkSync
  L1Executor_zkSync: "0xFf7F4d05e3247374e86A3f7231A2Ed1CA63647F2",
  L1ERC20Bridge_zkSync: "0x41527B2d03844dB6b0945f25702cB958b6d55989",

  // Mantle
  L1ERC20TokenBridge_Mantle: "0x2D001d79E5aF5F65a939781FE228B267a8Ed468B",

  // Linea
  L1TokenBridge_Linea: "0x051f1d88f0af5763fb888ec4378b4d8b29ea3319",

  // Scroll
  L1LidoGateway_Scroll: "0x6625c6332c9f91f2d27c304e729b86db87a3f504",

  // Mode
  L1ERC20TokenBridge_Mode: "0xD0DeA0a3bd8E4D55170943129c025d3fe0493F2A",

  //Zircuit
  L1ERC20TokenBridge_Zircuit: "0x912C7271a6A3622dfb8B218eb46a6122aB046C79",

  // Emergency Brakes
  EmergencyBrakesMultisig: "0x73b047fe6337183A454c5217241D780a932777bD",
} as const;

export const LIDO_CONTRACTS_NAMES: Record<Address, LidoContractName> = {};

for (const [name, address] of Object.entries(LIDO_CONTRACTS)) {
  LIDO_CONTRACTS_NAMES[bytes.normalize(address)] = name as LidoContractName;
}

export const CONTRACT_LABELS: Partial<Record<LidoContractName, string>> = {
  EasyTrackEvmScriptExecutor: "ET :: EVMScriptExecutor",
};

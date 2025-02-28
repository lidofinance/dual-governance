import bytes, { Address } from "../src/bytes";

export const LIDO_GENESIS_BLOCK = 30591;

export type LidoContractName =
  | `Unknown(${Address})`
  | "None"
  | "DualGovernance"
  | keyof typeof LIDO_CONTRACTS;

export const LIDO_CONTRACTS = {
  // Core Protocol
  LidoLocator: "0x28FAB2059C713A7F9D8c86Db49f9bb0e96Af1ef8",
  Lido: "0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034",
  StakingRouter: "0xd6EbF043D30A7fe46D1Db32BA90a0A51207FE229",
  DepositSecurityModule: "0x808DE3b26Be9438F12E9B45528955EA94C17f217",
  ExecutionLayerRewardsVault: "0xE73a3602b99f1f913e72F8bdcBC235e206794Ac8",
  WithdrawalQueueERC721: "0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50",
  WithdrawalVault: "0xF0179dEC45a37423EAD4FaD5fCb136197872EAd9",
  Burner: "0x4E46BD7147ccf666E1d73A3A456fC7a68de82eCA",
  MEVBoostRelayAllowedList: "0x2d86C5855581194a386941806E38cA119E50aEA3",

  // Oracle Contracts
  AccountingOracle: "0x4E97A3972ce8511D87F334dA17a2C332542a5246",
  AccountingOracleHashConsensus: "0xa067FC95c22D51c3bC35fd4BE37414Ee8cc890d2",
  ValidatorExitBusOracle: "0xffDDF7025410412deaa05E3E1cE68FE53208afcb",
  ValidatorExitBusHashConsensus: "0xe77Cf1A027d7C10Ee6bb7Ede5E922a181FF40E8f",
  OracleReportSanityChecker: "0x80D1B1fF6E84134404abA18A628347960c38ccA7",
  OracleDaemonConfig: "0xC01fC1F2787687Bc656EAc0356ba9Db6e6b7afb7",
  LegacyOracle: "0x072f72BE3AcFE2c52715829F2CD9061A6C8fF019",

  // DAO Contracts
  DAOKernel: "0x3b03f75Ec541Ca11a223bB58621A3146246E1644",
  Voting: "0xdA7d2573Df555002503F29aA4003e398d28cc00f",
  Agent: "0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d",
  TokenManager: "0xFaa1692c6eea8eeF534e7819749aD93a1420379A",
  Finance: "0xf0F281E5d7FBc54EAFcE0dA225CDbde04173AB16",
  ACL: "0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC",
  AragonPM: "0x4605Dc9dC4BD0442F850eB8226B94Dd0e27C3Ce7",
  VotingRepo: "0x2997EA0D07D79038D83Cb04b3BB9A2Bc512E3fDA",
  LidoRepo: "0xA37fb4C41e7D30af5172618a863BBB0f9042c604",
  LegacyOracleRepo: "0xB3d74c319C0C792522705fFD3097f873eEc71764",
  CuratedModuleRepo: "0x4E8970d148CB38460bE9b6ddaab20aE2A74879AF",
  SimpleDVTRepo: "0x889dB59baf032E1dfD4fCA720e0833c24f1404C6",
  OraclesGateSeal: "0xAE6eCd77DCC656c5533c4209454Fd56fB46e1778",
  EVMScriptRegistry: "0xE1200ae048163B67D69Bc0492bF5FddC3a2899C0",

  // Staking Modules
  CuratedModule: "0x595F64Ddc3856a3b5Ff4f4CC1d1fb4B46cFd2bAC",
  SimpleDVT: "0x11a93807078f8BB880c1BD0ee4C387537de4b4b6",
  CSModule: "0x4562c3e63c2e586cD1651B958C22F88135aCAd4f",
  CSAccounting: "0xc093e53e8F4b55A223c18A2Da6fA00e60DD5EFE1",
  CSFeeDistributor: "0xD7ba648C8F72669C6aE649648B516ec03D07c8ED",
  CSGateSeal: "0xf1C03536dbC77B1bD493a2D1C0b1831Ea78B540a",
  CSFeeOracle: "0xaF57326C7d513085051b50912D51809ECC5d98Ee",
  CSHashConsensus: "0xbF38618Ea09B503c1dED867156A0ea276Ca1AE37",
  CSCommitteeMultisig: "0x6165267E76D609465640bffc158aff7905D47B46",
  CSVerifier: "0xc099dfd61f6e5420e0ca7e84d820daad17fc1d44",

  // EasyTrack
  EasyTrack: "0x1763b9ED3586B08AE796c7787811a2E1bc16163a",
  EasyTrackEvmScriptExecutor: "0x2819B65021E13CEEB9AC33E77DB32c7e64e7520D",

  // Easy Track Factories for token transfers
  AllowedTokensRegistry: "0x091c0ec8b4d54a9fcb36269b5d5e5af43309e666",

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

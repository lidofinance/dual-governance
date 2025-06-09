import { PermissionsConfigData } from "../src/permissions-config";

export const HOLESKY_PERMISSIONS_CONFIG: PermissionsConfigData = {
  genesisBlock: 1,
  explorerURL: "https://holesky.etherscan.io",
  labels: {
    DGAdminExecutor: "0x8BD0a916faDa88Ba3accb595a3Acd28F467130e8",
    ResealManager: "0x9dE2273f9f1e81145171CcA927EFeE7aCC64c9fb",
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
    ValidatorsExitBusOracle: "0xffDDF7025410412deaa05E3E1cE68FE53208afcb",
    ValidatorsExitBusHashConsensus: "0xe77Cf1A027d7C10Ee6bb7Ede5E922a181FF40E8f",
    OracleReportSanityChecker: "0x80D1B1fF6E84134404abA18A628347960c38ccA7",
    OracleDaemonConfig: "0xC01fC1F2787687Bc656EAc0356ba9Db6e6b7afb7",
    LegacyOracle: "0x072f72BE3AcFE2c52715829F2CD9061A6C8fF019",

    // DAO Contracts
    ACL: "0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC",
    DAOKernel: "0x3b03f75Ec541Ca11a223bB58621A3146246E1644",
    Voting: "0xdA7d2573Df555002503F29aA4003e398d28cc00f",
    Agent: "0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d",
    TokenManager: "0xFaa1692c6eea8eeF534e7819749aD93a1420379A",
    Finance: "0xf0F281E5d7FBc54EAFcE0dA225CDbde04173AB16",
    AragonPM: "0xB576A85c310CC7Af5C106ab26d2942fA3a5ea94A",
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
    CSCommitteeMultisig: "0xc4DAB3a3ef68C6DFd8614a870D64D475bA44F164",
    CSVerifier: "0xc099dfd61f6e5420e0ca7e84d820daad17fc1d44",
    SandboxStakingModule: "0xD6C2ce3BB8bea2832496Ac8b5144819719f343AC",

    // EasyTrack
    EasyTrack: "0x1763b9ED3586B08AE796c7787811a2E1bc16163a",
    EvmScriptExecutor: "0x2819B65021E13CEEB9AC33E77DB32c7e64e7520D",

    // Easy Track Factories for token transfers
    AllowedTokensRegistry: "0x091c0ec8b4d54a9fcb36269b5d5e5af43309e666",

    // DEV Addresses
    DevEOA1: "0xDA6bEE5441f2e6b364F3b25E85d5f3C29Bfb669E",
    DevEOA2: "0x66b25cfe6b9f0e61bd80c4847225baf4ee6ba0a2",
    DevEOA3: "0x2A329E1973217eB3828EB0F2225d1b1C10DB72B0",
    DevEOA4: "0x13de2ff641806da869ad6e438ef0fa0101eefdd6",
    DevAgentManager: "0xc807d4036B400dE8f6cD2aDbd8d9cf9a3a01CC30",
    UnlimitedStake: "0xCfAC1357B16218A90639cd17F90226B385A71084",
  },
  aragon: {
    // Core protocol
    Lido: {
      STAKING_CONTROL_ROLE: { manager: "Agent", grantedTo: ["DevEOA1", "UnlimitedStake"] },
      RESUME_ROLE: { manager: "Agent" },
      PAUSE_ROLE: { manager: "Agent" },
      UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE: { manager: "Agent" },
      STAKING_PAUSE_ROLE: { manager: "Agent" },
    },

    // DAO Contracts
    DAOKernel: {
      APP_MANAGER_ROLE: { manager: "Agent" },
    },
    Voting: {
      UNSAFELY_MODIFY_VOTE_TIME_ROLE: { manager: "Voting" },
      MODIFY_QUORUM_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      MODIFY_SUPPORT_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      CREATE_VOTES_ROLE: { manager: "Voting", grantedTo: ["TokenManager"] },
    },
    TokenManager: {
      MINT_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      REVOKE_VESTINGS_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      BURN_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      ISSUE_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      ASSIGN_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
    },
    Finance: {
      CREATE_PAYMENTS_ROLE: {
        manager: "Voting",
        grantedTo: ["Voting", "EvmScriptExecutor"],
      },
      CHANGE_PERIOD_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      CHANGE_BUDGETS_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      EXECUTE_PAYMENTS_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      MANAGE_PAYMENTS_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
    },
    AragonPM: {
      CREATE_REPO_ROLE: { manager: "None" },
    },
    EVMScriptRegistry: {
      REGISTRY_MANAGER_ROLE: { manager: "Agent" },
      REGISTRY_ADD_EXECUTOR_ROLE: { manager: "Agent" },
    },
    VotingRepo: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
    LidoRepo: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
    LegacyOracleRepo: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
    CuratedModuleRepo: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
    SimpleDVTRepo: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
    // Staking Modules
    CuratedModule: {
      STAKING_ROUTER_ROLE: { manager: "Agent", grantedTo: ["StakingRouter", "DevEOA1", "DevEOA2"] },
      MANAGE_NODE_OPERATOR_ROLE: { manager: "Agent", grantedTo: ["DevEOA1", "DevEOA2"] },
      SET_NODE_OPERATOR_LIMIT_ROLE: {
        manager: "Agent",
        grantedTo: ["EvmScriptExecutor", "DevEOA1", "DevEOA2"],
      },
      MANAGE_SIGNING_KEYS: { manager: "Agent" },
    },
    SimpleDVT: {
      STAKING_ROUTER_ROLE: { manager: "Agent", grantedTo: ["StakingRouter", "EvmScriptExecutor", "DevEOA3"] },
      MANAGE_NODE_OPERATOR_ROLE: { manager: "Agent", grantedTo: ["EvmScriptExecutor", "DevEOA3"] },
      SET_NODE_OPERATOR_LIMIT_ROLE: { manager: "Agent", grantedTo: ["EvmScriptExecutor", "DevEOA3"] },
      MANAGE_SIGNING_KEYS: { manager: "EvmScriptExecutor", grantedTo: ["Voting", "EvmScriptExecutor", "DevEOA3"] },
    },
    ACL: {
      CREATE_PERMISSIONS_ROLE: { manager: "Agent", grantedTo: ["Agent"] },
    },
    Agent: {
      TRANSFER_ROLE: { manager: "Voting", grantedTo: ["Finance"] },
      RUN_SCRIPT_ROLE: { manager: "Agent", grantedTo: ["DGAdminExecutor", "DevAgentManager"] },
      EXECUTE_ROLE: { manager: "Agent", grantedTo: ["DGAdminExecutor"] },
      SAFE_EXECUTE_ROLE: { manager: "None" },
      DESIGNATE_SIGNER_ROLE: { manager: "None" },
      ADD_PRESIGNED_HASH_ROLE: { manager: "None" },
      ADD_PROTECTED_TOKEN_ROLE: { manager: "None" },
      REMOVE_PROTECTED_TOKEN_ROLE: { manager: "None" },
    },
  },
  oz: {
    // Core Protocol
    StakingRouter: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MANAGE_WITHDRAWAL_CREDENTIALS_ROLE: [],
      REPORT_EXITED_VALIDATORS_ROLE: ["AccountingOracle"],
      REPORT_REWARDS_MINTED_ROLE: ["Lido"],
      STAKING_MODULE_MANAGE_ROLE: ["Agent", "DevEOA1"],
      STAKING_MODULE_UNVETTING_ROLE: ["DepositSecurityModule"],
      UNSAFE_SET_EXITED_VALIDATORS_ROLE: [],
    },
    WithdrawalQueueERC721: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      FINALIZE_ROLE: ["Lido"],
      MANAGE_TOKEN_URI_ROLE: [],
      ORACLE_ROLE: ["AccountingOracle"],
      PAUSE_ROLE: ["OraclesGateSeal", "ResealManager"],
      RESUME_ROLE: ["Agent", "ResealManager"],
    },
    Burner: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      REQUEST_BURN_MY_STETH_ROLE: [],
      REQUEST_BURN_SHARES_ROLE: ["Lido", "CuratedModule", "SimpleDVT", "CSAccounting", "SandboxStakingModule"],
    },

    // Oracle Contracts
    AccountingOracle: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      SUBMIT_DATA_ROLE: [],
    },
    AccountingOracleHashConsensus: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: [],
      MANAGE_FRAME_CONFIG_ROLE: ["DevEOA1"],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["DevEOA1"],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
    ValidatorsExitBusOracle: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      PAUSE_ROLE: ["OraclesGateSeal", "ResealManager"],
      RESUME_ROLE: ["Agent", "ResealManager"],
      SUBMIT_DATA_ROLE: [],
    },
    ValidatorsExitBusHashConsensus: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: [],
      MANAGE_FRAME_CONFIG_ROLE: ["DevEOA1"],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["DevEOA1"],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
    OracleReportSanityChecker: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      ALL_LIMITS_MANAGER_ROLE: ["DevEOA1"],
      ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE: [],
      APPEARED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE: [],
      EXITED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE: ["DevEOA4"],
      INITIAL_SLASHING_AND_PENALTIES_MANAGER_ROLE: [],
      MAX_ITEMS_PER_EXTRA_DATA_TRANSACTION_ROLE: [],
      MAX_NODE_OPERATORS_PER_EXTRA_DATA_ITEM_ROLE: [],
      MAX_POSITIVE_TOKEN_REBASE_MANAGER_ROLE: [],
      MAX_VALIDATOR_EXIT_REQUESTS_PER_REPORT_ROLE: [],
      REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE: [],
      SECOND_OPINION_MANAGER_ROLE: [],
      SHARE_RATE_DEVIATION_LIMIT_MANAGER_ROLE: [],
    },
    OracleDaemonConfig: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      CONFIG_MANAGER_ROLE: ["DevEOA1"],
    },
    // Staking Modules
    CSModule: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSCommitteeMultisig"],
      MODULE_MANAGER_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal"],
      RECOVERER_ROLE: [],
      REPORT_EL_REWARDS_STEALING_PENALTY_ROLE: ["CSCommitteeMultisig"],
      RESUME_ROLE: [],
      SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE: ["EvmScriptExecutor"],
      STAKING_ROUTER_ROLE: ["StakingRouter"],
      VERIFIER_ROLE: ["CSVerifier"],
    },
    CSAccounting: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSCommitteeMultisig"],
      ACCOUNTING_MANAGER_ROLE: [],
      MANAGE_BOND_CURVES_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal"],
      RECOVERER_ROLE: [],
      RESET_BOND_CURVE_ROLE: ["CSModule", "CSCommitteeMultisig"],
      RESUME_ROLE: [],
      SET_BOND_CURVE_ROLE: ["CSModule", "CSCommitteeMultisig"],
    },
    CSFeeDistributor: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSCommitteeMultisig"],
      RECOVERER_ROLE: [],
    },
    CSFeeOracle: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSCommitteeMultisig"],
      CONTRACT_MANAGER_ROLE: [],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal"],
      RECOVERER_ROLE: [],
      RESUME_ROLE: [],
      SUBMIT_DATA_ROLE: [],
    },
    CSHashConsensus: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSCommitteeMultisig"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: [],
      MANAGE_FRAME_CONFIG_ROLE: [],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["Agent"],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
    // Easy Track
    EasyTrack: {
      DEFAULT_ADMIN_ROLE: ["Voting"],
      CANCEL_ROLE: [],
      PAUSE_ROLE: [],
      UNPAUSE_ROLE: [],
    },
    AllowedTokensRegistry: {
      DEFAULT_ADMIN_ROLE: ["Voting"],
      ADD_TOKEN_TO_ALLOWED_LIST_ROLE: ["Voting"],
      REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE: ["Voting"],
    },
  },
  getters: {
    DepositSecurityModule: { getOwner: "Agent" },
    LidoLocator: { proxy__getAdmin: "Agent" },
    StakingRouter: { proxy__getAdmin: "Agent" },
    WithdrawalQueueERC721: { proxy__getAdmin: "Agent" },
    WithdrawalVault: { proxy_getAdmin: "Agent" },
    AccountingOracle: { proxy__getAdmin: "Agent" },
    ValidatorsExitBusOracle: { proxy__getAdmin: "Agent" },
  },
};

import { PermissionsConfigData } from "../src/permissions-config";

export const HOODI_PERMISSIONS_CONFIG: PermissionsConfigData = {
  genesisBlock: 1,
  explorerURL: "https://hoodi.etherscan.io",
  labels: {
    DGAdminExecutor: "0x0eCc17597D292271836691358B22340b78F3035B",
    ResealManager: "0x05172CbCDb7307228F781436b327679e4DAE166B",
    // Core Protocol
    LidoLocator: "0xe2EF9536DAAAEBFf5b1c130957AB3E80056b06D8",
    Lido: "0x3508A952176b3c15387C97BE809eaffB1982176a",
    StakingRouter: "0xCc820558B39ee15C7C45B59390B503b83fb499A8",
    DepositSecurityModule: "0x2F0303F20E0795E6CCd17BD5efE791A586f28E03",
    ExecutionLayerRewardsVault: "0x9b108015fe433F173696Af3Aa0CF7CDb3E104258",
    WithdrawalQueueERC721: "0xfe56573178f1bcdf53F01A6E9977670dcBBD9186",
    WithdrawalVault: "0x4473dCDDbf77679A643BdB654dbd86D67F8d32f2",
    Burner: "0x4e9A9ea2F154bA34BE919CD16a4A953DCd888165",
    MEVBoostRelayAllowedList: "0x279d3A456212a1294DaEd0faEE98675a52E8A4Bf",

    // Oracle Contracts
    AccountingOracle: "0xcb883B1bD0a41512b42D2dB267F2A2cd919FB216",
    AccountingOracleHashConsensus: "0x32EC59a78abaca3f91527aeB2008925D5AaC1eFC",
    ValidatorsExitBusOracle: "0x8664d394C2B3278F26A1B44B967aEf99707eeAB2",
    ValidatorsExitBusHashConsensus: "0x30308CD8844fb2DB3ec4D056F1d475a802DCA07c",
    OracleReportSanityChecker: "0x26AED10459e1096d242ABf251Ff55f8DEaf52348",
    OracleDaemonConfig: "0x2a833402e3F46fFC1ecAb3598c599147a78731a9",
    LegacyOracle: "0x5B70b650B7E14136eb141b5Bf46a52f962885752",

    // DAO Contracts
    ACL: "0x78780e70Eae33e2935814a327f7dB6c01136cc62",
    DAOKernel: "0xA48DF029Fd2e5FCECB3886c5c2F60e3625A1E87d",
    Voting: "0x49B3512c44891bef83F8967d075121Bd1b07a01B",
    Agent: "0x0534aA41907c9631fae990960bCC72d75fA7cfeD",
    TokenManager: "0x8ab4a56721Ad8e68c6Ad86F9D9929782A78E39E5",
    Finance: "0x254Ae22bEEba64127F0e59fe8593082F3cd13f6b",
    AragonPM: "0x948ffB5fDA2961C60ED3Eb84c7a31aae42EbEdCC",
    VotingRepo: "0xc972Cdea5956482Ef35BF5852601dD458353cEbD",
    LidoRepo: "0xd3545AC0286A94970BacC41D3AF676b89606204F",
    LegacyOracleRepo: "0x5B70b650B7E14136eb141b5Bf46a52f962885752",
    CuratedModuleRepo: "0x5cDbE1590c083b5A2A64427fAA63A7cfDB91FbB5",
    SimpleDVTRepo: "0x0B5236BECA68004DB89434462DfC3BB074d2c830",
    OraclesGateSeal: "0x2168Ea6D948Ab49c3D34c667A7e02F92369F3A9C",
    EVMScriptRegistry: "0xe4D32427b1F9b12ab89B142eD3714dCAABB3f38c",

    // Staking Modules
    CuratedModule: "0x5cDbE1590c083b5A2A64427fAA63A7cfDB91FbB5",
    SimpleDVT: "0x0B5236BECA68004DB89434462DfC3BB074d2c830",
    CSModule: "0x79CEf36D84743222f37765204Bec41E92a93E59d",
    CSAccounting: "0xA54b90BA34C5f326BC1485054080994e38FB4C60",
    CSFeeDistributor: "0xaCd9820b0A2229a82dc1A0770307ce5522FF3582",
    CSGateSeal: "0xEe1f7f0ebB5900F348f2CfbcC641FB1681359B8a",
    CSFeeOracle: "0xe7314f561B2e72f9543F1004e741bab6Fc51028B",
    CSHashConsensus: "0x54f74a10e4397dDeF85C4854d9dfcA129D72C637",
    CSVerifier: "0xB6bafBD970a4537077dE59cebE33081d794513d6",
    SandboxStakingModule: "0x682E94d2630846a503BDeE8b6810DF71C9806891",

    // EasyTrack
    EasyTrack: "0x284D91a7D47850d21A6DEaaC6E538AC7E5E6fc2a",
    EvmScriptExecutor: "0x79a20FD0FA36453B2F45eAbab19bfef43575Ba9E",

    // Easy Track Factories for token transfers
    AllowedTokensRegistry: "0x40Db7E8047C487bD8359289272c717eA3C34D1D3",

    // DEV Addresses
    CSMDevEOA: "0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53",
    DevEOA1: "0xE28f573b732632fdE03BD5507A7d475383e8512E",
    DevEOA2: "0xF865A1d43D36c713B4DA085f32b7d1e9739B9275",
    DevEOA3: "0x4022E0754d0cB6905B54306105D3346d1547988b",
    EasyTrackManagerEOA: "0xBE2fD5a6Ce6460EB5e9aCC5d486697aE6402fdd2",
    DevAgentManager: "0xD500a8aDB182F55741E267730dfbfb4F1944C205",
    UnlimitedStake: "0x064A4D64040bFD52D0d1dC7f42eA799cb0a8AC40",
  },
  aragon: {
    // Core protocol
    Lido: {
      STAKING_CONTROL_ROLE: { manager: "Agent", grantedTo: ["UnlimitedStake"] },
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
      UNSAFELY_MODIFY_VOTE_TIME_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
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
      MANAGE_NODE_OPERATOR_ROLE: { manager: "Agent", grantedTo: ["Agent", "DevEOA1", "DevEOA2"] },
      SET_NODE_OPERATOR_LIMIT_ROLE: { manager: "Agent", grantedTo: ["EvmScriptExecutor", "DevEOA1", "DevEOA2"] },
      MANAGE_SIGNING_KEYS: { manager: "Agent", grantedTo: ["DevEOA1", "DevEOA2"] },
    },
    SimpleDVT: {
      STAKING_ROUTER_ROLE: {
        manager: "Agent",
        grantedTo: ["Agent", "StakingRouter", "EvmScriptExecutor", "DevEOA1", "DevEOA2"],
      },
      MANAGE_NODE_OPERATOR_ROLE: { manager: "Agent", grantedTo: ["EvmScriptExecutor", "DevEOA1", "DevEOA2"] },
      SET_NODE_OPERATOR_LIMIT_ROLE: { manager: "Agent", grantedTo: ["EvmScriptExecutor", "DevEOA1", "DevEOA2"] },
      MANAGE_SIGNING_KEYS: { manager: "EvmScriptExecutor", grantedTo: ["Voting", "DevEOA1", "DevEOA2"] },
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
      MANAGE_FAST_LANE_CONFIG_ROLE: ["DevEOA1", "DevEOA3"],
      MANAGE_FRAME_CONFIG_ROLE: ["DevEOA1", "DevEOA3"],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["Agent", "DevEOA1", "DevEOA3"],
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
      MANAGE_FAST_LANE_CONFIG_ROLE: ["DevEOA1", "DevEOA3"],
      MANAGE_FRAME_CONFIG_ROLE: ["DevEOA1", "DevEOA3"],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["Agent", "DevEOA1", "DevEOA3"],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
    OracleReportSanityChecker: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      ALL_LIMITS_MANAGER_ROLE: ["DevEOA1"],
      ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE: [],
      APPEARED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE: [],
      EXITED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE: [],
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
      DEFAULT_ADMIN_ROLE: ["Agent", "CSMDevEOA"],
      MODULE_MANAGER_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal"],
      RECOVERER_ROLE: [],
      REPORT_EL_REWARDS_STEALING_PENALTY_ROLE: ["CSMDevEOA"],
      RESUME_ROLE: [],
      SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE: ["EvmScriptExecutor"],
      STAKING_ROUTER_ROLE: ["StakingRouter"],
      VERIFIER_ROLE: ["CSVerifier"],
    },
    CSAccounting: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSMDevEOA"],
      ACCOUNTING_MANAGER_ROLE: [],
      MANAGE_BOND_CURVES_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal"],
      RECOVERER_ROLE: [],
      RESET_BOND_CURVE_ROLE: ["CSModule", "CSMDevEOA"],
      RESUME_ROLE: [],
      SET_BOND_CURVE_ROLE: ["CSModule", "CSMDevEOA"],
    },
    CSFeeDistributor: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSMDevEOA"],
      RECOVERER_ROLE: [],
    },
    CSFeeOracle: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSMDevEOA"],
      CONTRACT_MANAGER_ROLE: [],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal"],
      RECOVERER_ROLE: [],
      RESUME_ROLE: [],
      SUBMIT_DATA_ROLE: [],
    },
    CSHashConsensus: {
      DEFAULT_ADMIN_ROLE: ["Agent", "CSMDevEOA"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: ["DevEOA1", "DevEOA3"],
      MANAGE_FRAME_CONFIG_ROLE: ["DevEOA1", "DevEOA3"],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["Agent", "DevEOA1", "DevEOA3"],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
    // Easy Track
    EasyTrack: {
      DEFAULT_ADMIN_ROLE: ["Voting"],
      CANCEL_ROLE: ["Voting", "EasyTrackManagerEOA"],
      PAUSE_ROLE: ["Voting", "EasyTrackManagerEOA"],
      UNPAUSE_ROLE: ["Voting", "EasyTrackManagerEOA"],
    },
    AllowedTokensRegistry: {
      DEFAULT_ADMIN_ROLE: ["Voting"],
      ADD_TOKEN_TO_ALLOWED_LIST_ROLE: [],
      REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE: [],
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

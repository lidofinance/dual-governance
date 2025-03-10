import { AragonContractPermissionConfigs } from "../src/aragon-permissions";
import { ManagedContractsConfig } from "../src/managed-contracts";
import { OZContractRolesConfig } from "../src/oz-roles";
import { LIDO_CONTRACTS } from "./lido-contracts";

// TODO: Check the completeness of the configs

export const ARAGON_CONTRACT_ROLES_CONFIG: AragonContractPermissionConfigs = {
  // Core protocol
  Lido: {
    address: LIDO_CONTRACTS.Lido,
    permissions: {
      STAKING_CONTROL_ROLE: { manager: "Agent" },
      RESUME_ROLE: { manager: "Agent" },
      PAUSE_ROLE: { manager: "Agent" },
      UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE: { manager: "None" },
      STAKING_PAUSE_ROLE: { manager: "Agent" },
    },
  },

  // DAO Contracts
  DAOKernel: {
    address: LIDO_CONTRACTS.DAOKernel,
    permissions: {
      APP_MANAGER_ROLE: { manager: "Agent" },
    },
  },
  Voting: {
    address: LIDO_CONTRACTS.Voting,
    permissions: {
      UNSAFELY_MODIFY_VOTE_TIME_ROLE: { manager: "Voting" },
      MODIFY_QUORUM_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      MODIFY_SUPPORT_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      CREATE_VOTES_ROLE: { manager: "Voting", grantedTo: ["TokenManager"] },
    },
  },
  TokenManager: {
    address: LIDO_CONTRACTS.TokenManager,
    permissions: {
      ISSUE_ROLE: { manager: "Voting" },
      ASSIGN_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      BURN_ROLE: { manager: "Voting" },
      MINT_ROLE: { manager: "Voting" },
      REVOKE_VESTINGS_ROLE: { manager: "Voting" },
    },
  },
  Finance: {
    address: LIDO_CONTRACTS.Finance,
    permissions: {
      CREATE_PAYMENTS_ROLE: {
        manager: "Voting",
        grantedTo: ["Voting", "EasyTrackEvmScriptExecutor"],
      },
      CHANGE_PERIOD_ROLE: { manager: "Voting" },
      CHANGE_BUDGETS_ROLE: { manager: "Voting" },
      EXECUTE_PAYMENTS_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      MANAGE_PAYMENTS_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
    },
  },
  Agent: {
    address: LIDO_CONTRACTS.Agent,
    permissions: {
      TRANSFER_ROLE: { manager: "Voting", grantedTo: ["Finance"] },
      RUN_SCRIPT_ROLE: {
        manager: "Agent",
        grantedTo: ["DualGovernance"],
      },
      EXECUTE_ROLE: {
        manager: "Agent",
        grantedTo: ["DualGovernance"],
      },
      SAFE_EXECUTE_ROLE: { manager: "None" },
      DESIGNATE_SIGNER_ROLE: { manager: "None" },
      ADD_PRESIGNED_HASH_ROLE: { manager: "None" },
      ADD_PROTECTED_TOKEN_ROLE: { manager: "None" },
      REMOVE_PROTECTED_TOKEN_ROLE: { manager: "None" },
    },
  },
  ACL: {
    address: LIDO_CONTRACTS.ACL,
    permissions: {
      CREATE_PERMISSIONS_ROLE: { manager: "Agent", grantedTo: ["Agent"] },
    },
  },
  AragonPM: {
    address: LIDO_CONTRACTS.AragonPM,
    permissions: {
      CREATE_REPO_ROLE: { manager: "None" },
    },
  },
  EVMScriptRegistry: {
    address: LIDO_CONTRACTS.EVMScriptRegistry,
    permissions: {
      REGISTRY_ADD_EXECUTOR_ROLE: { manager: "Agent" },
      REGISTRY_MANAGER_ROLE: { manager: "Agent" },
    },
  },
  VotingRepo: {
    address: LIDO_CONTRACTS.VotingRepo,
    permissions: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
  },
  LidoRepo: {
    address: LIDO_CONTRACTS.LidoRepo,
    permissions: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
  },
  LegacyOracleRepo: {
    address: LIDO_CONTRACTS.LegacyOracleRepo,
    permissions: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
  },
  CuratedModuleRepo: {
    address: LIDO_CONTRACTS.CuratedModuleRepo,
    permissions: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
  },
  SimpleDVTRepo: {
    address: LIDO_CONTRACTS.SimpleDVTRepo,
    permissions: {
      CREATE_VERSION_ROLE: { manager: "None" },
    },
  },
  // Staking Modules
  CuratedModule: {
    address: LIDO_CONTRACTS.CuratedModule,
    permissions: {
      STAKING_ROUTER_ROLE: { manager: "Agent", grantedTo: ["StakingRouter"] },
      MANAGE_NODE_OPERATOR_ROLE: { manager: "Agent" },
      SET_NODE_OPERATOR_LIMIT_ROLE: {
        manager: "Agent",
        grantedTo: ["EasyTrackEvmScriptExecutor"],
      },
      MANAGE_SIGNING_KEYS: {
        manager: "Agent",
      },
    },
  },
  SimpleDVT: {
    address: LIDO_CONTRACTS.SimpleDVT,
    permissions: {
      STAKING_ROUTER_ROLE: {
        manager: "Agent",
        grantedTo: ["StakingRouter", "EasyTrackEvmScriptExecutor"],
      },
      MANAGE_NODE_OPERATOR_ROLE: {
        manager: "Agent",
        grantedTo: ["EasyTrackEvmScriptExecutor"],
      },
      SET_NODE_OPERATOR_LIMIT_ROLE: {
        manager: "Agent",
        grantedTo: ["EasyTrackEvmScriptExecutor"],
      },
      MANAGE_SIGNING_KEYS: {
        manager: "EasyTrackEvmScriptExecutor",
        grantedTo: ["EasyTrackEvmScriptExecutor", "Voting"],
      },
    },
  },

  // Oracle Contracts
  LegacyOracle: {
    address: LIDO_CONTRACTS.LegacyOracle,
    permissions: {},
  },
};

export const OZ_CONTRACT_ROLES_CONFIG: OZContractRolesConfig = {
  // Core Protocol
  StakingRouter: {
    address: LIDO_CONTRACTS.StakingRouter,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MANAGE_WITHDRAWAL_CREDENTIALS_ROLE: [],
      REPORT_EXITED_VALIDATORS_ROLE: ["AccountingOracle"],
      REPORT_REWARDS_MINTED_ROLE: ["Lido"],
      STAKING_MODULE_MANAGE_ROLE: ["Agent"],
      STAKING_MODULE_UNVETTING_ROLE: ["DepositSecurityModule"],
      UNSAFE_SET_EXITED_VALIDATORS_ROLE: [],
    },
  },
  WithdrawalQueueERC721: {
    address: LIDO_CONTRACTS.WithdrawalQueueERC721,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      FINALIZE_ROLE: ["Lido"],
      MANAGE_TOKEN_URI_ROLE: [],
      ORACLE_ROLE: ["AccountingOracle"],
      PAUSE_ROLE: [],
      RESUME_ROLE: ["Agent"],
    },
  },
  Burner: {
    address: LIDO_CONTRACTS.Burner,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      REQUEST_BURN_MY_STETH_ROLE: [],
      REQUEST_BURN_SHARES_ROLE: [
        "Lido",
        "CuratedModule",
        "SimpleDVT",
        "CSAccounting",
      ],
    },
  },

  // Oracle Contracts
  AccountingOracle: {
    address: LIDO_CONTRACTS.AccountingOracle,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      SUBMIT_DATA_ROLE: [],
    },
  },
  AccountingOracleHashConsensus: {
    address: LIDO_CONTRACTS.AccountingOracleHashConsensus,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: [],
      MANAGE_FRAME_CONFIG_ROLE: [],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: [],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
  },
  ValidatorExitBusOracle: {
    address: LIDO_CONTRACTS.ValidatorExitBusOracle,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      PAUSE_ROLE: [],
      RESUME_ROLE: ["Agent"],
      SUBMIT_DATA_ROLE: [],
    },
  },
  ValidatorExitBusHashConsensus: {
    address: LIDO_CONTRACTS.ValidatorExitBusHashConsensus,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: [],
      MANAGE_FRAME_CONFIG_ROLE: [],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: [],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
  },
  OracleReportSanityChecker: {
    address: LIDO_CONTRACTS.OracleReportSanityChecker,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      ALL_LIMITS_MANAGER_ROLE: [],
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
  },
  OracleDaemonConfig: {
    address: LIDO_CONTRACTS.OracleDaemonConfig,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      CONFIG_MANAGER_ROLE: [],
    },
  },
  // Staking Modules
  CSModule: {
    address: LIDO_CONTRACTS.CSModule,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MODULE_MANAGER_ROLE: [],
      PAUSE_ROLE: [],
      RECOVERER_ROLE: [],
      REPORT_EL_REWARDS_STEALING_PENALTY_ROLE: [],
      RESUME_ROLE: [],
      SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE: ["EasyTrackEvmScriptExecutor"],
      STAKING_ROUTER_ROLE: ["StakingRouter"],
      VERIFIER_ROLE: [],
    },
  },
  CSAccounting: {
    address: LIDO_CONTRACTS.CSAccounting,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      ACCOUNTING_MANAGER_ROLE: [],
      MANAGE_BOND_CURVES_ROLE: [],
      PAUSE_ROLE: [],
      RECOVERER_ROLE: [],
      RESET_BOND_CURVE_ROLE: ["CSModule"],
      RESUME_ROLE: [],
      SET_BOND_CURVE_ROLE: ["CSModule"],
    },
  },
  CSFeeDistributor: {
    address: LIDO_CONTRACTS.CSFeeDistributor,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      RECOVERER_ROLE: [],
    },
  },
  CSFeeOracle: {
    address: LIDO_CONTRACTS.CSFeeOracle,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      CONTRACT_MANAGER_ROLE: [],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      PAUSE_ROLE: [],
      RECOVERER_ROLE: [],
      RESUME_ROLE: [],
      SUBMIT_DATA_ROLE: [],
    },
  },
  CSHashConsensus: {
    address: LIDO_CONTRACTS.CSHashConsensus,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: [],
      MANAGE_FRAME_CONFIG_ROLE: [],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: [],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
  },
  // Easy Track
  EasyTrack: {
    address: LIDO_CONTRACTS.EasyTrack,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Voting"],
      CANCEL_ROLE: [],
      PAUSE_ROLE: [],
      UNPAUSE_ROLE: [],
    },
  },
  AllowedTokensRegistry: {
    address: LIDO_CONTRACTS.AllowedTokensRegistry,
    roles: {
      DEFAULT_ADMIN_ROLE: ["Voting"],
      ADD_TOKEN_TO_ALLOWED_LIST_ROLE: ["Voting"],
      REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE: ["Voting"],
    },
  },
} as const;

export const MANAGED_CONTRACTS: ManagedContractsConfig = {
  DSM: {
    address: "0x808DE3b26Be9438F12E9B45528955EA94C17f217",
    properties: {
      owner: { property: "getOwner", managedBy: "Agent" },
    },
  },
  "LidoLocator :: Proxy": {
    address: "0x28FAB2059C713A7F9D8c86Db49f9bb0e96Af1ef8",
    properties: { admin: { property: "proxy__getAdmin", managedBy: "Agent" } },
  },
  "StakingRouter :: Proxy": {
    address: "0xd6EbF043D30A7fe46D1Db32BA90a0A51207FE229",
    properties: { admin: { property: "proxy__getAdmin", managedBy: "Agent" } },
  },
  "WithdrawalQueue :: Proxy": {
    address: "0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50",
    properties: { admin: { property: "proxy__getAdmin", managedBy: "Agent" } },
  },
  "WithdrawalVault :: Proxy": {
    address: "0xF0179dEC45a37423EAD4FaD5fCb136197872EAd9",
    properties: { admin: { property: "proxy_getAdmin", managedBy: "Agent" } },
  },
  "AccountingOracle :: Proxy": {
    address: "0x4E97A3972ce8511D87F334dA17a2C332542a5246",
    properties: { admin: { property: "proxy__getAdmin", managedBy: "Agent" } },
  },
  "ValidatorsExitBusOracle :: Proxy": {
    address: "0xffDDF7025410412deaa05E3E1cE68FE53208afcb",
    properties: { admin: { property: "proxy__getAdmin", managedBy: "Agent" } },
  },
};

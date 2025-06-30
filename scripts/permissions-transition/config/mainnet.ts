import { PermissionsConfigData } from "../src/permissions-config";

export const MAINNET_PERMISSIONS_CONFIG: PermissionsConfigData = {
  genesisBlock: 10_500_000,
  explorerURL: "https://etherscan.io",
  labels: {
    DGAdminExecutor: "0x23E0B465633FF5178808F4A75186E2F2F9537021",
    ResealManager: "0x7914b5a1539b97Bd0bbd155757F25FD79A522d24",
    // Core Protocol
    LidoLocator: "0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb",
    Lido: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
    StakingRouter: "0xFdDf38947aFB03C621C71b06C9C70bce73f12999",
    DepositSecurityModule: "0xffa96d84def2ea035c7ab153d8b991128e3d72fd",
    WithdrawalQueueERC721: "0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1",
    WithdrawalVault: "0xb9d7934878b5fb9610b3fe8a5e441e8fad7e293f",
    Burner: "0xD15a672319Cf0352560eE76d9e89eAB0889046D3",
    MEVBoostRelayAllowedList: "0xF95f069F9AD107938F6ba802a3da87892298610E",

    // Oracle Contracts
    AccountingOracle: "0x852deD011285fe67063a08005c71a85690503Cee",
    AccountingOracleHashConsensus: "0xD624B08C83bAECF0807Dd2c6880C3154a5F0B288",
    ValidatorsExitBusOracle: "0x0De4Ea0184c2ad0BacA7183356Aea5B8d5Bf5c6e",
    ValidatorsExitBusHashConsensus: "0x7FaDB6358950c5fAA66Cb5EB8eE5147De3df355a",
    OracleReportSanityChecker: "0x6232397ebac4f5772e53285B26c47914E9461E75",
    OracleDaemonConfig: "0xbf05A929c3D7885a6aeAd833a992dA6E5ac23b09",

    // DAO Contracts
    ACL: "0x9895f0f17cc1d1891b6f18ee0b483b6f221b37bb",
    DAOKernel: "0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc",
    Voting: "0x2e59A20f205bB85a89C53f1936454680651E618e",
    Agent: "0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c",
    TokenManager: "0xf73a1260d222f447210581DDf212D915c09a3249",
    Finance: "0xB9E5CBB9CA5b0d659238807E84D0176930753d86",
    OraclesGateSeal: "0xf9c9fdb4a5d2aa1d836d5370ab9b28bc1847e178",
    EVMScriptRegistry: "0x853cc0D5917f49B57B8e9F89e491F5E18919093A",

    // Staking Modules
    CuratedModule: "0x55032650b14df07b85bF18A3a3eC8E0Af2e028d5",
    SimpleDVT: "0xaE7B191A31f627b4eB1d4DaC64eaB9976995b433",
    CSModule: "0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F",
    CSAccounting: "0x4d72BFF1BeaC69925F8Bd12526a39BAAb069e5Da",
    CSFeeDistributor: "0xD99CC66fEC647E68294C6477B40fC7E0F6F618D0",
    CSGateSeal: "0x16Dbd4B85a448bE564f1742d5c8cCdD2bB3185D0",
    CSFeeOracle: "0x4D4074628678Bd302921c20573EEa1ed38DdF7FB",
    CSHashConsensus: "0x71093efF8D8599b5fA340D665Ad60fA7C80688e4",
    CSCommitteeMultisig: "0xc52fc3081123073078698f1eac2f1dc7bd71880f",
    CSVerifier: "0x0c345dFa318f9F4977cdd4f33d80F9D0ffA38e8B",

    // Anchor Integration
    AnchorVault: "0xA2F987A546D4CD1c607Ee8141276876C26b72Bdf",
    bETH: "0x707f9118e33a9b8998bea41dd0d46f38bb963fc8",

    // DAO Ops contracts & addresses
    VestingEscrowFactory: "0xDA1DF6442aFD2EC36aBEa91029794B9b2156ADD0",

    // EasyTrack
    EasyTrack: "0xF0211b7660680B49De1A7E9f25C65660F0a13Fea",
    EvmScriptExecutor: "0xFE5986E06210aC1eCC1aDCafc0cc7f8D63B3F977",
    AllowedTokensRegistry: "0x4AC40c34f8992bb1e5E856A448792158022551ca",

    // Insurance
    InsuranceFund: "0x8B3f33234ABD88493c0Cd28De33D583B70beDe35",

    // Arbitrum
    L1ERC20TokenGateway_Arbitrum: "0x0F25c1DC2a9922304f2eac71DCa9B07E310e8E5a",

    // Optimism
    TokenRateNotifier_Optimism: "0xe6793B9e4FbA7DE0ee833F9D02bba7DB5EB27823",
    L1LidoTokensBridge_Optimism: "0x76943C0D61395d8F2edF9060e1533529cAe05dE6",

    // Polygon
    ERC20Predicate_Polygon: "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",
    Timelock_Polygon: "0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf",
    RootChainManagerProxy_Polygon: "0xA0c68C638235ee32657e8f720a23ceC1bFc77C77",
    ManagerMultisig_Polygon: "0xFa7D2a996aC6350f4b56C043112Da0366a59b74c",

    // Base
    L1ERC20TokenBridge_Base: "0x9de443AdC5A411E83F1878Ef24C3F52C61571e72",

    // zkSync
    L1Executor_zkSync: "0xFf7F4d05e3247374e86A3f7231A2Ed1CA63647F2",
    L1ERC20Bridge_zkSync: "0x41527B2d03844dB6b0945f25702cB958b6d55989",

    // Mantle
    L1ERC20TokenBridge_Mantle: "0x2D001d79E5aF5F65a939781FE228B267a8Ed468B",

    // Linea
    L1TokenBridge_Linea: "0x051f1d88f0af5763fb888ec4378b4d8b29ea3319",
    LineaSecurityCouncil_Linea: "0x892bb7EeD71efB060ab90140e7825d8127991DD3",
    L1TokenBridgeProxyAdmin_Linea: "0xF5058616517C068C7b8c7EbC69FF636Ade9066d6",
    ProxyAdminTimelock_Linea: "0xd6B95c960779c72B8C6752119849318E5d550574",
    L1TokenBridgeManagerMultisig_Linea: "0xB8F5524D73f549Cf14A0587a3C7810723f9c0051",

    // Scroll
    L1LidoGateway_Scroll: "0x6625c6332c9f91f2d27c304e729b86db87a3f504",
    L1LidoGatewayProxyAdmin_Scroll: "0xCC2C53556Bc75217cf698721b29071d6f12628A9",

    // Mode
    L1ERC20TokenBridge_Mode: "0xD0DeA0a3bd8E4D55170943129c025d3fe0493F2A",

    // Binance Smart Chain
    CrossChainController_BSC: "0x93559892D3C7F66DE4570132d68b69BD3c369A7C",
    CrossChainControllerProxyAdmin_BSC: "0xADD673dC6A655AFD6f38fB88301028fA31A6fDeE",
    NTTManager_BSC: "0xb948a93827d68a82F6513Ad178964Da487fe2BD9",
    WormholeTransceiver_BSC: "0xA1ACC1e6edaB281Febd91E3515093F1DE81F25c0",
    AxelarTransceiver_BSC: "0x723AEAD29acee7E9281C32D11eA4ed0070c41B13",

    //Zircuit
    L1ERC20TokenBridge_Zircuit: "0x912C7271a6A3622dfb8B218eb46a6122aB046C79",

    // Soneium
    L1LidoTokensBridge_Soneium: "0x2F543A7C9cc80Cc2427c892B96263098d23ee55a",

    // Unichain
    L1LidoTokensBridge_Unichain: "0x755610f5Be536Ad7afBAa7c10F3E938Ea3aa1877",

    // Lisk
    L1LidoTokensBridge_Lisk: "0x9348AF23B01F2B517AFE8f29B3183d2Bb7d69Fcf",

    // Swellchain
    L1LidoTokensBridge_Swellchain: "0xecf3376512EDAcA4FBB63d2c67d12a0397d24121",

    // Emergency Brakes
    EmergencyBrakesMultisig: "0x73b047fe6337183A454c5217241D780a932777bD",
  },
  aragon: {
    // Core protocol
    Lido: {
      STAKING_CONTROL_ROLE: { manager: "Agent" },
      RESUME_ROLE: { manager: "Agent" },
      PAUSE_ROLE: { manager: "Agent" },
      UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE: { manager: "None" },
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
      ISSUE_ROLE: { manager: "Voting" },
      ASSIGN_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      BURN_ROLE: { manager: "Voting" },
      MINT_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
      REVOKE_VESTINGS_ROLE: { manager: "Voting", grantedTo: ["Voting"] },
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
    EVMScriptRegistry: {
      REGISTRY_ADD_EXECUTOR_ROLE: { manager: "Agent" },
      REGISTRY_MANAGER_ROLE: { manager: "Agent" },
    },

    // Staking Modules
    CuratedModule: {
      STAKING_ROUTER_ROLE: { manager: "Agent", grantedTo: ["StakingRouter"] },
      MANAGE_NODE_OPERATOR_ROLE: { manager: "Agent", grantedTo: ["Agent"] },
      SET_NODE_OPERATOR_LIMIT_ROLE: { manager: "Agent", grantedTo: ["EvmScriptExecutor"] },
      MANAGE_SIGNING_KEYS: { manager: "Agent", grantedTo: [] },
    },
    SimpleDVT: {
      STAKING_ROUTER_ROLE: {
        manager: "Agent",
        grantedTo: ["StakingRouter", "EvmScriptExecutor"],
      },
      MANAGE_NODE_OPERATOR_ROLE: {
        manager: "Agent",
        grantedTo: ["EvmScriptExecutor"],
      },
      SET_NODE_OPERATOR_LIMIT_ROLE: {
        manager: "Agent",
        grantedTo: ["EvmScriptExecutor"],
      },
      MANAGE_SIGNING_KEYS: {
        manager: "EvmScriptExecutor",
        grantedTo: ["EvmScriptExecutor"],
      },
    },
    ACL: {
      CREATE_PERMISSIONS_ROLE: { manager: "Agent", grantedTo: ["Agent"] },
    },
    Agent: {
      TRANSFER_ROLE: { manager: "Voting", grantedTo: ["Finance"] },
      RUN_SCRIPT_ROLE: {
        manager: "Agent",
        grantedTo: ["DGAdminExecutor"],
      },
      EXECUTE_ROLE: {
        manager: "Agent",
        grantedTo: ["DGAdminExecutor"],
      },
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
      STAKING_MODULE_MANAGE_ROLE: ["Agent"],
      STAKING_MODULE_UNVETTING_ROLE: ["DepositSecurityModule"],
      UNSAFE_SET_EXITED_VALIDATORS_ROLE: [],
    },
    WithdrawalQueueERC721: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      FINALIZE_ROLE: ["Lido"],
      MANAGE_TOKEN_URI_ROLE: [],
      ORACLE_ROLE: ["AccountingOracle"],
      PAUSE_ROLE: ["OraclesGateSeal", "ResealManager"],
      RESUME_ROLE: ["ResealManager"],
    },
    Burner: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      REQUEST_BURN_MY_STETH_ROLE: ["Agent"],
      REQUEST_BURN_SHARES_ROLE: ["Lido", "CuratedModule", "SimpleDVT", "CSAccounting"],
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
      MANAGE_FRAME_CONFIG_ROLE: [],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["Agent"],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
    ValidatorsExitBusOracle: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      PAUSE_ROLE: ["OraclesGateSeal", "ResealManager"],
      RESUME_ROLE: ["ResealManager"],
      SUBMIT_DATA_ROLE: [],
    },
    ValidatorsExitBusHashConsensus: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: [],
      MANAGE_FRAME_CONFIG_ROLE: [],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["Agent"],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },
    OracleReportSanityChecker: {
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
    OracleDaemonConfig: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      CONFIG_MANAGER_ROLE: [],
    },

    // Staking Modules
    CSModule: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      MODULE_MANAGER_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal", "ResealManager"],
      RECOVERER_ROLE: [],
      REPORT_EL_REWARDS_STEALING_PENALTY_ROLE: ["CSCommitteeMultisig"],
      RESUME_ROLE: ["ResealManager"],
      SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE: ["EvmScriptExecutor"],
      STAKING_ROUTER_ROLE: ["StakingRouter"],
      VERIFIER_ROLE: ["CSVerifier"],
    },
    CSAccounting: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      ACCOUNTING_MANAGER_ROLE: [],
      MANAGE_BOND_CURVES_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal", "ResealManager"],
      RECOVERER_ROLE: [],
      RESET_BOND_CURVE_ROLE: ["CSModule", "CSCommitteeMultisig"],
      RESUME_ROLE: ["ResealManager"],
      SET_BOND_CURVE_ROLE: ["CSModule", "CSCommitteeMultisig"],
    },
    CSFeeDistributor: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      RECOVERER_ROLE: [],
    },
    CSFeeOracle: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      CONTRACT_MANAGER_ROLE: [],
      MANAGE_CONSENSUS_CONTRACT_ROLE: [],
      MANAGE_CONSENSUS_VERSION_ROLE: [],
      PAUSE_ROLE: ["CSGateSeal", "ResealManager"],
      RECOVERER_ROLE: [],
      RESUME_ROLE: ["ResealManager"],
      SUBMIT_DATA_ROLE: [],
    },
    CSHashConsensus: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DISABLE_CONSENSUS_ROLE: [],
      MANAGE_FAST_LANE_CONFIG_ROLE: [],
      MANAGE_FRAME_CONFIG_ROLE: [],
      MANAGE_MEMBERS_AND_QUORUM_ROLE: ["Agent"],
      MANAGE_REPORT_PROCESSOR_ROLE: [],
    },

    // Easy Track
    EasyTrack: {
      DEFAULT_ADMIN_ROLE: ["Voting"],
      CANCEL_ROLE: ["Voting"],
      PAUSE_ROLE: ["Voting", "EmergencyBrakesMultisig"],
      UNPAUSE_ROLE: ["Voting"],
    },
    AllowedTokensRegistry: {
      DEFAULT_ADMIN_ROLE: ["Voting"],
      ADD_TOKEN_TO_ALLOWED_LIST_ROLE: [],
      REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE: [],
    },

    // Arbitrum
    L1ERC20TokenGateway_Arbitrum: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Optimism
    L1LidoTokensBridge_Optimism: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Polygon
    ERC20Predicate_Polygon: {
      DEFAULT_ADMIN_ROLE: ["ManagerMultisig_Polygon"],
      MANAGER_ROLE: ["RootChainManagerProxy_Polygon"],
    },

    // Base
    L1ERC20TokenBridge_Base: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // zkSync
    L1ERC20Bridge_zkSync: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Mantle
    L1ERC20TokenBridge_Mantle: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Linea
    L1TokenBridge_Linea: {
      DEFAULT_ADMIN_ROLE: ["LineaSecurityCouncil_Linea"],
      PAUSE_ALL_ROLE: ["LineaSecurityCouncil_Linea"],
      PAUSE_COMPLETE_TOKEN_BRIDGING_ROLE: ["LineaSecurityCouncil_Linea"],
      PAUSE_INITIATE_TOKEN_BRIDGING_ROLE: ["LineaSecurityCouncil_Linea"],
      REMOVE_RESERVED_TOKEN_ROLE: ["LineaSecurityCouncil_Linea", "L1TokenBridgeManagerMultisig_Linea"],
      SET_CUSTOM_CONTRACT_ROLE: ["LineaSecurityCouncil_Linea", "L1TokenBridgeManagerMultisig_Linea"],
      SET_MESSAGE_SERVICE_ROLE: ["LineaSecurityCouncil_Linea"],
      SET_REMOTE_TOKENBRIDGE_ROLE: ["LineaSecurityCouncil_Linea"],
      SET_RESERVED_TOKEN_ROLE: ["LineaSecurityCouncil_Linea", "L1TokenBridgeManagerMultisig_Linea"],
      UNPAUSE_ALL_ROLE: ["LineaSecurityCouncil_Linea"],
      UNPAUSE_COMPLETE_TOKEN_BRIDGING_ROLE: ["LineaSecurityCouncil_Linea"],
      UNPAUSE_INITIATE_TOKEN_BRIDGING_ROLE: ["LineaSecurityCouncil_Linea"],
    },

    // Scroll
    L1LidoGateway_Scroll: {
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Mode
    L1ERC20TokenBridge_Mode: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    //Zircuit
    L1ERC20TokenBridge_Zircuit: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Soneium
    L1LidoTokensBridge_Soneium: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Unichain
    L1LidoTokensBridge_Unichain: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Lisk
    L1LidoTokensBridge_Lisk: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
    },

    // Swellchain
    L1LidoTokensBridge_Swellchain: {
      DEFAULT_ADMIN_ROLE: ["Agent"],
      DEPOSITS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      DEPOSITS_ENABLER_ROLE: ["Agent"],
      WITHDRAWALS_DISABLER_ROLE: ["Agent", "EmergencyBrakesMultisig"],
      WITHDRAWALS_ENABLER_ROLE: ["Agent"],
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
    InsuranceFund: { owner: "Voting" },
    MEVBoostRelayAllowedList: { get_owner: "Agent" },
    CSModule: { proxy__getAdmin: "Agent" },
    CSAccounting: { proxy__getAdmin: "Agent" },
    CSFeeDistributor: { proxy__getAdmin: "Agent" },
    CSFeeOracle: { proxy__getAdmin: "Agent" },
    AnchorVault: { admin: "Agent", proxy_getAdmin: "Agent" },
    bETH: { admin: "Agent" },
    VestingEscrowFactory: { owner: "Agent" },
    EvmScriptExecutor: { owner: "Voting" },

    // L2s
    L1ERC20TokenGateway_Arbitrum: { proxy__getAdmin: "Agent" },

    L1LidoTokensBridge_Optimism: { proxy__getAdmin: "Agent" },
    TokenRateNotifier_Optimism: { owner: "Agent" },

    ERC20Predicate_Polygon: { proxyOwner: "Timelock_Polygon" },
    RootChainManagerProxy_Polygon: {
      proxyOwner: "Timelock_Polygon",
    },

    L1ERC20TokenBridge_Base: { proxy__getAdmin: "Agent" },

    L1Executor_zkSync: { owner: "Agent", proxy__getAdmin: "Agent" },
    L1ERC20Bridge_zkSync: { proxy__getAdmin: "Agent" },

    L1ERC20TokenBridge_Mantle: { proxy__getAdmin: "Agent" },

    L1TokenBridgeProxyAdmin_Linea: { owner: "ProxyAdminTimelock_Linea" },

    L1LidoGateway_Scroll: { owner: "Agent" },
    L1LidoGatewayProxyAdmin_Scroll: { owner: "Agent" },

    L1ERC20TokenBridge_Mode: { proxy__getAdmin: "Agent" },

    CrossChainController_BSC: { owner: "Agent" },
    CrossChainControllerProxyAdmin_BSC: { owner: "Agent" },
    AxelarTransceiver_BSC: { owner: "Agent" },
    WormholeTransceiver_BSC: { owner: "Agent" },
    NTTManager_BSC: { owner: "Agent" },

    L1ERC20TokenBridge_Zircuit: { proxy__getAdmin: "Agent" },

    L1LidoTokensBridge_Soneium: { proxy__getAdmin: "Agent" },

    L1LidoTokensBridge_Unichain: { proxy__getAdmin: "Agent" },

    L1LidoTokensBridge_Lisk: { proxy__getAdmin: "Agent" },

    L1LidoTokensBridge_Swellchain: { proxy__getAdmin: "Agent" },
  },
};

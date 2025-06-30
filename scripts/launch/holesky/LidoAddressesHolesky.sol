// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract LidoAddressesHolesky {
    address public constant ACL = 0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC;
    address public constant LIDO = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address public constant KERNEL = 0x3b03f75Ec541Ca11a223bB58621A3146246E1644;
    address public constant VOTING = 0xdA7d2573Df555002503F29aA4003e398d28cc00f;
    address public constant TOKEN_MANAGER = 0xFaa1692c6eea8eeF534e7819749aD93a1420379A;
    address public constant FINANCE = 0xf0F281E5d7FBc54EAFcE0dA225CDbde04173AB16;
    address public constant AGENT = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
    address public constant EVM_SCRIPT_REGISTRY = 0xE1200ae048163B67D69Bc0492bF5FddC3a2899C0;
    address public constant CURATED_MODULE = 0x595F64Ddc3856a3b5Ff4f4CC1d1fb4B46cFd2bAC;
    address public constant SDVT_MODULE = 0x11a93807078f8BB880c1BD0ee4C387537de4b4b6;
    address public constant ALLOWED_TOKENS_REGISTRY = 0x091C0eC8B4D54a9fcB36269B5D5E5AF43309e666;
    address public constant WITHDRAWAL_VAULT = 0xF0179dEC45a37423EAD4FaD5fCb136197872EAd9;
    address public constant WITHDRAWAL_QUEUE = 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
    address public constant VEBO = 0xffDDF7025410412deaa05E3E1cE68FE53208afcb;
    address public constant STAKING_ROUTER = 0xd6EbF043D30A7fe46D1Db32BA90a0A51207FE229;
    address public constant ORACLES_GATE_SEAL = 0xAE6eCd77DCC656c5533c4209454Fd56fB46e1778;
    address public constant EVM_SCRIPT_EXECUTOR = 0x2819B65021E13CEEB9AC33E77DB32c7e64e7520D;

    // Dev Addresses And Contracts
    address public constant DEV_EOA_1 = 0xDA6bEE5441f2e6b364F3b25E85d5f3C29Bfb669E;
    address public constant DEV_EOA_2 = 0x66b25CFe6B9F0e61Bd80c4847225Baf4EE6Ba0A2;
    address public constant DEV_EOA_3 = 0x2A329E1973217eB3828EB0F2225d1b1C10DB72B0;
    address public constant UNLIMITED_STAKE = 0xCfAC1357B16218A90639cd17F90226B385A71084;

    // Additional grantee of the Agent.RUN_SCRIPT_ROLE, which may be used
    // for development purposes or as a fallback recovery mechanism.
    address public constant AGENT_MANAGER = 0xc807d4036B400dE8f6cD2aDbd8d9cf9a3a01CC30;
}

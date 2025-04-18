// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract LidoAddressesHoodi {
    address public constant ACL = 0x78780e70Eae33e2935814a327f7dB6c01136cc62;
    address public constant LIDO = 0x3508A952176b3c15387C97BE809eaffB1982176a;
    address public constant KERNEL = 0xA48DF029Fd2e5FCECB3886c5c2F60e3625A1E87d;
    address public constant VOTING = 0x49B3512c44891bef83F8967d075121Bd1b07a01B;
    address public constant TOKEN_MANAGER = 0x8ab4a56721Ad8e68c6Ad86F9D9929782A78E39E5;
    address public constant FINANCE = 0x254Ae22bEEba64127F0e59fe8593082F3cd13f6b;
    address public constant AGENT = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD;
    address public constant EVM_SCRIPT_REGISTRY = 0xe4D32427b1F9b12ab89B142eD3714dCAABB3f38c;
    address public constant CURATED_MODULE = 0x5cDbE1590c083b5A2A64427fAA63A7cfDB91FbB5;
    address public constant SDVT_MODULE = 0x0B5236BECA68004DB89434462DfC3BB074d2c830;
    address public constant ALLOWED_TOKENS_REGISTRY = 0x40Db7E8047C487bD8359289272c717eA3C34D1D3;
    address public constant WITHDRAWAL_VAULT = 0x4473dCDDbf77679A643BdB654dbd86D67F8d32f2;
    address public constant WITHDRAWAL_QUEUE = 0xfe56573178f1bcdf53F01A6E9977670dcBBD9186;
    address public constant VEBO = 0x8664d394C2B3278F26A1B44B967aEf99707eeAB2;
    address public constant STAKING_ROUTER = 0xCc820558B39ee15C7C45B59390B503b83fb499A8;
    address public constant ORACLES_GATE_SEAL = 0x2168Ea6D948Ab49c3D34c667A7e02F92369F3A9C;
    address public constant EVM_SCRIPT_EXECUTOR = 0x79a20FD0FA36453B2F45eAbab19bfef43575Ba9E;

    // Dev Addresses And Contracts
    address public constant DEV_EOA_1 = 0xE28f573b732632fdE03BD5507A7d475383e8512E;
    address public constant DEV_EOA_2 = 0xF865A1d43D36c713B4DA085f32b7d1e9739B9275;
    address public constant DEV_EOA_3 = 0x4022E0754d0cB6905B54306105D3346d1547988b;
    address public constant UNLIMITED_STAKE = 0x064A4D64040bFD52D0d1dC7f42eA799cb0a8AC40;

    // Additional grantee of the Agent.RUN_SCRIPT_ROLE, which may be used
    // for development purposes or as a fallback recovery mechanism.
    address public constant AGENT_MANAGER = 0xD500a8aDB182F55741E267730dfbfb4F1944C205;
}

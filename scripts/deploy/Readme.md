# Dual Governance deploy scripts

### Running locally with Anvil

Start Anvil, provide RPC URL (Infura as an example)
```
anvil --fork-url https://<mainnet or holesky>.infura.io/v3/<YOUR_API_KEY> --block-time 300
```

### Running the deploy script

1. Import your private key to Cast wallet ([see the docs](https://book.getfoundry.sh/reference/cast/cast-wallet-import)), for example (we will use the account name `Deployer1` here and further for the simplicity):

    ```
    cast wallet import Deployer1 --interactive
    ```

2. Set up the required env variables in the .env file

    ```
    CHAIN=<"mainnet" OR "holesky" OR "holesky-mocks">
    ETHERSCAN_MAINNET_KEY=...
    DEPLOY_CONFIG_FILE_PATH=... (for example: "deploy-config/deploy-config.json")
    ```

3. Create a deploy config JSON file with all the required values (at the location specified in DEPLOY_CONFIG_FILE_PATH):
    ```
    {
        "MIN_EXECUTION_DELAY": 0,
        "AFTER_SUBMIT_DELAY": 259200, // 3 days
        "MAX_AFTER_SUBMIT_DELAY": 3888000, // 45 days
        "AFTER_SCHEDULE_DELAY": 259200, // 3 days
        "MAX_AFTER_SCHEDULE_DELAY": 3888000, // 45 days
        "EMERGENCY_MODE_DURATION": 15552000, // 180 days
        "MAX_EMERGENCY_MODE_DURATION": 31536000, // 365 days
        "EMERGENCY_PROTECTION_DURATION": 7776000, // 90 days
        "MAX_EMERGENCY_PROTECTION_DURATION": 31536000, // 365 days
        "EMERGENCY_ACTIVATION_COMMITTEE": <address>,
        "EMERGENCY_EXECUTION_COMMITTEE": <address>,
        "TIEBREAKER_CORE_QUORUM": 1,
        "TIEBREAKER_SUB_COMMITTEES_COUNT": 2,
        "TIEBREAKER_EXECUTION_DELAY": 2592000, // 30 days
        "TIEBREAKER_SUB_COMMITTEE_1_MEMBERS": [addr1,addr2,addr3],
        "TIEBREAKER_SUB_COMMITTEE_2_MEMBERS": [addr1,addr2,addr3],
        "TIEBREAKER_SUB_COMMITTEE_3_MEMBERS": [],
        "TIEBREAKER_SUB_COMMITTEE_4_MEMBERS": [],
        "TIEBREAKER_SUB_COMMITTEE_5_MEMBERS": [],
        "TIEBREAKER_SUB_COMMITTEE_6_MEMBERS": [],
        "TIEBREAKER_SUB_COMMITTEE_7_MEMBERS": [],
        "TIEBREAKER_SUB_COMMITTEE_8_MEMBERS": [],
        "TIEBREAKER_SUB_COMMITTEE_9_MEMBERS": [],
        "TIEBREAKER_SUB_COMMITTEE_10_MEMBERS": [],
        "TIEBREAKER_SUB_COMMITTEES_QUORUMS": [3,2],
        "RESEAL_COMMITTEE": <address>
        "MIN_WITHDRAWALS_BATCH_SIZE": 4,
        "MIN_TIEBREAKER_ACTIVATION_TIMEOUT": 7776000, // 90 days
        "TIEBREAKER_ACTIVATION_TIMEOUT": 31536000, // 365 days
        "MAX_TIEBREAKER_ACTIVATION_TIMEOUT": 63072000, // 730 days
        "MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT": 255,
        "FIRST_SEAL_RAGE_QUIT_SUPPORT": 300, // 3%
        "SECOND_SEAL_RAGE_QUIT_SUPPORT": 1500, // 15%
        "MIN_ASSETS_LOCK_DURATION": 18000, // 5 hours
        "MAX_MIN_ASSETS_LOCK_DURATION": 31536000, // 365 days
        "VETO_SIGNALLING_MIN_DURATION": 259200, // 3 days
        "VETO_SIGNALLING_MIN_ACTIVE_DURATION":18000, // 5 hours
        "VETO_SIGNALLING_MAX_DURATION": 2592000, // 30 days
        "VETO_SIGNALLING_DEACTIVATION_MAX_DURATION": 432000, // 5 days
        "VETO_COOLDOWN_DURATION": 345600, // 4 days
        "RAGE_QUIT_EXTENSION_PERIOD_DURATION": 604800, // 7 days
        "RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY": 2592000, // 30 days
        "RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY": 15552000, // 180 days
        "RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH": 1296000, // 15 days
        "TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER": <address>
    }
    ```

    When using `CHAIN="holesky-mocks"` you will need to provide in addition already deployed mock contracts addresses in the same JSON config file (at DEPLOY_CONFIG_FILE_PATH):
    
    ```
    {
        ...
        "HOLESKY_MOCK_ST_ETH": ...,
        "HOLESKY_MOCK_WST_ETH": ...,
        "HOLESKY_MOCK_WITHDRAWAL_QUEUE": ...,
        "HOLESKY_MOCK_DAO_VOTING": ...,
        ...
    }
    ```

4. Run the deployment script

    With the local fork (Anvil):
    ```
    forge script scripts/deploy/DeployConfigurable.s.sol:DeployConfigurable --fork-url http://localhost:8545 --broadcast --account Deployer1 --sender <DEPLOYER1_ADDRESS>
    ```

    On a testnet (with Etherscan verification):
    ```
    forge script scripts/deploy/DeployConfigurable.s.sol:DeployConfigurable --fork-url https://holesky.infura.io/v3/<YOUR_API_KEY> --broadcast --account Deployer1 --sender <DEPLOYER1_ADDRESS> --verify
    ```

5. [Testnet and mainnet deployment only] Run Etherscan verification for Escrow contract

    The Escrow contract is deployed internally by DualGovernance contract, so it can't be verified automatically during the initial deployment and requires manual verification afterward. To run Etherscan verification:

    a. Query the deployed DualGovernance contract instance for ESCROW_MASTER_COPY address.

    b. Run Etherscan verification (for example on a Holesky testnet)

    ```
    forge verify-contract --chain holesky --verifier-url https://api-holesky.etherscan.io/api --watch --constructor-args $(cast abi-encode "Escrow(address,address,address,address,uint256)" <ST_ETH_ADDRESS> <WST_ETH_ADDRESS> <WITHDRAWAL_QUEUE_ADDRESS> <DUAL_GOVERNANCE_ADDRESS> <MIN_WITHDRAWALS_BATCH_SIZE>) <ESCROW_MASTER_COPY> contracts/Escrow.sol:Escrow
    ```

### Running the verification script

1. Set up the required env variables in the .env file

    ```
    CHAIN=<"mainnet" OR "holesky" OR "holesky-mocks">
    DEPLOYED_ADDRESSES_FILE_PATH=... (for example: "deploy-config/deployed-addrs.json")
    ONCHAIN_VOTING_CHECK_MODE=false
    ```

2. Create a deployed addresses list JSON file with all the required values (at the location specified in DEPLOYED_ADDRESSES_FILE_PATH):

    ```
    {
        "ADMIN_EXECUTOR": <address>,
        "TIMELOCK": <address>,
        "EMERGENCY_GOVERNANCE": <address>,
        "EMERGENCY_ACTIVATION_COMMITTEE": <address>,
        "EMERGENCY_EXECUTION_COMMITTEE": <address>,
        "RESEAL_MANAGER": <address>,
        "DUAL_GOVERNANCE": <address>,
        "RESEAL_COMMITTEE": <address>,
        "TIEBREAKER_CORE_COMMITTEE": <address>,
        "TIEBREAKER_SUB_COMMITTEES": [<address>, <address>],
        "TEMPORARY_EMERGENCY_GOVERNANCE": <address>
    }
    ```

3. Run the script (with the local Anvil as an example)

    ```
    forge script scripts/deploy/Verify.s.sol:Verify --fork-url http://localhost:8545 --broadcast
    ```

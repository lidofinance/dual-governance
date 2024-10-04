# Dual Governance deploy scripts

### Running locally with Anvil

Start Anvil, provide RPC url (Infura as an example)
```
anvil --fork-url https://<mainnet or holesky>.infura.io/v3/<YOUR_API_KEY> --block-time 300
```

### Running the deploy script

1. Set up the required env variables in the .env file

    ```
    CHAIN=<"mainnet" OR "holesky" OR "holesky-mocks">
    DEPLOYER_PRIVATE_KEY=...
    DEPLOY_CONFIG_FILE_PATH=... (for example: "deploy-config/deploy-config.json")
    ```
2. Create a deploy config JSON file with all the required values (at the location specified in DEPLOY_CONFIG_FILE_PATH):
    ```
    {
        "EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS": [addr1,addr2,addr3],
        "EMERGENCY_EXECUTION_COMMITTEE_MEMBERS": [addr1,addr2,addr3],
        "TIEBREAKER_SUB_COMMITTEE_1_MEMBERS": [addr1,addr2,addr3],
        "TIEBREAKER_SUB_COMMITTEE_2_MEMBERS": [addr1,addr2,addr3],
        "TIEBREAKER_SUB_COMMITTEES_QUORUMS": [3,2],
        "TIEBREAKER_SUB_COMMITTEES_COUNT": 2,
        "RESEAL_COMMITTEE_MEMBERS": [addr1,addr2,addr3]
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

3. Run the script (with the local Anvil as an example)

    ```
    forge script scripts/deploy/DeployConfigurable.s.sol:DeployConfigurable --fork-url http://localhost:8545 --broadcast
    ```

### Running the verification script

1. Set up the required env variables in the .env file

    ```
    CHAIN=<"mainnet" OR "holesky" OR "holesky-mocks">
    DEPLOYED_ADDRESSES_FILE_PATH=... (for example: "deploy-config/deployed-addrs.json")
    ```

2. Create a deployed addresses list JSON file with all the required values (at the location specified in DEPLOYED_ADDRESSES_FILE_PATH):

    ```
    {
        "ADMIN_EXECUTOR": "...",
        "TIMELOCK": "...",
        "EMERGENCY_GOVERNANCE": "...",
        "EMERGENCY_ACTIVATION_COMMITTEE": "...",
        "EMERGENCY_EXECUTION_COMMITTEE": "...",
        "RESEAL_MANAGER": "...",
        "DUAL_GOVERNANCE": "...",
        "RESEAL_COMMITTEE": "...",
        "TIEBREAKER_CORE_COMMITTEE": "...",
        "TIEBREAKER_SUB_COMMITTEES": ["...", "..."]
    }
    ```

3. Run the script (with the local Anvil as an example)

    ```
    forge script scripts/deploy/Verify.s.sol:Verify --fork-url http://localhost:8545 --broadcast
    ```

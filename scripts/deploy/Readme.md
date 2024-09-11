# Dual Governance deploy scripts

### Running locally with Anvil

Start Anvil, provide RPC url (Infura as an example)
```
anvil --fork-url https://<mainnet or holesky>.infura.io/v3/<YOUR_API_KEY> --block-time 300
```

### Running the deploy script

1. Set up required env variables in .env file

    ```
    CHAIN=<"mainnet" OR "holesky" OR "holesky-mocks">
    DEPLOYER_PRIVATE_KEY=...
    EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS=addr1,addr2,addr3
    EMERGENCY_EXECUTION_COMMITTEE_MEMBERS=addr1,addr2,addr3
    TIEBREAKER_SUB_COMMITTEE_1_MEMBERS=addr1,addr2,addr3
    TIEBREAKER_SUB_COMMITTEE_2_MEMBERS=addr1,addr2,addr3
    TIEBREAKER_SUB_COMMITTEES_QUORUMS=3,2
    TIEBREAKER_SUB_COMMITTEES_COUNT=2
    RESEAL_COMMITTEE_MEMBERS=addr1,addr2,addr3
    ```

    When using `CHAIN="holesky-mocks"` you will need to provide in addition already deployed mock contracts addresses:
    
    ```
    HOLESKY_MOCK_ST_ETH=...
    HOLESKY_MOCK_WST_ETH=...
    HOLESKY_MOCK_WITHDRAWAL_QUEUE=...
    HOLESKY_MOCK_DAO_VOTING=...
    ```

2. Run the script (with the local Anvil as an example)

    ```
    forge script scripts/deploy/DeployConfigurable.s.sol:DeployConfigurable --fork-url http://localhost:8545 --broadcast
    ```

### Running the verification script

1. Set up required env variables in .env file

    ```
    CHAIN=<"mainnet" OR "holesky" OR "holesky-mocks">
    ADMIN_EXECUTOR=...
    TIMELOCK=...
    EMERGENCY_GOVERNANCE=...
    EMERGENCY_ACTIVATION_COMMITTEE=...
    EMERGENCY_EXECUTION_COMMITTEE=...
    RESEAL_MANAGER=...
    DUAL_GOVERNANCE=...
    RESEAL_COMMITTEE=...
    TIEBREAKER_CORE_COMMITTEE=...
    TIEBREAKER_SUB_COMMITTEES=...
    ```

2. Run the script (with the local Anvil as an example)

    ```
    forge script scripts/deploy/Verify.s.sol:Verify --fork-url http://localhost:8545 --broadcast
    ```

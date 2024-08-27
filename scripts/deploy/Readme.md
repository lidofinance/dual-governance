# Dual Governance deploy script

### Running locally with Anvil

Start Anvil, provide RPC url (Infura as an example)
```
anvil --fork-url https://<mainnet or holesky>.infura.io/v3/<YOUR_API_KEY> --block-time 300
```

### Running the script

1. Set up required env variables in .env file

    ```
    CHAIN=<"mainnet" OR "holesky">
    DEPLOYER_PRIVATE_KEY=...
    EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS=addr1,addr2,addr3
    EMERGENCY_EXECUTION_COMMITTEE_MEMBERS=addr1,addr2,addr3
    TIEBREAKER_SUB_COMMITTEE_1_MEMBERS=addr1,addr2,addr3
    TIEBREAKER_SUB_COMMITTEE_2_MEMBERS=addr1,addr2,addr3
    RESEAL_COMMITTEE_MEMBERS=addr1,addr2,addr3
    ```
2. Run the script (with the local Anvil as an example)

    ```
    forge script scripts/deploy/Deploy.s.sol:DeployDG --fork-url http://localhost:8545 --broadcast
    ```

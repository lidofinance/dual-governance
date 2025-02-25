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
    ETHERSCAN_API_KEY=...
    DEPLOY_CONFIG_FILE_NAME=... (in the `deploy-config` folder, for example: "deploy-config.toml")
    ```

3. Create a deploy config TOML file with all the required values (at the location specified in `DEPLOY_CONFIG_FILE_NAME`):
    ```toml
    chain_id = 17000

    # ======================
    # DUAL GOVERNANCE CONFIG
    # ======================

    [dual_governance]
    admin_proposer = "<address>"
    reseal_committee = "<address>"
    proposals_canceller = "<address>"
    tiebreaker_activation_timeout = 31536000            # 365 days
    sealable_withdrawal_blockers = ["<address>"]

    [dual_governance.signalling_tokens]
    st_eth = "<address>"
    wst_eth = "<address>"
    withdrawal_queue = "<address>"

    [dual_governance.sanity_check_params]
    min_withdrawals_batch_size = 4
    max_tiebreaker_activation_timeout = 63072000        # 730 days
    min_tiebreaker_activation_timeout = 7776000         # 90 days
    max_sealable_withdrawal_blockers_count = 255
    max_min_assets_lock_duration = 31536000             # 365 days

    [dual_governance_config_provider]
    first_seal_rage_quit_support = 300                  # 3%
    second_seal_rage_quit_support = 1500                # 15%
    min_assets_lock_duration = 18000                    # 5 hours
    veto_signalling_min_duration = 259200               # 3 days
    veto_signalling_min_active_duration = 18000         # 5 hours
    veto_signalling_max_duration = 2592000              # 30 days
    veto_signalling_deactivation_max_duration = 432000  # 5 days
    veto_cooldown_duration = 345600                     # 4 days
    rage_quit_extension_period_duration = 604800        # 7 days
    rage_quit_eth_withdrawals_min_delay = 2592000       # 30 days
    rage_quit_eth_withdrawals_max_delay = 15552000      # 180 days
    rage_quit_eth_withdrawals_delay_growth = 1296000    # 15 days

    # ======================
    # EMERGENCY PROTECTED TIMELOCK CONFIG
    # ======================

    [timelock]
    after_submit_delay = 259200                         # 3 days
    after_schedule_delay = 259200                       # 3 days

    [timelock.sanity_check_params]
    min_execution_delay = 300                           # 5 minutes
    max_after_submit_delay = 3888000                    # 45 days
    max_after_schedule_delay = 3888000                  # 45 days
    max_emergency_mode_duration = 31536000              # 365 days
    max_emergency_protection_duration = 31536000        # 1 year

    [timelock.emergency_protection]
    emergency_mode_duration = 15552000                  # 180 days
    emergency_protection_end_date = 1765200000          # Mon, 08 Dec 2025 13:20:00 GMT+0000
    emergency_governance_proposer = "<address>"
    emergency_activation_committee = "<address>"
    emergency_execution_committee = "<address>"

    # ======================
    # TIEBREAKER CONFIG
    # ======================

    [tiebreaker]
    quorum = 1
    committees_count = 3
    execution_delay = 2592000                           # 30 days

    [[tiebreaker.committees]] 
    quorum = 1
    members = ["<address>"]

    [[tiebreaker.committees]] 
    quorum = 1
    members = ["<address>"]

    [[tiebreaker.committees]] 
    quorum = 1
    members = ["<address>"]
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

    a. Open the DualGovernance contracts deployment artifact file (`deploy-artifact-<chain_name>-<timestamp>.toml` in the `deploy-artifacts` folder) and look for `escrow_master_copy` and `dual_governance` addresses in the `deployed_contracts` section.

    b. Run Etherscan verification (for example on a Holesky testnet)

    ```
    forge verify-contract --chain holesky --verifier-url https://api-holesky.etherscan.io/api --watch --constructor-args $(cast abi-encode "Escrow(address,address,address,address,uint256,uint32)" <st_eth address> <wst_eth address> <withdrawal_queue address> <dual_governance address> <min_withdrawals_batch_size> <max_min_assets_lock_duration>) <escrow_master_copy address> contracts/Escrow.sol:Escrow
    ```

### Running the verification script

1. Set up the required env variables in the .env file

    ```
    DEPLOY_ARTIFACT_FILE_NAME=... (in the `deploy-artifacts` folder, for example: "deploy-artifact-<chain_name>-<timestamp>.toml")
    ```

2. The deployed addresses list TOML file should be produced by the deployment script, and should contain the section `deployed_contracts` with all the required values:

    ```toml
    [deployed_contracts]
    admin_executor = "<address>"
    dual_governance = "<address>"
    dual_governance_config_provider = "<address>"
    emergency_governance = "<address>"
    escrow_master_copy = "<address>"
    reseal_manager = "<address>"
    tiebreaker_core_committee = "<address>"
    tiebreaker_sub_committees = [
        "<address>",
        "<address>",
        "<address>",
    ]
    timelock = "<address>"
    ```

3. Run the script (with the local Anvil as an example)

    ```
    forge script scripts/deploy/Verify.s.sol:Verify --fork-url http://localhost:8545
    ```

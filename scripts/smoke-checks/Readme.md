### Deploying

    With the local fork (Anvil):
    ```
    forge script scripts/smoke-checks/DeployAragonRolesVerifier.s.sol:DeployAragonRolesVerifier --fork-url http://localhost:8545 --broadcast --account Deployer1 --sender <DEPLOYER1_ADDRESS> --verify
    ```

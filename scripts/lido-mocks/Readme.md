# Lido contracts mocks for Dual Governance testing on Holesky

### Deploying

    With the local fork (Anvil):
    ```
    forge script scripts/lido-mocks/DeployHoleskyLidoMocks.s.sol:DeployHoleskyLidoMocks --fork-url http://localhost:8545 --broadcast --account Deployer1
    ```

    On a testnet (with Etherscan verification):
    ```
    forge script scripts/lido-mocks/DeployHoleskyLidoMocks.s.sol:DeployHoleskyLidoMocks --fork-url https://holesky.infura.io/v3/<YOUR_API_KEY> --broadcast --account Deployer1 --verify
    ```
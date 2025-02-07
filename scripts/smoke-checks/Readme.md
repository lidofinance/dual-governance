### Deploying LidoRolesValidator

    With the local fork (Anvil):
    ```
    forge script scripts/smoke-checks/holesky-dry-run/DeployHoleskyMocksLidoRolesValidator.s.sol:DeployHoleskyMocksLidoRolesValidator --fork-url http://localhost:8545 --broadcast --account Deployer1
    ```

    On a testnet (with Etherscan verification):
    ```
    forge script scripts/smoke-checks/holesky-dry-run/DeployHoleskyMocksLidoRolesValidator.s.sol:DeployHoleskyMocksLidoRolesValidator --fork-url https://holesky.infura.io/v3/<YOUR_API_KEY> --broadcast --account Deployer1 --verify
    ```

### Deploying DGLaunchVerifier

    With the local fork (Anvil):
    ```
    forge script scripts/smoke-checks/holesky-dry-run/DeployHoleskyMocksDGLaunchVerifier.s.sol:DeployHoleskyMocksDGLaunchVerifier --fork-url http://localhost:8545 --broadcast --account Deployer1
    ```

    On a testnet (with Etherscan verification):
    ```
    forge script scripts/smoke-checks/holesky-dry-run/DeployHoleskyMocksDGLaunchVerifier.s.sol:DeployHoleskyMocksDGLaunchVerifier --fork-url https://holesky.infura.io/v3/<YOUR_API_KEY> --broadcast --account Deployer1 --verify
    ```

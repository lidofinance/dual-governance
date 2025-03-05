# Lido Dual Governance contracts

**WARNING**: this code is an early draft and is not functional yet.

See [this research forum discussion](https://research.lido.fi/t/ldo-steth-dual-governance-continuation/5727) for the relevant context.

## Setup

This project uses NPM for dependency management and Forge for tests so you'll need to have Node.js, NPM, and Foundry installed.

* Install NVM https://github.com/nvm-sh/nvm/blob/master/README.md#install--update-script

* Install specific Node.js version
    ```sh
    nvm install
    ```

* Install the dependencies:
    ```sh
    npm ci
    ```

* Install Foundry and `forge` https://book.getfoundry.sh/getting-started/installation

* Install Foundry v1.0.0 
    ```sh
    foundryup -i 1.0.0
    ```

* Create `.env` file
    ```sh
    cp .env.example .env
    ```

    and specify there your `MAINNET_RPC_URL`.

    > **_NOTE:_**  You may need to specify manually maximum allowed requests per second (rps) value for an API key/RPC url for some providers. In our experience max 100 rps will be enough to run tests.

## Running tests

```sh
forge test
```

## Test coverage HTML report generation

1. Install `lcov` package in your OS
    ```sh
    brew install lcov
    
    -OR-

    apt-get install lcov
    ```
2. Run
    ```sh
    npm run cov-report
    ```
3. Open `./coverage-report/index.html` in your browser.

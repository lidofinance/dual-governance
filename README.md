# Lido Dual Governance contracts

**WARNING**: this code is an early draft and is not functional yet.

See [this research forum discussion](https://research.lido.fi/t/ldo-steth-dual-governance-continuation/5727) for the relevant context.

## Setup

This project uses NPM for dependency management and Forge for tests so you'll need to have Node.js, NPM, and Foundry installed.

* Install NVM https://github.com/nvm-sh/nvm/blob/master/README.md#install--update-script

* Install specific Node.js version
    ```
    nvm install
    ```

* Installing the dependencies:
    ```sh
    npm ci
    ```
* Install Foundry and `forge` https://book.getfoundry.sh/getting-started/installation

## Running tests

```sh
forge test
```

## Test coverage HTML report generation

1. Install `lcov` package in your OS
    ```
    brew install lcov
    or
    apt-get install lcov
    ```
2. Run
    ```
    npm run cov-report
    ```
3. Open `./coverage-report/index.html` in you browser.

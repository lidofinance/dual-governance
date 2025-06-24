# Lido Dual Governance Smart Contracts

![image](./dg-banner.png)

This repository contains the source code for the smart contracts implementing the Lido Dual Governance mechanism.

The Dual Governance mechanism (DG) is an iteration on the protocol governance that gives stakers a say by allowing them to block DAO decisions and providing a negotiation device between stakers and the DAO.

Another way of looking at dual governance is that it implements:
1. A dynamic user-extensible timelock on DAO decisions
2. A rage quit mechanism for stakers that takes into account the specifics of how Ethereum withdrawals work

The detailed description of the system can be found in:
- [Mechanics Design](./docs/mechanism.md)
- [Specification](./docs/specification.md)


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

    and specify there your `MAINNET_RPC_URL` and `HOLESKY_RPC_URL`.

    > **_NOTE:_**  You may need to specify manually maximum allowed requests per second (rps) value for an API key/RPC url for some providers. In our experience max 100 rps will be enough to run tests.


## Running Tests

This repository contains different sets of tests written using the Foundry framework:

- **Unit tests** - Basic tests that cover each module in isolation. This is the most comprehensive set of tests, covering every edge case and aspect of the code.

- **Integration tests** - Tests that verify how contracts work in a forked environment using the real state of the protocol. These tests are split into two subcategories:
    - **Scenario tests** - Usually edge cases that demonstrate how the system behaves under very specific conditions. These tests use fresh deployments of the DG contracts (and forked Lido contract state) to prepare the system state for concrete scenarios.
    - **Regression tests** - Integration tests that can be launched on forked instances of the DG contracts. These tests verify the required functionality of the system and ensure everything works exactly as expected. This category contains two special tests: 
        1) A [test for complete rage quit](./test/regressions/complete-rage-quit.t.sol) of the majority of real stETH and wstETH holders. 
        2) A special [solvency test](./test/regressions/dg-solvency-simulation.t.sol) that simulates protocol operation under conditions with serial Rage Quits. 
    
            Both tests may require significant time to complete, so they are not expected to be run frequently, in contrast to regular regression tests which can be run daily to verify the system works correctly.

The following commands can be used to run different types of tests:

- **Run unit tests exclusively**
    ```sh
    npm run test:unit
    ```

- **Run integration and regression tests on a newly deployed setup of the Dual Governance**
    ```sh
    npm run test:integration
    ```

- **Run only scenario tests on a newly deployed setup of the Dual Governance**
    ```sh
    npm run test:scenario
    ```

- **Run regression tests on a forked setup of the Dual Governance**
    ```sh
    npm run test:regressions
    ```

- **Run solvency test exclusively on a forked setup of Dual Governance** _(Note: test is very time consuming)_
    ```sh
    npm run test:solvency-simulation
    ```
    > **_NOTE:_** Use flag `--load-accounts` to update list of stETH and wstETH holders before the test:
    >```sh
    >npm run test:solvency-simulation -- --load-accounts
    >```

- **Run complete rage quit test exclusively on a forked setup of Dual Governance** _(Note: test is very time consuming)_
    ```sh
    npm run test:complete-rage-quit
    ```
    >**_NOTE:_** Use flag `--load-accounts` to update list of stETH and wstETH holders before the test:
    >```sh
    >npm run test:complete-rage-quit -- --load-accounts
    >```

- **Run all types of tests**
    ```sh
    npm run test
    ```

>[!NOTE]
>Make sure that the required environment variables are set before running tests.

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

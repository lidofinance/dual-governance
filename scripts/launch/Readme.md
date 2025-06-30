### Launch acceptance tests
Specify the env variable `FROM_STEP` value in the .env file

```
FROM_STEP=0
```


Launch acceptance tests with the local fork (Anvil):

```
forge script scripts/launch/LaunchAcceptance.s.sol:LaunchAcceptance --fork-url http://localhost:8545 -vvvv
```

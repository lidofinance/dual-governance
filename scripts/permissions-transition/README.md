# Permissions Transition Scripts

These scripts generate a permissions transition plan for the Lido protocol, based on the network-specific permissions configuration (see the `./config` folder).

The generation is based on both historical events and the protocol state at a given snapshot block.

## Script Requirements

To run the scripts, make sure to install all dependencies as described in the [setup instructions](../../README.md#setup).

Event collection requires access to a historical or archive RPC node. The RPC URL must be set via environment variables depending on the network:

- `MAINNET_RPC_URL`
- `HOLESKY_RPC_URL`
- `HOODI_RPC_URL`

## Transition Plan Formatting

To generate the permissions transition plan, run the following command:

```
export NETWORK=<NETWORK_ENV> && npx ts-node ./scripts/permissions-transition/generate-transition-plan.ts
```

> Note: Make sure the `<NETWORK_NAME>_RPC_URL` environment variable is set and that the `./events/<NETWORK_NAME>.json` file exists.

The resulting file will be stored in:

```
./transition-plans/${NETWORK_NAME}-${SNAPSHOT_BLOCK_NUMBER}.md
```

Where `SNAPSHOT_BLOCK_NUMBER` is the latest block number used during event collection.

## Events Collecting

To collect new events required for the generating of the transition plan, run the following command:

```
export NETWORK=<NETWORK_ENV> && npx ts-node ./scripts/permissions-transition/collect-events.ts
```

> Note: Make sure the `<NETWORK_NAME>_RPC_URL` environment variable is set before launching the script.

Event collection may take some time.

To avoid restarting from the beginning each time, a snapshot of collected events is stored in the `./events` folder. When the script runs, it will resume collecting from the block after the last one saved in `./events/<NETWORK_NAME>.json`.

To start event collection without cache, delete the corresponding file from the `./events` folder. The process will then start from the genesis block defined in the `./config/<NETWORK_NAME>.json` config.

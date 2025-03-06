FROM ghcr.io/foundry-rs/foundry:nightly-a0a002020be4c40946fe122fe6ff752b21cb2885 as FOUNDRY

FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu-22.04

COPY --from=FOUNDRY /usr/local/bin/forge /usr/local/bin/forge
COPY --from=FOUNDRY /usr/local/bin/anvil /usr/local/bin/anvil
COPY --from=FOUNDRY /usr/local/bin/cast /usr/local/bin/cast
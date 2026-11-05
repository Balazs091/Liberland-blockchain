# Deployment Outputs

Foundry deployment scripts write network manifests into this directory. Generated `*.json` files are ignored by Git.
A simulation can also write a manifest, so verify confirmed transactions and the matching source revision before
using its addresses.

Use the guide for the selected profile: [Ethereum mainnet](../docs/Ethereum-Mainnet-Deployment.md),
[original Sepolia demo](../docs/Sepolia-Demo-Deployment.md), [governed Sepolia staging](../docs/Sepolia-Governed-Deployment.md)
or [isolated Sepolia foundation](../docs/Sepolia-Foundation-Deployment.md). Mainnet preparation remains incomplete
until the separate genesis-completion stage succeeds and setup authority is retired.

Tracked [mainnet](../frontend-export/ethereum-mainnet.example.json) and
[demo](../frontend-export/sepolia-demo.example.json) examples describe the frontend configuration shape.
Before release, verify deployed code and source, then copy the selected public manifest into the
[frontend package](../frontend-export/README.md).

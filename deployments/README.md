# Deployment Outputs

Foundry deployment scripts write network manifests into this directory. Live `*.json` files are intentionally ignored
because addresses and provenance must be regenerated from the exact deployment transaction and audit-tagged source;
do not treat a developer's local manifest as protocol authority.

The tracked schema examples live beside the frontend handoff documentation. Before a release, follow the relevant
deployment guide, verify the deployed bytecode and source, then copy only the intended public manifest into the
frontend package.

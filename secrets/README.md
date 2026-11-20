# Secrets

The secrets of the viewer. The files are committed: their values are encrypted with sops for the maintainer's age key
(`../.sops.yaml`).

| File | Key | What it is |
|---|---|---|
| `production.yaml` | `UPDATE_SIGNING_KEY` | The 32-byte Ed25519 seed of the update key, base64url (`viewertool update keygen`). Its public half is `PRODUCT.public_key` in `src/update/product.odin`. The release workflow reads it from the GitHub secret of the same name: `sops -d --extract '["UPDATE_SIGNING_KEY"]' secrets/production.yaml \| gh secret set UPDATE_SIGNING_KEY` |

# Project guidelines

## This repository is PUBLIC
Treat everything here as world-readable. Never commit or expose identifying or
sensitive data — Azure subscription IDs, tenant IDs, client/service-principal
IDs, object IDs, full resource IDs, license/account keys, SAS tokens,
connection strings, etc.

When adding new inputs:
- **GitHub Actions**: identifying or sensitive values go in **secrets**
  (`${{ secrets.X }}`), never in Actions **variables** (`${{ vars.X }}`), which
  are not protected. Reference secrets from the workflow only.
- **Terraform**: never hardcode such values in `.tf`, `.tfvars`, or scripts —
  take them as variables fed from CI secrets, and mark them `sensitive = true`.
- **Secrets consumed by Azure resources**: store in Key Vault and reference them
  (e.g. function app settings via `@Microsoft.KeyVault(SecretUri=...)`), not as
  plaintext app settings.

## Commits
- Keep commit messages brief.
- Do NOT add a `Co-authored-by` trailer.

## Terraform style
- Prefer explicit resource blocks over `for_each`/`count` loops driven by
  `locals`/maps when the count is modest (roughly ≤10 resources) — explicit
  resources read and review more clearly here. Creating ~10 distinct resources
  longhand is fine and preferred over a clever loop.
- Reserve loops for large, genuinely homogeneous sets.

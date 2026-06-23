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

## Comments
- Do NOT write comments unless they are extremely necessary. The default is no
  comment at all.
- Make the code self-explanatory through clear names and obvious structure
  instead of explaining it with a comment.
- Never write a comment that restates what the code already says.
- A comment is justified only when the code is genuinely surprising, looks wrong
  but is correct, or encodes a non-obvious external constraint that can't be made
  clear in code. In that rare case, keep it to a single short line.
- Multi-line comment blocks are essentially never acceptable.

## Resource naming
All Azure resources follow the Azure standard
`<resource-type-abbreviation>-<app/workload>-<location-short>-<instance>` —
e.g. `kv-sops-neu-001`, `asp-asn-neu-001`, `func-asn-neu-001`.
- Use the CAF resource-type abbreviation (kv, st, asp, func, appi, law, …) and a
  numbered instance (`001`, `002`, …), not a random suffix.
- Storage accounts are the exception (no hyphens, ≤24 chars): `st<app><loc><nn>`.
- Globally-unique names (Key Vault, storage) rely on the app/workload token being
  unique within the tenant.

## Terraform style
- Prefer explicit resource blocks over `for_each`/`count` loops driven by
  `locals`/maps when the count is modest (roughly ≤10 resources) — explicit
  resources read and review more clearly here. Creating ~10 distinct resources
  longhand is fine and preferred over a clever loop.
- Reserve loops for large, genuinely homogeneous sets.

## azapi / Azure REST API
- When building resources with the `azapi` provider, the Azure REST API reference
  is the authoritative schema for the request `body` — which fields exist and
  which are actually required. Use it instead of guessing or relying on prose
  docs (the two can disagree; the REST API model wins).
- For Microsoft Sentinel resources, start from the operation groups index:
  https://learn.microsoft.com/rest/api/securityinsights/operation-groups

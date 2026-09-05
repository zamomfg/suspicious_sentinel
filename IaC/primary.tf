# The primary Sentinel workspace lives in Sweden Central (law-log-sc-001). All
# workspace-scoped resources target it and are named with the "sc" short code.
# law-log-neu-001 (log.tf) is kept as an empty, onboarded secondary. The SOPS
# key vault and the ASN enrichment stack deliberately stay on neu (see sops.tf /
# asn_enrichment.tf) so encrypted watchlists keep decrypting and the function app
# is not recreated.
locals {
  primary_location       = "swedencentral"
  primary_location_short = "sc"
}

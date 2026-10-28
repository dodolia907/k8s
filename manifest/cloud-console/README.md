# cloud-console

Source: github.com/dodolia907/cloud (private). Image: ghcr.io/dodolia907/cloud-console (private).

This repository is public, so the following are created by hand in the `cloud-console`
namespace and are not managed by Argo CD:

- ConfigMap `cloud-console-regions` (key `regions.yaml`: real addresses and OCIDs)
- ConfigMap `cloud-console-env` (`CF_ACCESS_TEAM_DOMAIN`, `CF_ACCESS_AUD`, `ALLOWED_EMAILS`)
- Secret `cloud-console-credentials` (`<credentialsRef>.<field>`)
- Secret `ghcr-pull` (docker-registry, PAT with read:packages)

The console does not start until `cloud-console-env` has the Access settings.

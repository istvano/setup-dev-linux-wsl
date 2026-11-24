# Infrastructure-as-code tooling shared by every cloud provider. Opt-in. Provider CLIs
# live in cloud-aws and cloud-azure; there is no cloud-gcp yet (see TASKS.md).
#
# Host placement: these are stateless single binaries invoked interactively against
# working trees, so the container boundary would only add a bind mount.
#
# Every formula below was checked for an x86_64_linux bottle in homebrew-core (ADR-010).
brew "opentofu"       # Open-source infrastructure-as-code provisioning CLI.
brew "terraform-docs" # Generates module documentation from OpenTofu/Terraform sources.
brew "terragrunt"     # Keeps multi-environment OpenTofu configuration DRY across stacks.

# packer and vault are deliberately absent: both left homebrew-core after HashiCorp's
# BSL relicensing and would require a third-party tap, which profiles never use.

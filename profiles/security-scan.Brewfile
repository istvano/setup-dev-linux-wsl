# Single-binary scanners kept on the host for interactive, ad-hoc inspection.
# Opt-in: none of these is needed daily, and each overlaps something in the default
# profiles or is used occasionally (ADR-008, one tool per job).
#
# Repeatable, CI-equivalent scanning belongs in each project's own containers. These are
# on the host as well because each is a single static binary with no daemon, no
# persistent state and no privileged access, and because the interactive use case is
# inspecting an artefact before deciding to trust it.
#
# Every formula below was checked for an x86_64_linux bottle in homebrew-core (ADR-010).
brew "syft"        # Generates an SBOM for an image, directory or archive.
brew "grype"       # Matches an SBOM or image against vulnerability data.
brew "osv-scanner" # Checks lockfiles against the OSV vulnerability database.
brew "trufflehog"  # Verifies discovered credentials rather than only pattern-matching them.
brew "dive"        # Inspects container image layers and wasted space.
brew "cosign"      # Verifies (and creates) signatures and attestations on images and blobs.
brew "nmap"        # Port and service discovery for hosts you are authorised to scan.

# trivy and hadolint live in profiles/dev.Brewfile: scanning an image and linting a
# Dockerfile are part of authoring, not a specialist activity.

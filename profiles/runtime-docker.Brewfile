# runtime-docker profile.
#
# Docker Engine (docker-ce, buildx, compose) comes from Docker's signed apt repository,
# installed by script/apt-vendor (apt/vendor.list, ADR-003), not by Homebrew. Only the
# daemonless client-side helper below is a formula: it needs no daemon and no privilege.
brew "skopeo"  # Inspect and copy container images between registries without a daemon.

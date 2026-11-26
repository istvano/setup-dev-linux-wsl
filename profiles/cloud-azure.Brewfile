# Azure tooling for interactive sessions. Opt-in.
#
# azure-cli is deliberately absent from this file: in homebrew-core it is a macOS-only cask (its
# download is the macos-arm64 tarball), so there is no Linux formula. It arrives with
# Microsoft's signed apt repository, installed by script/apt-vendor (apt/vendor.list).
# kubelogin does not depend on it: it is a standalone Go binary that works with kubectl.
#
# Verified for an x86_64_linux bottle in homebrew-core (ADR-010).
brew "kubelogin" # Entra ID (Azure AD) credential plugin for kubectl against AKS.

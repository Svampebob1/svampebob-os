# Svampebob-os &nbsp; [![bluebuild build badge](https://github.com/svampebob1/svampebob-os/actions/workflows/build.yml/badge.svg)](https://github.com/svampebob1/svampebob-os/actions/workflows/build.yml)

Svampebob-os based on Universal Blue with two variants.
The project contains the packages I need for running my build of SwayVM.

## Installation
### Bluefin

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/svampebob1/svampebob-os-bluefin:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/svampebob1/svampebob-os-bluefin:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.


### Bazzite

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/svampebob1/svampebob-os-bazzite:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/svampebob1/svampebob-os-bazzite:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.

## ISO

```
sudo bluebuild generate-iso --iso-name svampebob-os-bluefin.iso image ghcr.io/svampebob1/svampebob-os-bluefin
sudo bluebuild generate-iso --iso-name svampebob-os-bazzite.iso image ghcr.io/svampebob1/svampebob-os-bazzite
```

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/svampebob1/svampebob-os
```

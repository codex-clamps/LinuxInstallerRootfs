#!/usr/bin/env bash
# Full GUI rootfs provisioner for Fedora 40 Workstation (GNOME desktop, GDM).
# Runs inside the build container as root; the base image is fedora:40.
set -euo pipefail

dnf install --assumeyes --setopt=install_weak_deps=False \
  glibc-langpack-en \
  kernel \
  kernel-core \
  kernel-modules \
  kernel-modules-extra \
  linux-firmware \
  dracut \
  dracut-config-generic \
  @workstation-product-environment \
  mesa-vulkan-drivers \
  NetworkManager-wifi \
  grub2-efi-x64 \
  grub2-tools \
  grub2-tools-extra \
  shim-x64 \
  os-prober \
  pipewire-pulseaudio \
  wireplumber

# Fedora keeps its GRUB config in /boot/grub2; expose it under /boot/grub
# so the installer's UEFI forwarding stub finds it
mkdir -p /boot/grub2
ln -sfn grub2 /boot/grub

systemctl set-default graphical.target
systemctl enable gdm NetworkManager 2>/dev/null || true
systemctl disable gnome-initial-setup.service 2>/dev/null || true
systemctl disable gnome-initial-setup-first-login.service 2>/dev/null || true

# Generate the initramfs for each installed kernel explicitly; a bare
# dracut --force would pick up the host's uname -r inside the container
for kernel_directory in /lib/modules/*/; do
  [[ -d "${kernel_directory}" ]] || continue
  dracut --force --no-hostonly --kver "$(basename "${kernel_directory}")"
done

dnf clean all
rm -rf /var/cache/* /var/log/*

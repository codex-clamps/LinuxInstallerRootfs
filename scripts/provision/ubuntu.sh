#!/usr/bin/env bash
# Full GUI rootfs provisioner for Ubuntu 24.04 LTS (GNOME desktop, GDM3).
# Runs inside the build container as root; the base image is ubuntu:24.04.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install --yes --no-install-recommends \
  locales \
  ca-certificates \
  linux-generic \
  linux-firmware \
  initramfs-tools \
  ubuntu-desktop-minimal \
  gdm3 \
  plymouth \
  plymouth-theme-spinner \
  mesa-vulkan-drivers \
  mesa-va-drivers \
  network-manager \
  netplan.io \
  grub-efi-amd64-signed \
  grub-efi-amd64-bin \
  grub-common \
  grub-pc-bin \
  os-prober \
  pipewire \
  pipewire-pulse \
  pipewire-alsa \
  wireplumber

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# The desktop must come up with NetworkManager owning the devices
cat > /etc/netplan/10-lifw-networkmanager.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
chmod 600 /etc/netplan/10-lifw-networkmanager.yaml

systemctl set-default graphical.target
systemctl enable gdm3 NetworkManager 2>/dev/null || true

# The installer-created user logs in directly; no first-boot wizard
apt-get purge --yes gnome-initial-setup 2>/dev/null || true
apt-get autoremove --yes 2>/dev/null || true

update-initramfs -c -k all

apt-get clean
rm -rf /var/lib/apt/lists/*

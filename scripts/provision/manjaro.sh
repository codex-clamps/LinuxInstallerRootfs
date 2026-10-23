#!/usr/bin/env bash
# Full GUI rootfs provisioner for Manjaro Rolling (XFCE flagship, LightDM).
# Runs inside the build container as root; the base image is manjarolinux/base:latest.
set -euo pipefail

pacman-key --init 2>/dev/null || true
pacman-key --populate archlinux manjaro 2>/dev/null || true

pacman -Syu --noconfirm --needed bash ca-certificates

# Pick the newest Manjaro LTS kernel the mirrors actually provide
kernel_package=""
for candidate in linux612 linux66 linux61; do
  if pacman -Si "${candidate}" >/dev/null 2>&1; then
    kernel_package="${candidate}"
    break
  fi
done
[[ -n "${kernel_package}" ]] || { echo ">>> No supported Manjaro kernel found in the mirrors" >&2; exit 1; }
echo ">>> Provisioning Manjaro XFCE with kernel ${kernel_package}..."

pacman -S --noconfirm --needed \
  "${kernel_package}" \
  linux-firmware \
  mkinitcpio \
  xfce4 \
  xfce4-goodies \
  manjaro-xfce-settings \
  xorg-server \
  mesa \
  xf86-video-fbdev \
  xf86-video-vesa \
  vulkan-intel \
  vulkan-radeon \
  lightdm \
  lightdm-gtk-greeter \
  lightdm-gtk-greeter-settings \
  pipewire \
  pipewire-pulse \
  pipewire-alsa \
  wireplumber \
  networkmanager \
  network-manager-applet \
  grub \
  os-prober \
  efibootmgr \
  dosfstools \
  mtools

systemctl set-default graphical.target
systemctl enable lightdm NetworkManager 2>/dev/null || true

mkinitcpio -P

pacman -Scc --noconfirm || true
rm -rf /var/cache/* /var/log/*

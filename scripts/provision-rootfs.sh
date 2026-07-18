#!/bin/sh
set -eu

export PATH=/sbin:/bin:/usr/sbin:/usr/bin

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install --yes --no-install-recommends \
    bash \
    ca-certificates \
    dbus \
    network-manager \
    passwd \
    sudo \
    systemd-sysv
  apt-get clean
  rm -rf /var/lib/apt/lists/*
elif command -v dnf >/dev/null 2>&1; then
  dnf install --assumeyes \
    bash \
    ca-certificates \
    dbus \
    NetworkManager \
    passwd \
    shadow-utils \
    sudo \
    systemd
  dnf clean all
elif command -v pacman >/dev/null 2>&1; then
  pacman -Syu --noconfirm \
    bash \
    ca-certificates \
    dbus \
    networkmanager \
    shadow \
    sudo \
    systemd
  pacman -Scc --noconfirm || true
else
  echo "Unsupported rootfs package manager" >&2
  exit 1
fi

mkdir -p /boot/grub /etc/systemd/system
ln -sfn /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target
systemctl enable NetworkManager 2>/dev/null || true
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id

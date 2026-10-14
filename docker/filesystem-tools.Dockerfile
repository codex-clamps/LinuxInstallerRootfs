FROM alpine:3.22

RUN apk add --no-cache \
    bash \
    btrfs-progs \
    coreutils \
    dosfstools \
    e2fsprogs \
    findutils \
    gptfdisk \
    sgdisk \
    grub \
    grub-efi \
    jq \
    os-prober \
    parted \
    shadow \
    tar \
    util-linux \
    zstd

COPY installer/install.sh /opt/linux-installer/install.sh
COPY installer/post-setup.sh /opt/linux-installer/post-setup.sh

RUN chmod 0755 \
    /opt/linux-installer/install.sh \
    /opt/linux-installer/post-setup.sh

LABEL org.opencontainers.image.title="LinuxInstallerForWindows filesystem and shell tools"
LABEL org.opencontainers.image.description="Bash installer userspace for EXT4, Btrfs, GPT, rootfs extraction, and GRUB post-setup"

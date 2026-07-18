FROM alpine:3.22

RUN apk add --no-cache \
    busybox \
    kmod \
    linux-lts \
    tar \
    util-linux \
    zstd

COPY installer/init /init
RUN chmod 0755 /init

LABEL org.opencontainers.image.title="LinuxInstallerForWindows boot runtime"
LABEL org.opencontainers.image.description="Kernel initramfs that launches the verified installer shell toolchain"

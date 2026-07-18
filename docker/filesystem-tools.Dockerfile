FROM alpine:3.22

RUN apk add --no-cache     bash     btrfs-progs     e2fsprogs     util-linux

LABEL org.opencontainers.image.title="LinuxInstallerForWindows filesystem tools"
LABEL org.opencontainers.image.description="Minimal EXT4 and Btrfs installer userspace"

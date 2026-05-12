#!/bin/sh
# Build x86 emulator kernel image

ARCH=x86_64 make tizen_emul_defconfig
sed -i "s/^EXTRAVERSION.*/EXTRAVERSION = -x86_64/" Makefile
./scripts/config --set-str CONFIG_INITRAMFS_SOURCE ramfs/initramfs.x86_64 -e CONFIG_CRYPTO_AES_X86_64
ARCH=x86_64 CROSS_COMPILE='' make -j8

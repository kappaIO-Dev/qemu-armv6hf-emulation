#!/bin/bash
#
# Build ARM kernel 4.1.7 for QEMU Raspberry Pi Emulation
#
#######################################################

set -ex

#sudo apt-get update && sudo apt-get install git libncurses5-dev gcc-arm-linux-gnueabihf
#git clone https://github.com/raspberrypi/linux.git
[ ! -d tools ] && git clone https://github.com/raspberrypi/tools
[ -d linux ] && rm -rf linux
git clone https://github.com/raspberrypi/linux.git

TOOLCHAIN=arm-linux-gnueabihf
PATH=$PATH:$(readlink -m ./tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin)
CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
[ "$CPUS" -lt 1 ] && CPUS=1
cd linux
#checking out 4.1.7+ branch, see https://github.com/raspberrypi/linux/commits/rpi-4.1.y
git checkout 77798915750db46f10bb449e1625d6368ea42e25
patch -p1 -d ./ < ../linux-arm.patch
make ARCH=arm versatile_defconfig
cat >> .config << EOF
CONFIG_CROSS_COMPILE="$TOOLCHAIN"
CONFIG_CPU_V6=y
CONFIG_ARM_ERRATA_411920=y
CONFIG_ARM_ERRATA_364296=y
CONFIG_AEABI=y
CONFIG_OABI_COMPAT=y
CONFIG_PCI=y
CONFIG_SCSI=y
CONFIG_SCSI_SYM53C8XX_2=y
CONFIG_BLK_DEV_SD=y
CONFIG_BLK_DEV_SR=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TMPFS=y
CONFIG_INPUT_EVDEV=y
CONFIG_EXT3_FS=y
CONFIG_EXT4_FS=y
CONFIG_VFAT_FS=y
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_ISO8859_1=y
CONFIG_FONT_8x16=y
CONFIG_LOGO=y
CONFIG_VFP=y
CONFIG_CGROUPS=y
CONFIG_8139CP=y
CONFIG_8139TOO=y
CONFIG_R8169=y
CONFIG_SQUASHFS=y
EOF

make -j$CPUS -k ARCH=arm CROSS_COMPILE=${TOOLCHAIN}- menuconfig
make -j$CPUS -k ARCH=arm CROSS_COMPILE=${TOOLCHAIN}- bzImage
cd ..
[ -z "$OUTDIR" ] && OUTDIR=./
cp linux/arch/arm/boot/zImage $OUTDIR

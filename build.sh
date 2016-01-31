#! /bin/sh
export OUTDIR=$(readlink -m emulation)
cd kernel 
./build-kernel.sh
cd ..
cd rootfs
./build-rootfs.sh
cd ..

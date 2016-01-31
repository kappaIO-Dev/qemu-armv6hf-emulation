#!/bin/bash

# Boot the emulated system to a shell prompt.

if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root\n"
  exit 1
fi

set -ex
ARCH=armv6l
#RAW_IMG=$(readlink -m jessie.img)
RAW_IMG=$(readlink -m "$1")
work=work
NBD_DEV=/dev/nbd0
rootfs=rootfs
SSH_KEY=$(readlink -m qemu_arm_key)
SSH_PORT=22000
SSH_USER=root
SSH_ADDR=localhost
QEMU_ROOTFS=$(readlink -m qemu_rootfs.sqf)
QEMU_KERNEL=$(readlink -m zImage)
chroot=/sbin/chroot

attach_image_to_nbd() {
  # use -v as we seem to have problems otherwise...
  sudo qemu-nbd --nocache -v -c $2 $1 &
  sleep 5
}

detach_image_from_nbd() {
  sudo qemu-nbd -d $1
}

ssh_in_to_qemu() {
  ssh -i $SSH_KEY -p 22000 -lroot localhost "$@"
}
shutdown_qemu() {
  ssh_in_to_qemu "sync && umount -a" || true
  echo "exit" > fifo.in
  sleep 5
  if [ -e qemu.pid ]; then
    QEMU_PID=$(cat qemu.pid)
    while [ -n "$QEMU_PID" ]; do 
      set +e
      kill -0 $QEMU_PID 2>/dev/null
      if [ $? -eq 0 ]; then
        printf "Qemu pid %s not finished yet. Waiting\n" "$QEMU_PID"
        sleep 1
      else
        QEMU_PID=""
      fi
      set -e
    done
  fi
  rm fifo.in
  rm fifo.out
#  sleep 15
}
mount_apt_cache() {
  ssh_in_to_qemu "mount -o noatime /dev/sdc /mnt/var/cache/apt"

}
install_packages() {
  # we may want to break out DEBIAN_FRONTEND=noninteractive
  ssh_in_to_qemu $chroot /mnt sh -l -ex - <<EOF
dpkg --configure -a
apt-get update
apt-get install -y apache2 php5 libapache2-mod-php5
#apt-get install php5
#apt-get install libapache2-mod-php5
EOF
}

disable_starting_services() {
  ssh_in_to_qemu $chroot /mnt sh -ex - <<EOF
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
EOF
}

allow_starting_services() {
  ssh_in_to_qemu $chroot /mnt sh -ex - <<EOF
rm /usr/sbin/policy-rc.d
EOF
}

CONSOLE="-serial pipe:fifo $'\046'"

run_qemu()
{
  rm fifo.out fifo.in || true
  mkfifo fifo.out fifo.in
  chmod 0666 fifo.in
  [ ! -z "$DEBUG" ] && set -x
  qemu-system-arm -M versatileab -m 256 -cpu arm1176 -nographic -no-reboot -kernel $QEMU_KERNEL \
  -hda $QEMU_ROOTFS \
  -append "root=/dev/sda init=/sbin/init.sh rw panic=1 console=ttyAMA0 HOST=armv6l $KERNEL_EXTRA" $1 \
  -net nic,model=rtl8139 -net user -redir tcp:22000::22 -pidfile qemu.pid -serial pipe:fifo &
  sleep 10
}

tty_run_qemu()
{
  rm fifo.out fifo.in || true
  mkfifo fifo.out fifo.in
  chmod 0666 fifo.in
  [ ! -z "$DEBUG" ] && set -x
  qemu-system-arm -M versatileab -m 256 -cpu arm1176 -nographic -no-reboot -kernel $QEMU_KERNEL \
  -hda $QEMU_ROOTFS \
  -append "root=/dev/sda init=/sbin/init.sh rw panic=1 console=ttyAMA0 HOST=armv6l $KERNEL_EXTRA" $1 \
  -net nic,model=rtl8139 -net user -redir tcp:22000::22 -pidfile qemu.pid
}

# mount the rootfs partition
disable_ld_so_preload() {
 [ ! -d $rootfs ] && mkdir $rootfs
 sudo umount $rootfs || true
 sudo qemu-nbd -d $NBD_DEV
 sudo qemu-nbd --nocache -v -c $NBD_DEV $QED_IMG &
 sleep 1
 sudo mount "$NBD_DEV"p2 $rootfs 
 if [ -f $rootfs/etc/ld.so.preload ]
 then
   mv $rootfs/etc/ld.so.preload $rootfs/etc/ld.so.preload.disable
 else
   echo "ld.so.preload is missing, check the image."
 fi
 sudo umount $rootfs
 sudo qemu-nbd -d $NBD_DEV
}
enable_ld_so_preload() {
 [ ! -d $rootfs ] && mkdir $rootfs
 sudo umount $rootfs || true
 sudo qemu-nbd -d $NBD_DEV
 sudo qemu-nbd --nocache -v -c $NBD_DEV $QED_IMG &
 sleep 1
 sudo mount "$NBD_DEV"p2 $rootfs 
 if [ -f $rootfs/etc/ld.so.preload.disable ]
 then
   mv $rootfs/etc/ld.so.preload.disable $rootfs/etc/ld.so.preload
 else
   echo "ld.so.preload.disable is missing, check the image."
 fi
 sudo umount $rootfs
 sudo qemu-nbd -d $NBD_DEV
}

setup_wifi() {
WIFI_CRN=$(cat <<\EOF
 network={
    ssid="YOURWIFISSID"
    psk="YOURWIFIPASSWORD"
 }
EOF
)

 [ ! -d $rootfs ] && mkdir $rootfs
 sudo umount $rootfs || true
 sudo qemu-nbd -d $NBD_DEV
 sudo qemu-nbd --nocache -v -c $NBD_DEV $QED_IMG &
 sleep 1
 sudo mount "$NBD_DEV"p2 $rootfs
sleep 1 
 res=$(printf "%s" $(cat rootfs/etc/wpa_supplicant/wpa_supplicant.conf | grep "$WIFI_CRN"))
 [ -z $res ] && printf "%s" "$WIFI_CRN" >> rootfs/etc/wpa_supplicant/wpa_supplicant.conf
 [ ! -z $res ] && echo "credential exists" 
# echo "$res"
# if [ ! -z "$res" ]
# then
#   echo "wifi credential exists"
# else 
#   echo "append wifi credential"
#   printf "%s" "$WIFI_CRN" >> $rootfs/etc/wpa_supplicant/wpa_supplicant.conf
# fi
 sudo umount $rootfs
 sudo qemu-nbd -d $NBD_DEV
}

APT_CACHE_IMG=apt_cache
IMGFORMAT=qed

mkdir -p $work
cd $work
[ -b "$NBD_DEV" ] || modprobe nbd max_part=16
[ -e "$APT_CACHE_IMG.wip" ] && rm "$APT_CACHE_IMG"
if ! [ -f "$APT_CACHE_IMG" ]; then
  printf "No apt cache disk image exists. Making one.\n"
  qemu-img create -f $IMGFORMAT $APT_CACHE_IMG 4G
  touch "$APT_CACHE_IMG.wip"
  sudo -v
  attach_image_to_nbd $APT_CACHE_IMG $NBD_DEV
  sudo mkfs.ext4 -O ^huge_file $NBD_DEV
  mkdir -p rootfs
  sudo mount $NBD_DEV rootfs
  sudo mkdir -p rootfs/archives/partial
  sudo touch rootfs/archives/lock
  sudo umount $NBD_DEV
  detach_image_from_nbd $NBD_DEV
  rm "$APT_CACHE_IMG.wip"
fi

# convert RAW to QED
QED_IMG=$(basename "$RAW_IMG")"-QED"
[ ! -f "$QED_IMG" ] && qemu-img convert -f raw -O qed $RAW_IMG $QED_IMG
QED_IMG=$(readlink -m $QED_IMG)

QEMU_EXTRA="-drive file=$QED_IMG,index=1,media=disk,cache=unsafe"
QEMU_EXTRA=$QEMU_EXTRA" -drive file=$APT_CACHE_IMG,index=2,media=disk,cache=unsafe"
setup_wifi
disable_ld_so_preload
run_qemu "$QEMU_EXTRA"
mount_apt_cache
install_packages
shutdown_qemu
enable_ld_so_preload
REPACKED_IMG="REPACKED-"$(basename $RAW_IMG)
[ -f "$REPACKED_IMG" ] && rm $REPACKED_IMG
qemu-img convert -f qed -O raw $QED_IMG $REPACKED_IMG

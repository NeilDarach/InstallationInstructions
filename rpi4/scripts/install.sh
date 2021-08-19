#!/bin/sh
set -o pipefail
set -eu

stage1() {

apk add wireless-tools wpa_supplicant
wpa_passphrase "Darach" "?????" > /etc/wpa_supplicant/wpa_supplicant.conf 
sed -i -e "s/^wpa_supplicant_args=.*/wpa_supplicant_args=\"-i wlan0\"/" /etc/conf.d/wpa_supplicant
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto wlan0
iface wlan0 inet dhcp
EOF
rc-update add wpa_supplicant boot
rc-service wpa_supplicant start

cat > /tmp/answers <<EOF
KEYMAPOPTS="gb gb"
HOSTNAMEOPTS="-n ha-pi"
INTERFACESOPTS="auto lo
iface lo inet loopback

auto wlan0
iface wlan0 inet dhcp
"
DNSOPTS=""
TIMEZONEOPTS="-z Europe/London"
PROXYOPTS="none"
APKREPOSOPTS="-f"
SSHDOPTS="-c openssh"
NTPOPTS="-c chrony"
EOF


setup-alpine -f /tmp/answers



apk update
apk upgrade
sed -e 's/supported=vfat$/supported="vfat tmpfs"/' -i /sbin/setup-disk
sed -e 's/xfs vfat"$/xfs vfat tmpfs"/' -i /sbin/setup-disk
mkdir /media/ramdisk
mount -t tmpfs -o size=2048M tmpfs /media/ramdisk
mkdir /media/ramdisk/boot
setup-disk -m sys /media/ramdisk
mount -o remount,rw /media/mmcblk0p1
mount -o bind /dev /media/ramdisk/dev
mount -o bind /sys /media/ramdisk/sys
mount -t proc none /media/ramdisk/proc
mkdir /media/ramdisk/root/scripts
cp /media/mmcblk0p1/scripts/install.sh /media/ramdisk/root/scripts/stage2.sh
chroot /media/ramdisk /bin/sh -c /root/scripts/stage2.sh
}

stage2() {

mkdir /media/sdcard
mount /dev/mmcblk0p1 /media/sdcard
apk fetch lz4-libs lzo squashfs-tools libintl libtirpc-conf krb5-conf libcom_err keyutils-libs libverto krb5-libs libtirpc zfs-libs zfs-openrc zfs-rpi4 zfs zfs-lts
cp *.apk /media/sdcard/apks/aarch64

#apk add squashfs-tools zfs zfs-lts sfdisk partx
apk add squashfs-tools zfs sfdisk partx
#create the map with sfdisk -d /dev/mmcblk0
sfdisk /dev/mmcblk0 <<EOF
label: dos
label-id: 0x00000000
device: /dev/mmcblk0
unit: sectors
sector-size: 512

/dev/mmcblk0p1 : start=        2048, size=      500000, type=b
/dev/mmcblk0p2 : type=83
EOF
partx -a /dev/mmcblk0 || true
sed -e 's/tmpfs/tmpfs squashfs network dhcp loop zfs/' -i /etc/mkinitfs/mkinitfs.conf
mkinitfs

cp -r /lib/modules /tmp/modloop
mksquashfs /tmp/modloop /tmp/modloop.squashfs -b 1048576 -comp xz -Xdict-size 100%

cp /tmp/modloop.squashfs /media/sdcard/boot

# create the pool
modprobe zfs
zpool create -f -o ashift=12 -O acltype=posixacl -O canmount=off -O dnodesize=auto -O normalization=formD -O relatime=on -O xattr=sa -O mountpoint=/ -R /mnt rpool /dev/mmcblk0p2
zfs create -o mountpoint=none -o canmount=off rpool/ROOT
zfs create -o mountpoint=/ rpool/ROOT/alpine
zfs create -o mountpoint=/home rpool/home
zfs create -o mountpoint=/opt rpool/opt

sed -e 's/supported=vfat$/supported="vfat zfs"/' -i /sbin/setup-disk
mkdir -p /mnt/dev /mnt/sys /mnt/proc /mnt/boot 
mount -o bind /dev /mnt/dev
mount -o bind /sys /mnt/sys
mount -t proc none /mnt/proc
setup-disk -m sys /mnt
mkdir /mnt/root/scripts
cp /root/scripts/stage2.sh /mnt/root/scripts/stage3.sh
chroot /mnt /bin/sh -c /root/scripts/stage3.sh

}

stage3() {

rc-update add zfs-import sysinit
rc-update add zfs-mount sysinit
mkdir /root/.ssh
mkdir /media/sdcard
mount /dev/mmcblk0p1 /media/sdcard
cp /media/sdcard/boot/initramfs-rpi4 /media/sdcard/boot/initramfs-rpi4.orig
cp /media/sdcard/boot/vmlinuz-rpi4 /media/sdcard/boot/vmlinuz-rpi4.orig
cp /boot/initramfs-rpi4 /media/sdcard/boot
cp /boot/vmlinuz-rpi4 /media/sdcard/boot
wget https://speedy.goip.org.uk/authorized_keys -O /root/.ssh/authorized_keys
echo "/dev/mmcblk0p1	/media/mmcblk0p1 vfat	defaults	0	0" > /etc/fstab
echo "noquiet console=tty1 moloop=boot/modloop.squashfs modules=loop,squashfs,sd-mod,usb-storage,zfs root=rpool/ROOT/alpine rootfstype=zfs" > /media/sdcard/cmdline.txt
cat > /media/sdcard/usercfg.txt <<EOF
enable_uart=1
gpu_mem=32
disable_overscan=1
EOF
sed -e "s/#\(.*3\/community\)/\1/" -i /etc/apk/repositories
sed -i -e "s/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/"
apk update
apk add bash python3 neovim
umount /media/sdcard
rmdir /media/sdcard
zpool export -a || true
reboot
}


if [[ $(basename $0) = 'install.sh' ]] ; then
  stage1
elif [[ $(basename $0) = 'stage2.sh' ]] ; then
  stage2
elif [[ $(basename $0) = 'stage3.sh' ]] ; then
  stage3
else
  echo "Don't know what to run"
fi


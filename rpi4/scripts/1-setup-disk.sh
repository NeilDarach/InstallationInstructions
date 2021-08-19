setup-alpine -f ha-pi.answers

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
cp /media/mmcblk0p1/scripts/* /media/ramdisk/root/scripts
chroot /media/ramdisk /bin/sh

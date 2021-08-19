rc-update add zfs-import sysinit
rc-update add zfs-mount sysinit
mkdir /root/.ssh
mkdir /media/sdcard
mount /dev/mmcblk0p1 /media/sdcard
cp /media/sdcard/boot/initramfs-rpi4 /media/sdcard/boot/initramfs-rpi4.orig
cp /media/sdcard/boot/vmlinuz-rpi4 /media/sdcard/boot/vmlinuz-rpi4.orig
cp /boot/initramfs-rpi4 /media/sdcard/boot
cp /boot/vmlinuz-rpi4 /media/sdcard/boot
wget https://speedy2.goip.org.uk/authorized_keys -o /root/.ssh/authorized_keys
echo "/dev/mmcblk0p1	/media/mmcblk0p1 vfat	defaults	0	0" > /etc/fstab
echo "noquiet console=tty1 moloop=boot/modloop.squashfs modules=loop,squashfs,sd-mod,usb-storage,zfs root=rpool/ROOT/alpine rootfstype=zfs" > /media/sdcard/cmdline.txt
cat > /media/sdcard/usercfg.txt <<EOF
enable_uart=1
gpu_mem=32
disable_overscan=1
EOF
sed -e "s/#\(.*3\/community\)/\1/" -i /etc/apk/repositories
apk update
apk add python3 neovim
umount /media/sdcard
rmdir /media/sdcard

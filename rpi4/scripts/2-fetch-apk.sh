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
partx -a /dev/mmcblk0
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
cp /root/scripts/* /mnt/root/scripts
chroot /mnt /bin/sh



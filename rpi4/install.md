== Apline Linux on a Raspberry Pi 4 with ZFS root ==

Based on [Raspberry Pi 4 - Persistent system acting as a NAS and Time Machine>https://wiki.alpinelinux.org/wiki/Raspberry_Pi_4_-_Persistent_system_acting_as_a_NAS_and_Time_Machine].

=== Tinkering for Persistence ===

Download the latest tarball (3.13 at this time) from Alpine ([https://alpinelinux.org/downloads/]).  Use the aarch64 tarball for the Pi 4.

Partition the SD card for the Pi. The Pi boots off a FAT32 partition, but we want the system to reside in an ext4 partition later, so we will start by reserving a small portion of the card for the boot partition. This is done using Terminal in macOS with the following commands.

 diskutil list
 diskutil partitionDisk /dev/disk<n> MBR "FAT32" ALP 256MB "Free Space" SYS R
 sudo fdisk -e /dev/disk<n>
 > f 1
 > w
 > exit

Extract the tarball to the new partion

 cd /Volumes/ALP
 tar xvf ~/Downloads/alpine-rpi-3.13.4-aarch64.tar
 vi usercfg.txt

The newly created file usercfg.txt should contain the following:

 enable_uart=1
 gpu_mem=32
 disable_overscan=1

The least amount of memory for headless is 32MB. The UART thing is beyond me, but seems to be a recommended setting. Removing overscan gives you more screen estate. If you intend to use this as a desktop computer rather than a headless server you probably want to allocate more memory to the GPU and enable sound. Full specification for options can be found on the official Raspberry Pi homepage.

Eject the card (making sure that any pending writes are finalized).

 cd
 diskutil eject /dev/disk<n>

Put the SD card in the Pi and boot. Login with “root” as username and no password. This presumes that you have connected everything else, such as a keyboard and monitor.

 setup-alpine

During setup, select your keymap, hostname, etc, as desired. However, when asked where to store configs, type “none”, and the same for the apk cache directory. If you want to follow this guide to the point, you should also select “chrony” as the NTP client. The most important part here though is to get your network up and running. A full description of the setup programs can be found on the Alpine homepage.

 apk update
 apk upgrade

Create a ramdisk
 mkdir /media/ramdisk
 mount -t tmpfs -o size=2048M tmpfs /media/ramdisk

And install into it
 setup-disk -m sys /media/ramdisk

If setup-disk fails, beacuase only vfat is supported then edit setup-disk to remove the is_rpi line and allow the other file types.

Remount the disks and chroot to the new install
 mount -o remount,rw /media/mmcblk0p1
 mount -o bind /dev /media/ramdisk/dev
 mount -o bind /media/mmcblk0p1/boot /media/ramdisk/boot
 mount -o bind /sys /media/ramdisk/sys
 mount -t proc none /media/ramdisk/proc
 chroot /media/ramdisk


fetch apks for later
  apk fetch lz4-libs lzo squashfs-tools libintl libtirpc-conf krb5-conf libcom_err keyutils-libs libverto krb5-libs libtirpc zfs-libs zfs-openrc zfs-rpi4 zfs zfs-lts

§


Clear out the boot directory
 rm -f /boot/boot/*
 cd /media/ramdisk
 rm boot/boot
 mv boot/* /media/mmcblk0p1/boot/
 rm -Rf boot
 mkdir media/mmcblk0p1
 ln -s media/mmcblk0p1/boot boot





 apk add cfdisk partx
 cfdisk /dev/mmcblk0

In cfdisk, select “Free space” and the option “New”. It will suggest using the entire available space, so just press enter, then select the option “primary”, followed by “Write”. Type “yes” to write the partition table to disk, then select “Quit”.

 partx -a /dev/mmcblk0
 apk add e2fsprogs
 mkfs.ext4 /dev/mmcblk0p2
 mount /dev/mmcblk0p2 /mnt
 setup-disk -m sys /mnt
 mount -o remount,rw /media/mmcblk0p1

Now the mountpoints need fixing, so run:

 vi etc/fstab

Add the following line:

 /dev/mmcblk0p1   /media/mmcblk0p1   vfat   defaults   0 0

Now the kernel needs to know where the root filesystem is.

 vi /media/mmcblk0p1/cmdline.txt

Append the following at the end of the one and only line in the file:

 root=/dev/mmcblk0p2

And delete 'quiet' to get a reassuring boot screen

After exiting vi, it’s safe to reboot, so:

 reboot

After rebooting, login using “root” as username, and the password you selected during setup-alpine earlier. Now you have a persistent system and everything that is done will stick, as opposed to how the original distro was configured.

=== Tailoring for Remote Access ===

OpenSSH should already be installed, but it will not allow remote root login. We will initially relax this constraint. Last in this article is a section on hardening where we again disallow root login. If you intend to have this box accessible from the Internet I strongly advice on hardening the Pi.

 vi /etc/ssh/sshd_config

Uncomment and change the line (about 30 lines down) with PermitRootLogin to:

 PermitRootLogin NoPassword

Then restart the service:

 rc-service sshd restart

Copy an authorized_keys file in to /root/.ssh

  mkdir /root/.ssh
  chmod 755 /root/.ssh
  wget https://speedy2.goip.org.uk/authorized_keys -o /root/.ssh
  chmod 644 /root/.ssh/authorized_keys

Now you should be able to ssh to your Pi. The following steps are easier when you can cut and paste things into a terminal window. Feeling lucky? Then now is a good time to disconnect your keyboard and monitor.

=== Keeping the Time ===

If you selected chrony as your NTP client it may take a long time for it to actually correct the clock. Since the Pi does not have a hardware clock, it’s necessary to have time corrected at boot time, so we will change the configuration such that the clock is set if it is more than 60 seconds off during the first 10 lookups. 

 vi /etc/chrony/chrony.conf

Add the following line at the bottom of the file.

 makestep 60 10

Check the date, restart the service, and check the (now hopefully corrected) date again.

 date
 rc-service chronyd restart
 date

Having the correct time is a good thing, particularly when building a job scheduling server.

=== Hardening ===

Now that most configuring is done, it’s time to harden the Pi. First we will install a firewall with some basic login protection using the builtin ‘limit’ in iptables. Assuming you are in the 192.168.1.0/24 range, which was set during setup-alpine, the following should be run. Only clients on the local network are allowed access to shared folders.

 apk add ufw@testing
 rc-update add ufw default
 ufw allow 22
 ufw limit 22/tcp
 ufw allow 80
 ufw allow 443
 ufw allow Bonjour

With the rules in place, it’s time to disallow root login over ssh, and make sure that only fresh protocols are used.

 vi /etc/ssh/sshd_config

Change the line that previously said yes to no, and add the other lines at the bottom of the file (borrowed from this security site):

 PermitRootLogin NoPassword
 PrintMotd no
 Protocol 2
 HostKey /etc/ssh/ssh_host_ed25519_key
 HostKey /etc/ssh/ssh_host_rsa_key
 KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
 Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
 MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com

After that, enable ufw and restart sshd. Note that if something goes wrong here you will need to plug in a monitor and keyboard again to login locally and fix things.

 ufw enable
 rc-service sshd restart

Now is a good time to reboot and reconnect to check that everything is working.

 reboot

With root not being able to login, you will instead login as “pi”. It is possible for this user to (temporarily, until exit) elevate privileges by the following command:

 su


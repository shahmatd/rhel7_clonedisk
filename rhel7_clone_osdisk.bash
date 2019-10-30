#!/bin/bash
########################################################################################
# Author: Shahmat Dahlan <shahmatd@gmail.com>
# Date: 30/10/2019
# Description: RHEL 7.x/CentOS 7.x OS dd cloning # all filesystems are xfs.
# Pending:
# 1. Running of grub2-mkconfig -o /boot/grub2/grub.cfg on the chroot environ-
#    ment (/dev/sdb)
# 2. Update of the /boot/grub2/grub.cfg on the first disk, so grub will reflect
#    both OS on the grub menu at the next reboot
#    (a) One way is to update the entry in /boot/grub2/grub.cfg on the first
#        disk as an additional entry
#    (b) Edit the grub menu at the next reboot and change the root=hd0,msdos1
#        to root=hd1,msdos1
# URL: https://github.com/shahmatd/rhel7_clonedisk/blob/master/rhel7_clone_osdisk.bash
########################################################################################

source_dsk=/dev/sda
target_dsk=/dev/sdb
source_vg=centos
target_vg=centos1

# Zeroes target second disk /dev/sdb
echo "-------------------"
echo "Zeroes target second disk /dev/sdb, this will take a while..."
/bin/dd count=200000 if=/dev/zero of=${target_dsk}

# Start the dd cloning
echo
echo "-------------------"
echo "Start clone from first disk /dev/sda, this will also take a while..."
/bin/dd bs=1024000 if=${source_dsk} of=${target_dsk}

# Check to see if this is an EFI system, if it is, exit
if grep -q /boot/efi /etc/mtab; then 
	echo
	echo "-------------------"
	echo "This script is not tested on EFI systems yet, exiting..."
	exit 1
fi

echo
echo "-------------------"
if /sbin/xfs_repair -L /dev/sdb1; then
	echo "xfs_repair -L /dev/sdb1 is successful, proceeding..."
else
	echo "xfs_repair -L /dev/sdb1 failed, exiting..."
	exit 2
fi

echo
echo "-------------------"
if /sbin/xfs_admin -U generate /dev/sdb1; then
	echo "xfs_admin -U generate /dev/sdb1 is successful, proceeding..."
else
	echo "xfs_admin -U generate /dev/sdb1 failed, exiting..."
	exit 2
fi

if [ ! -d /a ]; then
	mkdir /a
fi

echo
echo "-------------------"
if mount /dev/sdb1 /a/boot; then
	echo "/boot able to mount, proceeding..."
	umount /a/boot
else
	echo "/boot unable to mount, exiting..."
	exit 3
fi

echo
echo "-------------------"
if /sbin/vgimportclone --import -n ${source_vg} /dev/sdb2; then
	echo "/sbin/vgimportclone --import -n ${source_vg} /dev/sdb2 is successful, proceeding..."
else
	echo "/sbin/vgimportclone --import -n ${source_vg} /dev/sdb2 failed, exiting..."
	exit 4
fi

echo
echo "-------------------"
# Activate vg target_vg centos1
if /sbin/vgchange -ay centos1; then
	echo "/sbin/vgchange -ay centos1 is successful, proceeding..."
else
	echo "/sbin/vgchange -ay centos1 failed, exiting..."
	exit 5
fi

# Calculate the number of existing LV
lv_count=$(/sbin/lvs -o lvname ${target_vg} | wc -l)
lv_count_m=$(expr $lv_count - 1)

for lv in $(/sbin/lvs -o lvname ${target_vg} | tail -${lv_count_m} | grep -v swap); do
	echo
	echo "-------------------"
	if xfs_repair -L /dev/mapper/${target_vg}-${lv}; then
		echo "xfs_repair -L /dev/mapper/${target_vg}-${lv} is successful, proceeding..."
	else
		echo "xfs_repair -L /dev/mapper/${target_vg}-${lv} failed, exiting..."
		exit 6
	fi
	echo
	echo "-------------------"
	if xfs_admin -U generate /dev/mapper/${target_vg}-${lv}; then
		echo "xfs_admin -U generate /dev/mapper/${target_vg}-${lv} is successful, proceeding..."
	else
		echo "xfs_admin -U generate /dev/mapper/${target_vg}-${lv} failed, exiting..."
		exit 7
	fi
done

# Mount first the root filesystem for the lines below to be able to use the /etc/fstab
echo
echo "-------------------"
if mount /dev/mapper/${target_vg}-root /a; then
	echo "mount /dev/mapper/${target_vg}-root /a is successful, proceeding..."
else
	echo "mount /dev/mapper/${target_vg}-root /a failed, exiting..."
	exit 8
fi
if mount /dev/sdb1 /a/boot; then
	echo "mount /dev/sdb1 /a/boot is successful, proceeding..."
else
	echo "mount /dev/sdb1 /a/boot failed, exiting..."
	exit 9
fi

# Extract only the uuid for /dev/sda1 and /dev/sdb1
disk1_uuid=$(blkid | grep /dev/sda1 | awk '{print $2}' | awk -F= '{print $2}' | sed 's/"//g')
disk2_uuid=$(blkid | grep /dev/sdb1 | awk '{print $2}' | awk -F= '{print $2}' | sed 's/"//g')

# Make a backup copy of the files /etc/fstab /boot/grub2/grub.cfg and /etc/default/grub on the second disk /dev/sdb
today=$(date +%Y%m%d_%H%M%S)
for file in /a/etc/fstab /a/boot/grub2/grub.cfg /a/etc/default/grub; do
	echo
	echo "-------------------"
	if [ -f $file ]; then
		echo "Making a backup of $file to $file.bak_${today}"
		cp $file $file.bak_${today}
	fi
done

# Update /etc/fstab on the second disk /dev/sdb mounted on /a
sed "s/${disk1_uuid}/${disk2_uuid}/" /a/etc/fstab.bak_${today} >/a/etc/fstab.bak_1
sed "s/${source_vg}/${target_vg}/" /a/etc/fstab.bak_1 >/a/etc/fstab
if [ -f /a/etc/fstab.bak_1 ]; then rm /a/etc/fstab.bak_1; fi

# Update /boot/grub2/grub.cfg and replace all the first disk /dev/sda to the second disk /dev/sdb
sed "s/${disk1_uuid}/${disk2_uuid}/" /a/boot/grub2/grub.cfg.bak_${today} >/a/boot/grub2/grub.cfg

# Update the vg name centos with centos1 in the /etc/default/grub
sed "s/${source_vg}/${target_vg}/" /a/etc/default/grub.bak_${today} >/a/etc/default/grub

# Mount the LVM LVs contained under PV /dev/sdb2 and VG centos1
for fstab_e in $(grep -P "^/" /a/etc/fstab | grep -vE "root|swap" | awk '{printf "%s|%s\n", $1, $2}'); do
	lv=$(echo $fstab_e | awk -F'|' '{print $1}')
	mntp=/a$(echo $fstab_e | awk -F'|' '{print $2}')
	mount $lv $mntp
done 

mount -t proc none /a/proc
mount -o bind /sys /a/sys
mount -o bind /dev /a/dev

echo
echo "-------------------"
echo "Completed."
echo "Please chroot into the environment on the second disk /dev/sdb:"
echo "   # chroot /a"
echo
echo "And run grub2-mkconfig -o /boot/grub2/grub.cfg"

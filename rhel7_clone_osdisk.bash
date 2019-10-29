#!/bin/bash
######################################################
# Author: Shahmat Dahlan <shahmat@gmail.com>
# Date: 30/10/2019 05:30 AM
# Description:
#      To basically perform an OS cloning for OS with
# two disk /dev/sda and /dev/sdb of the same size.
# Filesystems are xfs. Uses dd to clone
# Activation of booting to secondary from the grub2
# menu is manual. e.g. When the grub2 menu appears,
# press the 'e' key to make the changes and 'ctrl+x'
# to boot into the second disk
######################################################
source_dsk=/dev/sda
target_dsk=/dev/sdb
source_vg=centos
target_vg=centos1

# Zeroes target second disk /dev/sdb
echo "Zeroes target second disk /dev/sdb, this will take a while..."
/bin/dd count=200000 if=/dev/zero of=${target_dsk}

# Start the dd cloning
echo "Start clone from first disk /dev/sda, this will also take a while..."
/bin/dd bs=1024000 if=${source_dsk} of=${target_dsk}

# Check to see if this is an EFI system, if it is, exit
if grep -q /boot/efi /etc/mtab; then 
	echo "This script is not tested on EFI systems yet."
	exit 1
fi

if /sbin/xfs_repair -L /dev/sdb1; then
	echo "xfs_repair -L /dev/sdb1 is successful, proceeding..."
else
	echo "xfs_repair -L /dev/sdb1 failed, exiting..."
	exit 2
fi

if /sbin/xfs_admin -U generate /dev/sdb1; then
	echo "xfs_admin -U generate /dev/sdb1 is successful, proceeding..."
else
	echo "xfs_admin -U generate /dev/sdb1 failed, exiting..."
	exit 2
fi

if [ ! -d /a ]; then
	mkdir /a
fi

if mount /dev/sdb1 /a/boot; then
	echo "/boot able to mount, proceeding..."
	umount /a/boot
else
	echo "/boot unable to mount, exiting..."
	exit 3
fi

if /sbin/vgimportclone --import -n ${source_vg} /dev/sdb2; then
	echo "vgimportclone --import -n ${source_vg} /dev/sdb2 is successful, proceeding..."
else
	echo "vgimportclone --import -n ${source_vg} /dev/sdb2 failed, exiting..."
	exit 4
fi

# Activate vg target_vg centos1
if /sbin/vgchange -ay ${target_vg}; then
	echo "Activate vg ${target_vg} is successful, proceeding..."
else
	echo "Activate vg ${target_vg} failed, exiting..."
	exit 5
fi

# Calculate the number of existing LV
lv_count=$(/sbin/lvs -o lvname ${target_vg} | wc -l)
lv_count_m=$(expr $lv_count - 1)

for lv in $(/sbin/lvs -o lvname ${target_vg} | tail -${lv_count_m} | grep -v swap); do
	echo $lv
	if xfs_repair -L /dev/mapper/${target_vg}-${lv}; then
		echo "xfs_repair -L /dev/mapper/${target_vg}-${lv} is successful, proceeding..."
	else
		echo "xfs_repair -L /dev/mapper/${target_vg}-${lv} failed, exiting..."
		exit 6
	fi
	if xfs_admin -U generate /dev/mapper/${target_vg}-${lv}; then
		echo "xfs_admin -U generate /dev/mapper/${target_vg}-${lv} is successful, proceeding..."
	else
		echo "xfs_admin -U generate /dev/mapper/${target_vg}-${lv} failed, exiting..."
		exit 7
	fi
done

mount /dev/mapper/${target_vg}-root /a
mount /dev/sdb1 /a/boot
mount /dev/mapper/${target_vg}-home /a/home
mount /dev/mapper/${target_vg}-tmp /a/tmp
mount /dev/mapper/${target_vg}-var /a/var
mount /dev/mapper/${target_vg}-var_log /a/var/log
mount /dev/mapper/${target_vg}-var_tmp /a/var/tmp
mount /dev/mapper/${target_vg}-var_log_audit /a/var/log/audit
mount -t proc none /a/proc
mount -o bind /sys /a/sys
mount -o bind /dev /a/dev

disk1_uuid=$(blkid | grep /dev/sda1 | awk '{print $2}' | awk -F= '{print $2}' | sed 's/"//g')
disk2_uuid=$(blkid | grep /dev/sdb1 | awk '{print $2}' | awk -F= '{print $2}' | sed 's/"//g')

today=$(date +%Y%m%d_%H%M%S)
for file in /a/etc/fstab /a/boot/grub2/grub.cfg /a/etc/default/grub; do
	if [ -f $file ]; then
		cp $file $file.bak_${today}
	fi
done

sed "s/${disk1_uuid}/${disk2_uuid}/" /a/etc/fstab.bak_${today} >/a/etc/fstab
sed "s/${disk1_uuid}/${disk2_uuid}/" /a/boot/grub2/grub.cfg.bak_${today} >/a/boot/grub2/grub.cfg
sed "s/${source_vg}/${target_vg}/" /a/etc/default/grub.bak_${today} >/a/etc/default/grub

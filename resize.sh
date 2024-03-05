#!/bin/bash
PATH="/usr/sbin:/usr/bin"

update_part() {
    partx -u "$1"
    udevadm trigger
    udevadm settle
}

# el 自带 fdisk parted (el7的part不支持在线扩容)
# ubuntu 自带 fdisk growpart

# 删除分区用
# el/ubuntu fdisk

# 扩容分区用
# el7 grownparted 额外安装
# el8/9/fedora parted
# ubuntu grownpart

# 找出主硬盘
root_drive=$(mount | awk '$3=="/" {print $1}')
xda=$(lsblk -r --inverse "$root_drive" | grep -w disk | awk '{print $1}')

# 删除 installer 分区
installer_num=$(readlink -f /dev/disk/by-label/installer | grep -o '[0-9]*$')
if [ -n "$installer_num" ]; then
    # 要添加 LC_NUMERIC 或者将%转义成\%才能在cron里正确运行
    # locale -a 不一定有"en_US.UTF-8"，但肯定有"C.UTF-8"
    LC_NUMERIC="C.UTF-8"
    printf "d\n%s\nw" "$installer_num" | fdisk "/dev/$xda"
    update_part "/dev/$xda"
fi

# 找出现在的最后一个分区，也就是系统分区
# el7 的 lsblk 没有 --sort，所以用其他方法
# shellcheck disable=2012
part_num=$(ls -1v "/dev/$xda"* | tail -1 | grep -o '[0-9]*$')
part_fstype=$(lsblk -no FSTYPE "/dev/$xda"*"$part_num")

# 扩容分区
# ubuntu 和 el7 用 growpart，其他用 parted
# el7 不能用parted在线扩容，而fdisk扩容会改变 PARTUUID，所以用 growpart
if grep -E -i 'centos:7|ubuntu' /etc/os-release; then
    growpart "/dev/$xda" "$part_num"
else
    printf 'yes\n100%%' | parted "/dev/$xda" resizepart "$part_num" ---pretend-input-tty
fi
update_part "/dev/$xda"

# 扩容最后一个分区的文件系统
case $part_fstype in
xfs) xfs_growfs / ;;
ext*) resize2fs "/dev/$xda"*"$part_num" ;;
btrfs) btrfs filesystem resize max / ;;
esac
update_part "/dev/$xda"

# 删除脚本自身
rm -f /resize.sh /etc/cron.d/resize

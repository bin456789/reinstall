#!/bin/bash
PATH="/usr/sbin:/usr/bin"

update_part() {
  partprobe
  partx -u $1
  udevadm settle
}

# rh 自带 fdisk parted
# ubuntu 自带 fdisk growpart

# 找出主硬盘
xda=$(lsblk -dn -o NAME | grep -E 'nvme0n1|.da')

# 删除 installer 分区
installer_num=$(readlink -f /dev/disk/by-label/installer | grep -o '[0-9]*$')
if [ -n "$installer_num" ]; then
  # 要添加 LC_NUMERIC 或者将%转义成\%才能在cron里正确运行
  LC_NUMERIC=en_US.utf8
  printf "d\n%s\nw" "$installer_num" | fdisk /dev/$xda
  update_part /dev/$xda
fi

# 找出现在的最后一个分区，也就是系统分区
# el7 的 lsblk 没有 --sort，所以用其他方法
# shellcheck disable=2012
part_num=$(ls -1v /dev/$xda* | tail -1 | grep -o '[0-9]*$')
part_fstype=$(lsblk -no FSTYPE /dev/$xda$part_num)

# 扩容分区
# rh 7 不能用parted在线扩容，而fdisk扩容会改变 PARTUUID，所以用 growpart
# printf 'yes\n100%%' | parted /dev/$xda resizepart $part_num ---pretend-input-tty
growpart /dev/$xda $part_num
update_part /dev/$xda

# 扩容最后一个分区的文件系统
case $part_fstype in
xfs) xfs_growfs / ;;
ext*) resize2fs /dev/$xda$part_num ;;
esac

# 删除脚本自身
rm -f /resize.sh /etc/cron.d/resize

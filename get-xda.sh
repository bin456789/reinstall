#!/bin/sh
# debian ubuntu redhat 安装模式共用此脚本
# alpine 未用到此脚本

get_all_disks() {
    # busybox blkid 不接受任何参数
    disks=$(blkid | cut -d: -f1 | cut -d/ -f3 | sed -E 's/p?[0-9]+$//' | sort -u)
    # blkid 会显示 sr0，经过上面的命令输出为 sr
    # 因此要检测是否有效
    for disk in $disks; do
        if [ -b "/dev/$disk" ]; then
            echo "$disk"
        fi
    done
}

get_xda() {
    # 如果没找到 main_disk 或 xda
    # 返回假的值，防止意外地格式化全部盘
    main_disk="$(grep -o 'extra\.main_disk=[^ ]*' /proc/cmdline | cut -d= -f2)"

    if [ -z "$main_disk" ]; then
        echo 'MAIN_DISK_NOT_FOUND'
        return 1
    fi

    for disk in $(get_all_disks); do
        if fdisk -l "/dev/$disk" | grep -iq "$main_disk"; then
            echo "$disk"
            return
        fi
    done

    echo 'XDA_NOT_FOUND'
    return 1
}

get_xda

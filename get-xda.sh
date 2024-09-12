#!/bin/sh
# debian ubuntu redhat 安装模式共用此脚本
# alpine 未用到此脚本

get_all_disks() {
    # shellcheck disable=SC2010
    ls /sys/block/ | grep -Ev '^(loop|sr|nbd)'
}

get_xda() {
    # 如果没找到 main_disk 或 xda
    # 返回假的值，防止意外地格式化全部盘
    eval "$(grep -o 'extra_main_disk=[^ ]*' /proc/cmdline | sed 's/^extra_//')"

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

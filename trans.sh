#!/bin/ash
# shellcheck shell=dash
# alpine 默认使用 busybox ash

# 显示输出到前台
# 似乎script更优雅，但 alpine 不带 script 命令
# script -f/dev/tty0
exec >/dev/tty0 2>&1

# 提取 finalos/extra 到变量
for prefix in finalos extra; do
    for var in $(grep -o "\b$prefix\.[^ ]*" /proc/cmdline | xargs); do
        eval "$(echo $var | sed -E "s/$prefix\.([^=]*)=(.*)/\1='\2'/")"
    done
done

# 找到主硬盘
# alpine 不自带lsblk，liveos安装的软件也会被带到新系统，所以不用lsblk
# xda=$(lsblk -dn -o NAME | grep -E 'nvme0n1|.da')
# shellcheck disable=SC2010
xda=$(ls /dev/ | grep -Ex '[shv]da|nvme0n1')

# arm要手动从硬件同步时间，避免访问https出错
hwclock -s

# 安装并打开 ssh
echo root:123@@@ | chpasswd
printf '\nyes' | setup-sshd

# shellcheck disable=SC2154
if [ "$distro" = "alpine" ]; then
    # 还原改动，不然本脚本会被复制到新系统
    rm -f /etc/local.d/trans.start
    rm -f /etc/runlevels/default/local

    # 网络
    setup-interfaces -a # 生成 /etc/network/interfaces
    rc-update add networking boot

    # 设置
    setup-keymap us us
    setup-timezone -i Asia/Shanghai
    setup-ntp chrony

    # 在 arm netboot initramfs init 中
    # 如果识别到rtc硬件，就往系统添加hwclock服务，否则添加swclock
    # 这个设置也被复制到安装的系统中
    # 但是从initramfs chroot到真正的系统后，是能识别rtc硬件的
    # 所以我们手动改用hwclock修复这个问题
    rc-update del swclock boot
    rc-update add hwclock boot

    # 通过 setup-alpine 安装会多启用几个服务
    # https://github.com/alpinelinux/alpine-conf/blob/c5131e9a038b09881d3d44fb35e86851e406c756/setup-alpine.in#L189
    # acpid | default
    # crond | default
    # seedrng | boot

    # 添加 virt-what 用到的社区仓库
    alpine_ver=$(cut -d. -f1,2 </etc/alpine-release)
    echo http://dl-cdn.alpinelinux.org/alpine/v$alpine_ver/community >>/etc/apk/repositories

    # 如果是 vm 就用 virt 内核
    cp /etc/apk/world /tmp/world.old
    apk add virt-what
    if [ -n "$(virt-what)" ]; then
        kernel_opt="-k virt"
    fi
    # 删除 virt-what 和依赖，不然会带到新系统
    apk del "$(diff /tmp/world.old /etc/apk/world | grep '^+' | sed '1d' | sed 's/^+//')"

    # 重置为官方仓库配置
    true >/etc/apk/repositories
    setup-apkrepos -1
    setup-apkcache /var/cache/apk

    # 安装到硬盘
    # alpine默认使用 syslinux (efi 环境除外)，这里强制使用 grub，方便用脚本再次重装
    export BOOTLOADER="grub"
    printf 'y' | setup-disk -m sys $kernel_opt -s 0 /dev/$xda
    exec reboot
fi

download() {
    # 显示 url
    echo $1

    # 阿里云禁止 axel 下载
    # axel https://mirrors.aliyun.com/alpine/latest-stable/releases/x86_64/alpine-netboot-3.17.0-x86_64.tar.gz
    # Initializing download: https://mirrors.aliyun.com/alpine/latest-stable/releases/x86_64/alpine-netboot-3.17.0-x86_64.tar.gz
    # HTTP/1.1 403 Forbidden

    # 先用 axel 下载
    [ -z $2 ] && save="" || save="-o $2"
    if ! axel $1 $save; then
        # 出错再用 curl
        [ -z $2 ] && save="-O" || save="-o $2"
        curl -L $1 $save
    fi
}

update_part() {
    hdparm -z $1
    partprobe $1
    partx -u $1
    udevadm settle
    echo 1 >/sys/block/${1#/dev/}/device/rescan
} 2>/dev/null

if ! apk add util-linux axel grub udev hdparm e2fsprogs curl parted; then
    echo 'Unable to install package!'
    sleep 1m
    exec reboot
fi

# 打开dev才能刷新分区名
rc-service udev start

# 反激活 lvm
# alpine live 不需要
false && vgchange -an

# 移除 lsblk 显示的分区
partx -d /dev/$xda

disk_size=$(blockdev --getsize64 /dev/$xda)
disk_2t=$((2 * 1024 * 1024 * 1024 * 1024))

# 对于红帽系是临时分区表，安装时除了 installer 分区，其他分区会重建为默认的大小
# 对于ubuntu是最终分区表，因为 ubuntu 的安装器不能调整个别分区，只能重建整个分区表
# {xda}*1 星号用于 nvme0n1p1 的字母 p
if [ -d /sys/firmware/efi ]; then
    # efi
    apk add dosfstools
    parted /dev/$xda -s -- \
        mklabel gpt \
        mkpart '" "' fat32 1MiB 1025MiB \
        mkpart '" "' ext4 1025MiB -2GiB \
        mkpart '" "' ext4 -2GiB 100% \
        set 1 boot on
    update_part /dev/$xda
    mkfs.fat -F 32 -n efi /dev/${xda}*1     #1 efi
    mkfs.ext4 -F -L os /dev/${xda}*2        #2 os
    mkfs.ext4 -F -L installer /dev/${xda}*3 #3 installer
elif [ "$disk_size" -ge "$disk_2t" ]; then
    # bios 2t
    parted /dev/$xda -s -- \
        mklabel gpt \
        mkpart '" "' ext4 1MiB 2MiB \
        mkpart '" "' ext4 2MiB -2GiB \
        mkpart '" "' ext4 -2GiB 100% \
        set 1 bios_grub on
    update_part /dev/$xda
    echo                                    #1 bios_boot
    mkfs.ext4 -F -L os /dev/${xda}*2        #2 os
    mkfs.ext4 -F -L installer /dev/${xda}*3 #3 installer
else
    # bios
    parted /dev/$xda -s -- \
        mklabel msdos \
        mkpart primary ext4 1MiB -2GiB \
        mkpart primary ext4 -2GiB 100% \
        set 1 boot on
    update_part /dev/$xda
    mkfs.ext4 -F -L os /dev/${xda}*1        #1 os
    mkfs.ext4 -F -L installer /dev/${xda}*2 #2 installer
fi
update_part /dev/$xda

# 挂载主分区
mkdir -p /os
mount /dev/disk/by-label/os /os

# 挂载其他分区
mkdir -p /os/boot/efi
mount /dev/disk/by-label/efi /os/boot/efi
mkdir -p /os/installer
mount /dev/disk/by-label/installer /os/installer

# 安装 grub2
basearch=$(uname -m)
if [ -d /sys/firmware/efi/ ]; then
    # 注意低版本的grub无法启动f38 arm的内核
    # https://forums.fedoraforum.org/showthread.php?330104-aarch64-pxeboot-vmlinuz-file-format-changed-broke-PXE-installs

    apk add grub-efi efibootmgr
    grub-install --efi-directory=/os/boot/efi --boot-directory=/os/boot

    # 添加 netboot 备用
    cd /os/boot/efi || exit
    if [ "$basearch" = aarch64 ]; then
        download https://boot.netboot.xyz/ipxe/netboot.xyz-arm64.efi
    else
        download https://boot.netboot.xyz/ipxe/netboot.xyz.efi
    fi
else
    apk add grub-bios
    grub-install --boot-directory=/os/boot /dev/$xda
fi

# 重新整理 extra，因为grub会处理掉引号，要重新添加引号
for var in $(grep -o '\bextra\.[^ ]*' /proc/cmdline | xargs); do
    extra_cmdline="$extra_cmdline $(echo $var | sed -E "s/(extra\.[^=]*)=(.*)/\1='\2'/")"
done

grub_cfg=/os/boot/grub/grub.cfg

# 新版grub不区分linux/linuxefi
# shellcheck disable=SC2154
if [ "$distro" = "ubuntu" ]; then
    cd /os/installer/ || exit
    download $iso ubuntu.iso

    iso_file=/ubuntu.iso
    # 正常写法应该是 ds="nocloud-net;s=https://xxx/" 但是甲骨文云的ds更优先，自己的ds根本无访问记录
    # $seed 是 https://xxx/
    cat <<EOF >$grub_cfg
        set timeout=5
        menuentry "reinstall" {
            # https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/1851311
            rmmod tpm
            search --no-floppy --label --set=root installer
            loopback loop $iso_file
            linux (loop)/casper/vmlinuz iso-scan/filename=$iso_file autoinstall noprompt noeject cloud-config-url=$ks $extra_cmdline ---
            initrd (loop)/casper/initrd
        }
EOF
else
    cd /os/ || exit
    download $vmlinuz
    download $initrd

    cd /os/installer/ || exit
    download $squashfs install.img

    cat <<EOF >$grub_cfg
        set timeout=5
        menuentry "reinstall" {
            search --no-floppy --label --set=root os
            linux /vmlinuz inst.stage2=hd:LABEL=installer:/install.img inst.ks=$ks $extra_cmdline
            initrd /initrd.img
        }
EOF
fi
reboot

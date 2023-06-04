#!/bin/ash
# shellcheck shell=dash
# alpine 默认使用 busybox ash

# 显示输出到前台
# 似乎script更优雅，但 alpine 不带 script 命令
# script -f/dev/tty0
exec >/dev/tty0 2>&1

add_community_repo() {
    alpine_ver=$(cut -d. -f1,2 </etc/alpine-release)
    echo http://dl-cdn.alpinelinux.org/alpine/v$alpine_ver/community >>/etc/apk/repositories
}

# 提取 finalos/extra 到变量
for prefix in finalos extra; do
    while read -r line; do
        if [ -n "$line" ]; then
            key=$(echo $line | cut -d= -f1)
            value=$(echo $line | cut -d= -f2-)
            eval "$key='$value'"
        fi
    done <<EOF
$(xargs -n1 </proc/cmdline | grep "^$prefix" | sed "s/^$prefix\.//")
EOF
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
    add_community_repo

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

elif [ "$distro" = "dd" ]; then
    filetype=$(echo $ddimg | awk -F. '{print $NF}')
    case "$filetype" in
    gz) prog=gzip ;;
    xz) prog=xz ;;
    esac

    if [ -n "$prog" ]; then
        # alpine busybox 自带 gzip xz，但官方版也许性能更好
        apk add curl $prog
        curl -L $ddimg | $prog -dc >/dev/$xda
    else
        echo 'Not supported'
        sleep 1m
    fi
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

# xda*1 星号用于 nvme0n1p1 的字母 p
if [ "$distro" = windows ]; then
    add_community_repo
    apk add ntfs-3g ntfs-3g-progs fuse3 virt-what wimlib rsync dos2unix
    modprobe fuse
    if [ -d /sys/firmware/efi ]; then
        # efi
        apk add dosfstools
        parted /dev/$xda -s -- \
            mklabel gpt \
            mkpart '" "' fat32 1MiB 1025MiB \
            mkpart '" "' fat32 1025MiB 1041MiB \
            mkpart '" "' ext4 1041MiB -6GiB \
            mkpart '" "' ntfs -6GiB 100% \
            set 1 boot on \
            set 2 msftres on \
            set 3 msftdata on
        update_part /dev/$xda
        mkfs.fat -F 32 -n efi /dev/$xda*1        #1 efi
        echo                                     #2 msr
        mkfs.ext4 -F -L os /dev/$xda*3           #3 os
        mkfs.ntfs -f -F -L installer /dev/$xda*4 #4 installer
    else
        # bios
        parted /dev/$xda -s -- \
            mklabel msdos \
            mkpart primary ntfs 1MiB -6GiB \
            mkpart primary ntfs -6GiB 100% \
            set 1 boot on
        update_part /dev/$xda
        mkfs.ext4 -F -L os /dev/$xda*1           #1 os
        mkfs.ntfs -f -F -L installer /dev/$xda*2 #2 installer
    fi
else
    # 对于红帽系是临时分区表，安装时除了 installer 分区，其他分区会重建为默认的大小
    # 对于ubuntu是最终分区表，因为 ubuntu 的安装器不能调整个别分区，只能重建整个分区表
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
        mkfs.fat -F 32 -n efi /dev/$xda*1     #1 efi
        mkfs.ext4 -F -L os /dev/$xda*2        #2 os
        mkfs.ext4 -F -L installer /dev/$xda*3 #3 installer
    elif [ "$disk_size" -ge "$disk_2t" ]; then
        # bios 2t
        parted /dev/$xda -s -- \
            mklabel gpt \
            mkpart '" "' ext4 1MiB 2MiB \
            mkpart '" "' ext4 2MiB -2GiB \
            mkpart '" "' ext4 -2GiB 100% \
            set 1 bios_grub on
        update_part /dev/$xda
        echo                                  #1 bios_boot
        mkfs.ext4 -F -L os /dev/$xda*2        #2 os
        mkfs.ext4 -F -L installer /dev/$xda*3 #3 installer
    else
        # bios
        parted /dev/$xda -s -- \
            mklabel msdos \
            mkpart primary ext4 1MiB -2GiB \
            mkpart primary ext4 -2GiB 100% \
            set 1 boot on
        update_part /dev/$xda
        mkfs.ext4 -F -L os /dev/$xda*1        #1 os
        mkfs.ext4 -F -L installer /dev/$xda*2 #2 installer
    fi
fi

update_part /dev/$xda

# 挂载主分区
mkdir -p /os
mount /dev/disk/by-label/os /os

# 挂载其他分区
mkdir -p /os/boot/efi
if [ -d /sys/firmware/efi/ ]; then
    mount /dev/disk/by-label/efi /os/boot/efi
fi
mkdir -p /os/installer
mount /dev/disk/by-label/installer /os/installer

basearch=$(uname -m)
case "$basearch" in
"x86_64") basearch_alt=amd64 ;;
"aarch64") basearch_alt=arm64 ;;
esac

# shellcheck disable=SC2154
if [ "$distro" = "windows" ]; then
    download $iso /os/windows.iso
    mkdir /iso
    mount /os/windows.iso /iso

    # 下载 virtio 驱动
    if [ "$(virt-what)" = kvm ]; then
        case $(echo "$image_name" | tr '[:upper:]' '[:lower:]') in
        'windows server 2022'*) sys=2k22 ;;
        'windows server 2019'*) sys=2k19 ;;
        'windows server 2016'*) sys=2k16 ;;
        'windows server 2012 R2'*) sys=2k12R2 ;;
        'windows server 2012'*) sys=2k12 ;;
        'windows server 2008 R2'*) sys=2k8R2 ;;
        'windows server 2008'*) sys=2k8 ;;
        'windows 11'*) sys=w11 ;;
        'windows 10'*) sys=w10 ;;
        'windows 8.1'*) sys=w8.1 ;;
        'windows 8'*) sys=w8 ;;
        'windows 7'*) sys=w7 ;;
        esac

        case "$sys" in
        # https://github.com/virtio-win/virtio-win-pkg-scripts/issues/40
        w7) dir=archive-virtio/virtio-win-0.1.173-9 ;;
        # https://github.com/virtio-win/virtio-win-pkg-scripts/issues/61
        2k12*) dir=archive-virtio/virtio-win-0.1.215-1 ;;
        *) dir=stable-virtio ;;
        esac

        download https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/$dir/virtio-win.iso /os/virtio-win.iso
        mkdir /virtio
        mount /os/virtio-win.iso /virtio
    fi

    # efi: 复制boot开头的文件+efi目录到efi分区，复制iso全部文件(除了boot.wim)到installer分区
    # bios: 复制iso全部文件到installer分区
    if [ -d /sys/firmware/efi/ ]; then
        mkdir -p /os/boot/efi/sources/
        /bin/cp -rv /iso/boot* /os/boot/efi/
        /bin/cp -rv /iso/efi/ /os/boot/efi/
        /bin/cp -rv /iso/sources/boot.wim /os/boot/efi/sources/
        rsync -rv --exclude=/sources/boot.wim /iso/* /os/installer/
        boot_wim=/os/boot/efi/sources/boot.wim
    else
        rsync -rv /iso/* /os/installer/
        boot_wim=/os/installer/sources/boot.wim
    fi
    install_wim=/os/installer/sources/install.wim

    # 修改应答文件
    download $confhome/Autounattend.xml /tmp/Autounattend.xml
    locale=$(wiminfo $install_wim | grep 'Default Language' | head -1 | awk '{print $NF}')
    sed -i "s|%arch%|$basearch_alt|; s|%image_name%|$image_name|; s|%locale%|$locale|" /tmp/Autounattend.xml

    # 修改应答文件，分区配置
    line_num=$(grep -E -n '<ModifyPartitions>' /tmp/Autounattend.xml | cut -d: -f1)
    if [ -d /sys/firmware/efi/ ]; then
        sed -i "s|%installto_partitionid%|3|" /tmp/Autounattend.xml
        cat <<EOF | sed -i "${line_num}r /dev/stdin" /tmp/Autounattend.xml
            <ModifyPartition wcm:action="add">
                <Order>1</Order>
                <PartitionID>1</PartitionID>
                <Format>FAT32</Format>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
                <Order>2</Order>
                <PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
                <Order>3</Order>
                <PartitionID>3</PartitionID>
                <Format>NTFS</Format>
            </ModifyPartition>
EOF
    else
        sed -i "s|%installto_partitionid%|1|" /tmp/Autounattend.xml
        cat <<EOF | sed -i "${line_num}r /dev/stdin" /tmp/Autounattend.xml
            <ModifyPartition wcm:action="add">
                <Order>1</Order>
                <PartitionID>1</PartitionID>
                <Format>NTFS</Format>
            </ModifyPartition>
EOF
    fi
    unix2dos /tmp/Autounattend.xml

    #     # ei.cfg
    #     cat <<EOF >/os/installer/sources/ei.cfg
    #         [Channel]
    #         OEM
    # EOF
    #     unix2dos /os/installer/sources/ei.cfg

    # 挂载 boot.wim
    mkdir /wim
    wimmountrw $boot_wim 2 /wim/

    # virtio 驱动
    if [ -d /virtio ]; then
        mkdir /wim/virtio
        find /virtio \
            -ipath "*/$sys/$basearch_alt/*" \
            -not -iname '*.pdb' \
            -not -iname '*.doc' \
            -exec /bin/cp -rf {} /wim/virtio/ \;
    fi

    # win7 要添加 bootx64.efi 到 efi 目录
    [ $basearch = x86_64 ] && boot_efi=bootx64.efi || boot_efi=bootaa64.efi
    if [ -d /sys/firmware/efi/ ] && [ ! -e /os/boot/efi/efi/boot/$boot_efi ]; then
        mkdir -p /os/boot/efi/efi/boot/
        cp /wim/Windows/Boot/EFI/bootmgfw.efi /os/boot/efi/efi/boot/$boot_efi
    fi

    # 复制应答文件
    cp /tmp/Autounattend.xml /wim/

    # 提交修改 boot.wim
    wimunmount --commit /wim/

    # windows 7 没有 invoke-webrequest
    # installer分区盘符不一定是D盘
    # 所以复制 resize.bat 到 install.wim
    image_name=$(wiminfo $install_wim | grep -ix "Name:[[:blank:]]*$image_name" | cut -d: -f2 | xargs)
    wimmountrw $install_wim "$image_name" /wim/
    download $confhome/resize.bat /wim/resize.bat
    wimunmount --commit /wim/

    # 添加引导
    if [ -d /sys/firmware/efi/ ]; then
        apk add efibootmgr
        efibootmgr -c -L "Windows Installer" -d /dev/$xda -p1 -l "\\EFI\\boot\\$boot_efi"
    else
        # 或者用 ms-sys
        apk add grub-bios
        grub-install --boot-directory=/os/boot /dev/$xda
        cat <<EOF >/os/boot/grub/grub.cfg
            set timeout=5
            menuentry "reinstall" {
                search --no-floppy --label --set=root installer
                ntldr /bootmgr
            }
EOF
    fi
    exec reboot
fi

# 安装 grub2
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
            # rmmod tpm
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

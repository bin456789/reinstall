#!/bin/ash
# shellcheck shell=dash
# shellcheck disable=SC2086,SC3047,SC3036,SC3010,SC3001
# alpine 默认使用 busybox ash

# 命令出错终止运行，将进入到登录界面，防止失联
set -eE
trap 'trap_err $LINENO $?' ERR

# 复制本脚本到 /tmp/trans.sh，用于打印错误
# 也有可能从管道运行，这时删除 /tmp/trans.sh
case "$0" in
*trans.*) cp -f "$0" /tmp/trans.sh ;;
*) rm -f /tmp/trans.sh ;;
esac

# 还原改动，不然本脚本会被复制到新系统
rm -f /etc/local.d/trans.start
rm -f /etc/runlevels/default/local

trap_err() {
    line_no=$1
    ret_no=$2

    error "Line $line_no return $ret_no"
    if [ -f "/tmp/trans.sh" ]; then
        sed -n "$line_no"p /tmp/trans.sh
    fi
}

error() {
    color='\e[31m'
    plain='\e[0m'
    echo -e "${color}Error: $*${plain}"
}

error_and_exit() {
    error "$@"
    exit 1
}

add_community_repo() {
    # 先检查原来的repo是不是egde
    if grep -x 'http.*/edge/main' /etc/apk/repositories; then
        alpine_ver=edge
    else
        alpine_ver=v$(cut -d. -f1,2 </etc/alpine-release)
    fi

    if ! grep -x "http.*/$alpine_ver/community" /etc/apk/repositories; then
        echo http://dl-cdn.alpinelinux.org/alpine/$alpine_ver/community >>/etc/apk/repositories
    fi
}

download() {
    url=$1
    file=$2
    echo $url

    # 阿里云禁止 axel 下载
    # axel https://mirrors.aliyun.com/alpine/latest-stable/releases/x86_64/alpine-netboot-3.17.0-x86_64.tar.gz
    # Initializing download: https://mirrors.aliyun.com/alpine/latest-stable/releases/x86_64/alpine-netboot-3.17.0-x86_64.tar.gz
    # HTTP/1.1 403 Forbidden

    # axel 在 lightsail 上会占用大量cpu
    # 构造 aria2 参数
    # 没有指定文件名的情况
    if [ -z $file ]; then
        save=""
    else
        # 文件名是绝对路径
        if [[ "$file" = "/*" ]]; then
            save="-d / -o $file"
        else
            # 文件名是相对路径
            save="-o $file"
        fi
    fi
    # 先用 aria2 下载
    # aria2 下载 fedora 官方镜像链接会将meta4文件下载下来，而且占用了指定文件名，造成重命名失效。而且无法指定目录
    # https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2
    # https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-o
    if ! (command -v aria2c && aria2c -x4 --allow-overwrite=true $url $save); then
        # 出错再用 wget
        # alpine 的 busybox 没有 curl
        [ -z $file ] && save="" || save="-O $file"
        wget $url $save
    fi
}

update_part() {
    {
        hdparm -z $1
        partprobe $1
        partx -u $1
        udevadm settle
        echo 1 >/sys/block/${1#/dev/}/device/rescan
    } 2>/dev/null || true
}

is_efi() {
    [ -d /sys/firmware/efi/ ]
}

is_use_cloud_image() {
    [ -n "$cloud_image" ] && [ "$cloud_image" = 1 ]
}

setup_nginx() {
    apk add nginx
    cat <<EOF >/etc/nginx/http.d/default.conf
        server {
            listen 80 default_server;
            listen [::]:80 default_server;

            location = / {
                root /;
                try_files /reinstall.html /reinstall.html;
                # types {
                #     text/plain log;
                # }
            }
        }
EOF
    # rc-service nginx start
    if pgrep nginx >/dev/null; then
        nginx -s reload
    else
        nginx
    fi
}

setup_nginx_if_enough_ram() {
    total_ram=$(free -m | awk '{print $2}' | sed -n '2p')
    # 避免后面没内存安装程序，谨慎起见，512内存才安装
    if [ $total_ram -gt 400 ]; then
        # lighttpd 虽然运行占用内存少，但安装占用空间大
        # setup_lighttpd
        setup_nginx
    fi
}

setup_lighttpd() {
    apk add lighttpd
    ln -sf /reinstall.html /var/www/localhost/htdocs/index.html
    rc-service lighttpd start
}

# 最后一个 tty 是主tty，显示的信息最多
# 有些平台例如 aws/gcp 只能截图，不能输入（没有鼠标）
# 所以如果有显示器且有鼠标，tty0 放最后面，否则 tty0 放前面
get_ttys() {
    prefix=$1
    # shellcheck disable=SC2154
    wget $confhome/ttys.sh -O- | sh -s $prefix
}

setup_tty_and_log() {
    cat <<EOF >/reinstall.html
<!DOCTYPE html>
<html lang="en">

<head>
    <meta http-equiv="refresh" content="2">
</head>

<body>
    <script>
        window.onload = function() {
            // history.scrollRestoration = "manual";
            window.scrollTo(0, document.body.scrollHeight);
        }
    </script>
    <pre>
EOF
    # 显示输出到前台
    # script -f /dev/tty0
    dev_ttys=$(get_ttys /dev/)
    exec > >(tee -a $dev_ttys /reinstall.html) 2>&1
}

extract_env_from_cmdline() {
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
}

qemu_nbd() {
    command qemu-nbd "$@"
    sleep 5
}

mod_motd() {
    cat <<EOF >/etc/motd
Reinstalling...
Run "tail -f /reinstall.html" to view logs.
EOF
}

# 可能脚本不是首次运行，先清理之前的残留
clear_previous() {
    {
        # TODO: fuser and kill
        qemu_nbd -d /dev/nbd0
        swapoff -a
        # alpine 自带的umount没有-R，除非安装了util-linux
        umount -R /iso /wim /installer /os/installer /os /nbd /nbd-boot /nbd-efi /mnt
        umount /iso /wim /installer /os/installer /os /nbd /nbd-boot /nbd-efi /mnt
    } 2>/dev/null || true
}

get_virt_to() {
    if [ -z "$_virt" ]; then
        apk add virt-what
        _virt="$(virt-what)"
        apk del virt-what
    fi
    eval "$1='$_virt'"
}

is_virt() {
    get_virt_to virt
    [ -n "$virt" ]
}

get_ra_to() {
    if [ -z "$_ra" ]; then
        apk add ndisc6
        # 有时会重复收取，所以设置收一份后退出
        _ra="$(rdisc6 -1 eth0)"
        apk del ndisc6
    fi
    eval "$1='$_ra'"
}

get_netconf_to() {
    case "$1" in
    slaac | dhcpv6 | rdnss) get_ra_to ra ;;
    esac

    # shellcheck disable=SC2154
    case "$1" in
    slaac) echo "$ra" | grep 'Autonomous address conf' | grep Yes && res=1 || res=0 ;;
    dhcpv6) echo "$ra" | grep 'Stateful address conf' | grep Yes && res=1 || res=0 ;;
    rdnss) res=$(echo "$ra" | grep 'Recursive DNS server' | cut -d: -f2- | xargs) ;;
    *) res=$(cat /dev/$1) ;;
    esac

    eval "$1='$res'"
}

is_dhcpv4() {
    get_netconf_to dhcpv4
    # shellcheck disable=SC2154
    [ "$dhcpv4" = 1 ]
}

is_slaac() {
    get_netconf_to slaac
    # shellcheck disable=SC2154
    [ "$slaac" = 1 ]
}

is_dhcpv6() {
    get_netconf_to dhcpv6
    # shellcheck disable=SC2154
    [ "$dhcpv6" = 1 ]
}

insert_into_file() {
    file=$1
    location=$2
    regex_to_find=$3

    line_num=$(grep -E -n "$regex_to_find" "$file" | cut -d: -f1)
    if [ "$location" = before ]; then
        line_num=$((line_num - 1))
    elif ! [ "$location" = after ]; then
        return 1
    fi

    sed -i "${line_num}r /dev/stdin" "$file"
}

install_alpine() {
    # 网络
    # 坑1 udhcpc下，ip -4 addr 无法知道是否是 dhcp
    # 坑2 udhcpc不支持dhcpv6
    # 坑3 dhcpcd的slaac默认开了隐私保护，造成ip和后台面板不一致

    # slaac方案1: udhcpc + rdnssd
    # slaac方案2: dhcpcd + 关闭隐私保护
    # dhcpv6方案: dhcpcd

    # 综合使用dhcpcd方案
    # 1 无需改动/etc/network/interfaces，自动根据ra使用slaac和dhcpv6
    # 2 自带rdnss支持
    # 3 唯一要做的是关闭隐私保护

    # 安装 dhcpcd
    apk add dhcpcd
    sed -i '/^slaac private/s/^/#/' /etc/dhcpcd.conf
    sed -i '/^#slaac hwaddr/s/^#//' /etc/dhcpcd.conf
    rc-update add networking boot

    # 生成 lo配置 + eth0头部
    cat <<EOF >/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
EOF

    # 生成 ipv4 配置
    if is_dhcpv4; then
        echo "iface eth0 inet dhcp" >>/etc/network/interfaces
    else
        get_netconf_to ipv4_addr
        get_netconf_to ipv4_gateway
        if [ -n "$ipv4_addr" ]; then
            # shellcheck disable=SC2154
            cat <<EOF >>/etc/network/interfaces
iface eth0 inet static
    address $ipv4_addr
    gateway $ipv4_gateway
EOF
        fi
    fi

    # 生成 ipv6 配置
    # slaac 或者 dhcpv6，实测不用写配置
    if false; then
        if is_slaac; then
            echo 'iface eth0 inet6 auto' >>/etc/network/interfaces
        fi

        if is_dhcpv6; then
            echo 'iface eth0 inet6 dhcp' >>/etc/network/interfaces
        fi
    fi

    # 静态
    if ! is_slaac && ! is_dhcpv6; then
        get_netconf_to ipv6_addr
        get_netconf_to ipv6_gateway
        if [ -n "$ipv6_addr" ]; then
            # shellcheck disable=SC2154
            cat <<EOF >>/etc/network/interfaces
iface eth0 inet6 static
    address $ipv6_addr
    gateway $ipv6_gateway
EOF
            # 如果有rdnss，则删除自己添加的dns，再添加rdnss
            # 也有可能 dhcpcd 会自动设置，但没环境测试
            get_netconf_to rdnss
            if [ -n "$rdnss" ]; then
                sed -i '/^[[:blank:]]*nameserver[[:blank:]].*:/d' /etc/resolv.conf
                echo "nameserver $rdnss" >>/etc/resolv.conf
            fi
        fi
    fi

    # 显示网络配置
    echo
    ip addr | cat -n
    echo
    echo "$ra" | cat -n
    echo
    cat -n /etc/network/interfaces
    echo

    # 设置
    setup-keymap us us
    setup-timezone -i Asia/Shanghai
    setup-ntp chrony || true

    # 在 arm netboot initramfs init 中
    # 如果识别到rtc硬件，就往系统添加hwclock服务，否则添加swclock
    # 这个设置也被复制到安装的系统中
    # 但是从initramfs chroot到真正的系统后，是能识别rtc硬件的
    # 所以我们手动改用hwclock修复这个问题
    rc-update del swclock boot || true
    rc-update add hwclock boot

    # 通过 setup-alpine 安装会多启用几个服务
    # https://github.com/alpinelinux/alpine-conf/blob/c5131e9a038b09881d3d44fb35e86851e406c756/setup-alpine.in#L189
    # acpid | default
    # crond | default
    # seedrng | boot
    if [ -e /dev/input/event0 ]; then
        rc-update add acpid
    fi
    rc-update add crond
    rc-update add seedrng boot

    # 如果是 vm 就用 virt 内核
    if is_virt; then
        kernel_flavor="virt"
    else
        kernel_flavor="lts"
    fi

    # 重置为官方仓库配置
    true >/etc/apk/repositories
    setup-apkrepos -1

    # 安装到硬盘
    # alpine默认使用 syslinux (efi 环境除外)，这里强制使用 grub，方便用脚本再次重装
    KERNELOPTS="$(get_ttys console=)"
    export KERNELOPTS
    export BOOTLOADER="grub"
    printf 'y' | setup-disk -m sys -k $kernel_flavor -s 0 /dev/$xda
}

# shellcheck disable=SC2154
install_dd() {
    case "$img_type" in
    gzip) prog=gzip ;;
    xz) prog=xz ;;
    esac

    if [ -n "$prog" ]; then
        # alpine busybox 自带 gzip xz，但官方版也许性能更好
        # wget -O- $img | $prog -dc >/dev/$xda
        apk add curl $prog
        # curl -L $img | $prog -dc | dd of=/dev/$xda bs=1M
        curl -L $img | $prog -dc >/dev/$xda
        sync
    else
        error_and_exit 'Not supported'
    fi
}

is_xda_gt_2t() {
    disk_size=$(blockdev --getsize64 /dev/$xda)
    disk_2t=$((2 * 1024 * 1024 * 1024 * 1024))
    [ "$disk_size" -gt "$disk_2t" ]
}

create_part() {
    # 目标系统非 alpine 和 dd
    # 脚本开始
    apk add util-linux aria2 grub udev hdparm e2fsprogs curl parted

    # 打开dev才能刷新分区名
    rc-service udev start

    # 反激活 lvm
    # alpine live 不需要
    false && vgchange -an

    # 移除 lsblk 显示的分区
    partx -d /dev/$xda || true

    # 清除分区签名
    wipefs -a /dev/$xda

    # xda*1 星号用于 nvme0n1p1 的字母 p
    # shellcheck disable=SC2154
    if [ "$distro" = windows ]; then
        apk add ntfs-3g-progs virt-what wimlib rsync dos2unix
        # 虽然ntfs3不需要fuse，但wimmount需要，所以还是要保留
        modprobe fuse ntfs3
        if is_efi; then
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

            mkfs.fat -n efi /dev/$xda*1              #1 efi
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
    elif is_use_cloud_image; then
        # 这几个系统不使用dd，而是复制文件，因为dd这几个系统的qcow2需要10g硬盘
        if { [ "$distro" = centos ] || [ "$distro" = alma ] || [ "$distro" = rocky ]; }; then
            apk add dosfstools e2fsprogs
            if is_efi; then
                parted /dev/$xda -s -- \
                    mklabel gpt \
                    mkpart '" "' fat32 1MiB 601MiB \
                    mkpart '" "' xfs 601MiB -2GiB \
                    mkpart '" "' ext4 -2GiB 100% \
                    set 1 esp on
                update_part /dev/$xda

                mkfs.fat -n efi /dev/$xda*1           #1 efi
                echo                                  #2 os 用目标系统的格式化工具
                mkfs.ext4 -F -L installer /dev/$xda*3 #3 installer
            else
                parted /dev/$xda -s -- \
                    mklabel gpt \
                    mkpart '" "' ext4 1MiB 2MiB \
                    mkpart '" "' xfs 2MiB -2GiB \
                    mkpart '" "' ext4 -2GiB 100% \
                    set 1 bios_grub on
                update_part /dev/$xda

                echo                                  #1 bios_boot
                echo                                  #2 os 用目标系统的格式化工具
                mkfs.ext4 -F -L installer /dev/$xda*3 #3 installer
            fi
        else
            # gentoo 的镜像解压后是 3.5g，因此设置 installer 分区 1g，这样才能在5g硬盘上安装
            [ "$distro" = gentoo ] && installer_part_size=1GiB || installer_part_size=2GiB
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' ext4 1MiB -$installer_part_size \
                mkpart '" "' ext4 -$installer_part_size 100%
            update_part /dev/$xda

            mkfs.ext4 -F -L os /dev/$xda*1        #1 os
            mkfs.ext4 -F -L installer /dev/$xda*2 #2 installer
        fi
    else
        # 安装红帽系或ubuntu
        # 对于红帽系是临时分区表，安装时除了 installer 分区，其他分区会重建为默认的大小
        # 对于ubuntu是最终分区表，因为 ubuntu 的安装器不能调整个别分区，只能重建整个分区表
        # installer 2g分区用fat格式刚好塞得下ubuntu-22.04.3 iso，而ext4塞不下或者需要改参数
        apk add dosfstools
        if is_efi; then
            # efi
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' fat32 1MiB 1025MiB \
                mkpart '" "' ext4 1025MiB -2GiB \
                mkpart '" "' ext4 -2GiB 100% \
                set 1 boot on
            update_part /dev/$xda

            mkfs.fat -n efi /dev/$xda*1       #1 efi
            mkfs.ext4 -F -L os /dev/$xda*2    #2 os
            mkfs.fat -n installer /dev/$xda*3 #3 installer
        elif is_xda_gt_2t; then
            # bios > 2t
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' ext4 1MiB 2MiB \
                mkpart '" "' ext4 2MiB -2GiB \
                mkpart '" "' ext4 -2GiB 100% \
                set 1 bios_grub on
            update_part /dev/$xda

            echo                              #1 bios_boot
            mkfs.ext4 -F -L os /dev/$xda*2    #2 os
            mkfs.fat -n installer /dev/$xda*3 #3 installer
        else
            # bios
            parted /dev/$xda -s -- \
                mklabel msdos \
                mkpart primary ext4 1MiB -2GiB \
                mkpart primary ext4 -2GiB 100% \
                set 1 boot on
            update_part /dev/$xda

            mkfs.ext4 -F -L os /dev/$xda*1    #1 os
            mkfs.fat -n installer /dev/$xda*2 #2 installer
        fi
        update_part /dev/$xda

        # centos 7 无法加载alpine格式化的ext4
        # 要关闭这个属性
        # 目前改用fat格式，不用设置这个
        if false && [ "$distro" = centos ]; then
            apk add e2fsprogs-extra
            tune2fs -O ^metadata_csum_seed /dev/disk/by-label/installer
        fi
    fi

    update_part /dev/$xda
}

mount_pseudo_fs() {
    os_dir=$1

    # https://wiki.archlinux.org/title/Chroot#Using_chroot
    mount -t proc /proc $os_dir/proc/
    mount -t sysfs /sys $os_dir/sys/
    mount --rbind /dev $os_dir/dev/
    mount --rbind /run $os_dir/run/
    if is_efi; then
        mount --rbind /sys/firmware/efi/efivars $os_dir/sys/firmware/efi/efivars/
    fi
}

create_cloud_init_network_config() {
    ci_file=$1

    get_netconf_to mac_addr

    # TODO: 没在windows下获取网络信息,先跳过cloud-init网络，不然网络不通
    [ -z "$mac_addr" ] && return

    get_netconf_to ipv4_addr
    get_netconf_to ipv4_gateway
    get_netconf_to ipv6_addr
    get_netconf_to ipv6_gateway

    # shellcheck disable=SC2154
    is_dhcpv4 && dhcp4=true || dhcp4=false
    (is_dhcpv6 || is_slaac) && dhcp6=true || dhcp6=false
    cat <<EOF >>$ci_file
network:
  version: 2
  ethernets:
    eth0:
      match:
        macaddress: "$mac_addr"
      dhcp4: $dhcp4
      dhcp6: $dhcp6
      addresses:
        - $ipv4_addr @ipv4_addr
        - $ipv6_addr @ipv6_addr
      gateway4: $ipv4_gateway @ipv4_gateway
      gateway6: $ipv6_gateway @ipv6_gateway
      nameservers:
        addresses: @dns_addrs
EOF

    if is_dhcpv4 || [ -z "$ipv4_addr" ]; then
        sed -i '/@ipv4/d' $ci_file
    fi

    if is_slaac || is_dhcpv6 || [ -z "$ipv6_addr" ]; then
        sed -i '/@ipv6/d' $ci_file
    fi

    if ! grep '@ipv._addr' $ci_file; then
        sed -i '/addresses:/d' $ci_file
    fi

    # dns
    dns_list=$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}')
    unset dns4_list dns6_list
    if ! is_dhcpv4; then
        dns4_list=$(echo "$dns_list" | grep '\.' || true)
    fi
    if ! (is_slaac || is_dhcpv6); then
        dns6_list=$(echo "$dns_list" | grep ':' || true)
    fi

    is_have_dns=false
    for cur in $dns4_list $dns6_list; do
        is_have_dns=true
        echo "          - $cur" >>$ci_file
    done

    if ! $is_have_dns; then
        sed -i '/nameservers:/d' $ci_file
        sed -i '/@dns_addrs/d' $ci_file
    fi

    sed -Ei "s/@(ip|dns).*//" $ci_file

}

download_cloud_init_config() {
    os_dir=$1
    ci_file=$os_dir/etc/cloud/cloud.cfg.d/99_nocloud.cfg

    # shellcheck disable=SC2154
    download $confhome/nocloud.yaml $ci_file

    # swapfile
    # 如果分区表中已经有swap就跳过，例如arch
    if ! grep -w swap $os_dir/etc/fstab; then
        # btrfs
        if mount | grep 'on /os type btrfs'; then
            insert_into_file $ci_file after '^runcmd:' <<EOF
  - btrfs filesystem mkswapfile --size 1G /swapfile
  - swapon /swapfile
  - echo "/swapfile none swap defaults 0 0" >> /etc/fstab
EOF
        else
            # ext4 xfs
            cat <<EOF >>$ci_file
swap:
  filename: /swapfile
  size: auto
EOF
        fi
    fi

    create_cloud_init_network_config $ci_file
    cat -n $ci_file
}

modify_dd_os() {
    find_and_mount() {
        mount_point=$1

        mount_dev=$(awk "\$2==\"$mount_point\" {print \$1}" $os_dir/etc/fstab)
        if [ -n "$mount_dev" ]; then
            mount $mount_dev $os_dir$mount_point
        fi
    }

    apk add lsblk
    mkdir -p /os
    # 按分区容量大到小，依次寻找系统分区
    for part in $(lsblk /dev/$xda --sort SIZE -no NAME | sed '$d' | tac); do
        # btrfs挂载的是默认子卷，如果没有默认子卷，挂载的是根目录
        # fedora 云镜像没有默认子卷，且系统在root子卷中
        if mount /dev/$part /os; then
            if etc_dir=$({ ls -d /os/etc || ls -d /os/*/etc; } 2>/dev/null); then
                os_dir=$(dirname $etc_dir)
                break
            fi
            umount /os
        fi
    done

    if [ -z "$os_dir" ]; then
        error_and_exit "can't find os partition"
    fi

    download_cloud_init_config $os_dir

    # 为红帽系禁用 selinux kdump
    if [ -f $os_dir/etc/redhat-release ]; then
        find_and_mount /boot
        find_and_mount /boot/efi
        disable_selinux_kdump $os_dir
    fi

    # opensuse tumbleweed 需安装 wicked
    if grep opensuse-tumbleweed $os_dir/etc/os-release; then
        cp -f /etc/resolv.conf $os_dir/etc/resolv.conf
        mount_pseudo_fs $os_dir
        chroot $os_dir zypper install -y wicked
        rm -f $os_dir/etc/resolv.conf
    fi

    # gentoo
    if [ -f $os_dir/etc/gentoo-release ]; then
        # 挂载伪文件系统
        mount_pseudo_fs $os_dir

        # 在这里修改密码，而不是用cloud-init，因为我们的默认密码太弱
        sed -i 's/enforce=everyone/enforce=none/' $os_dir/etc/security/passwdqc.conf
        echo 'root:123@@@' | chroot $os_dir chpasswd >/dev/null
        sed -i 's/enforce=none/enforce=everyone/' $os_dir/etc/security/passwdqc.conf

        # 下载仓库，选择 profile
        if false && [ ! -d $os_dir/var/db/repos/gentoo/ ]; then
            cp -f /etc/resolv.conf $os_dir/etc/resolv.conf

            chroot $os_dir emerge-webrsync
            profile=$(chroot $os_dir eselect profile list | grep '/[0-9\.]*/systemd (stable)' | awk '{print $2}')
            chroot $os_dir eselect profile set $profile
        fi

        # 删除 resolv.conf，不然 systemd-resolved 无法创建软链接
        rm -f $os_dir/etc/resolv.conf

        # 启用网络服务
        chroot $os_dir systemctl enable systemd-networkd
        chroot $os_dir systemctl enable systemd-resolved

        # systemd-networkd 有时不会运行
        # https://bugs.gentoo.org/910404 补丁好像没用
        # https://github.com/systemd/systemd/issues/27718#issuecomment-1564877478
        # 临时的解决办法是运行 networkctl，如果启用了systemd-networkd服务，会运行服务
        insert_into_file $os_dir/lib/systemd/system/systemd-logind.service after '\[Service\]' <<EOF
ExecStartPost=-networkctl
EOF
    fi
}

install_cloud_image_by_dd() {
    apk add util-linux udev hdparm curl
    rc-service udev start
    install_dd
    update_part /dev/$xda
    modify_dd_os
}

create_swap() {
    swapfile=$1
    if ! grep $swapfile /proc/swaps; then
        apk add util-linux
        ram_size=$(lsmem -b 2>/dev/null | grep 'Total online memory:' | awk '{ print $NF/1024/1024 }')
        if [ -z $ram_size ] || [ $ram_size -lt 1024 ]; then
            fallocate -l 512M $swapfile
            chmod 0600 $swapfile
            mkswap $swapfile
            swapon $swapfile
        fi
    fi
}

disable_selinux_kdump() {
    os_dir=$1
    releasever=$(awk -F: '{ print $5 }' <$os_dir/etc/system-release-cpe)

    if ! chroot $os_dir command -v grubby; then
        if [ "$releasever" = 7 ]; then
            chroot $os_dir yum -y --disablerepo=* --enablerepo=base,updates grubby
        else
            chroot $os_dir dnf -y --disablerepo=* --enablerepo=baseos --setopt=install_weak_deps=False grubby
        fi
    fi

    # selinux
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' $os_dir/etc/selinux/config
    # https://access.redhat.com/solutions/3176
    if [ "$releasever" -ge 9 ]; then
        chroot $os_dir grubby --update-kernel ALL --args selinux=0
    fi

    # kdump
    chroot $os_dir grubby --update-kernel ALL --args crashkernel=no
    if [ "$releasever" -eq 7 ]; then
        # el7 上面那条 grubby 命令不能设置 /etc/default/grub
        sed -iE 's/crashkernel=[^ "]*/crashkernel=no/' $os_dir/etc/default/grub
    fi
    rm -rf $os_dir/etc/systemd/system/multi-user.target.wants/kdump.service
}

install_cloud_image() {
    apk add qemu-img lsblk

    mkdir -p /installer
    mount /dev/disk/by-label/installer /installer
    qcow_file=/installer/cloud_image.qcow2
    download $img $qcow_file

    # centos/alma/rocky cloud image系统分区是8~9g xfs，而我们的目标是能在5g硬盘上运行，因此改成复制系统文件
    if [ "$distro" = "centos" ] || [ "$distro" = "alma" ] || [ "$distro" = "rocky" ]; then
        yum() {
            if [ "$releasever" = 7 ]; then
                chroot /os/ yum -y --disablerepo=* --enablerepo=base,updates "$@"
            else
                chroot /os/ dnf -y --disablerepo=* --enablerepo=baseos --setopt=install_weak_deps=False "$@"
            fi
        }

        modprobe nbd
        qemu_nbd -c /dev/nbd0 $qcow_file

        # TODO: 改成循环mount找出os+fstab查找剩余分区？
        os_part=$(lsblk /dev/nbd0p*[0-9] --sort SIZE -no NAME,FSTYPE | grep xfs | tail -1 | cut -d' ' -f1)
        efi_part=$(lsblk /dev/nbd0p*[0-9] --sort SIZE -no NAME,FSTYPE | grep fat | tail -1 | cut -d' ' -f1)
        boot_part=$(lsblk /dev/nbd0p*[0-9] --sort SIZE -no NAME,FSTYPE | grep xfs | sed '$d' | tail -1 | cut -d' ' -f1)

        os_part_uuid=$(lsblk /dev/$os_part -no UUID)
        if [ -n "$efi_part" ]; then
            efi_part_uuid=$(lsblk /dev/$efi_part -no UUID)
        fi

        mkdir -p /nbd /nbd-boot /nbd-efi /os

        # 使用目标系统的格式化程序
        # centos8 如果用alpine格式化xfs，grub2-mkconfig和grub2里面都无法识别xfs分区
        mount -o nouuid /dev/$os_part /nbd/
        mount_pseudo_fs /nbd/
        chroot /nbd mkfs.xfs -f -m uuid=$os_part_uuid /dev/$xda*2
        umount -R /nbd/

        # 复制系统
        echo Copying os partition
        mount -o ro,nouuid /dev/$os_part /nbd/
        mount -o noatime /dev/$xda*2 /os/
        cp -a /nbd/* /os/

        # 复制boot分区，如果有
        if [ -n "$boot_part" ]; then
            echo Copying boot partition
            mount -o ro,nouuid /dev/$boot_part /nbd-boot/
            cp -a /nbd-boot/* /os/boot/
        fi

        # efi 分区
        efi_mount_opts="defaults,uid=0,gid=0,umask=077,shortname=winnt"
        if is_efi; then
            # 挂载 efi
            mkdir -p /os/boot/efi/
            mount -o $efi_mount_opts /dev/$xda*1 /os/boot/efi/

            # 复制文件
            if [ -n "$efi_part" ]; then
                echo Copying efi partition
                mount -o ro /dev/$efi_part /nbd-efi/
                cp -a /nbd-efi/* /os/boot/efi/
            fi
        fi

        # 取消挂载 nbd
        umount /nbd/ /nbd-boot/ /nbd-efi/ || true
        qemu_nbd -d /dev/nbd0

        # 如果镜像有efi分区，复制其uuid
        # 如果有相同uuid的fat分区，则无法挂载
        # 所以要先复制efi分区，断开nbd再复制uuid
        if is_efi && [ -n "$efi_part_uuid" ]; then
            umount /os/boot/efi/
            apk add mtools
            mlabel -N "$(echo $efi_part_uuid | sed 's/-//')" -i /dev/$xda*1
            update_part /dev/$xda
            mount -o $efi_mount_opts /dev/$xda*1 /os/boot/efi/
        fi

        # 挂载伪文件系统
        mount_pseudo_fs /os/

        # 创建 swap
        rm -rf /installer/*
        create_swap /installer/swapfile

        # resolv.conf
        mv /os/etc/resolv.conf /os/etc/resolv.conf.orig
        cp /etc/resolv.conf /os/etc/resolv.conf

        # selinux kdump
        disable_selinux_kdump /os

        # cloud-init
        download_cloud_init_config /os

        # fstab 删除 boot 分区
        # alma/rocky 镜像本身有boot分区，但我们不需要
        sed -i '/[[:blank:]]\/boot[[:blank:]]/d' /os/etc/fstab

        # fstab 添加 efi 分区
        if is_efi; then
            # centos 要创建efi条目
            if ! grep /boot/efi /os/etc/fstab; then
                efi_part_uuid=$(lsblk /dev/$xda*1 -no UUID)
                echo "UUID=$efi_part_uuid /boot/efi vfat $efi_mount_opts 0 0" >>/os/etc/fstab
            fi
        else
            # 删除 efi 条目
            sed -i '/[[:blank:]]\/boot\/efi[[:blank:]]/d' /os/etc/fstab
        fi

        distro_full=$(awk -F: '{ print $3 }' </os/etc/system-release-cpe)
        releasever=$(awk -F: '{ print $5 }' </os/etc/system-release-cpe)

        remove_grub_conflict_files() {
            # bios 和 efi 转换前先删除

            # bios转efi出错
            # centos7是bios镜像，/boot/grub2/grubenv 是真身
            # 安装grub-efi时，grubenv 会改成指向efi分区grubenv软连接
            # 如果安装grub-efi前没有删除原来的grubenv，原来的grubenv将不变，新建的软连接将变成 grubenv.rpmnew
            # 后续grubenv的改动无法同步到efi分区，会造成grub2-setdefault失效

            # efi转bios出错
            # 如果是指向efi目录的软连接（例如el8），先删除它，否则 grub2-install 会报错
            rm -rf /os/boot/grub2/grubenv /os/boot/grub2/grub.cfg
        }

        # 安装 efi 引导
        # 只有centos镜像没有efi，其他系统镜像已经从efi分区复制了文件
        if [ "$distro" = "centos" ] && is_efi; then
            remove_grub_conflict_files
            [ "$(uname -m)" = x86_64 ] && arch=x64 || arch=aa64
            yum install efibootmgr grub2-efi-$arch grub2-efi-$arch-modules shim-$arch
        fi

        # 安装 bios 引导
        if ! is_efi; then
            remove_grub_conflict_files
            yum install grub2-pc grub2-pc-modules
            chroot /os/ grub2-install /dev/$xda
        fi

        # blscfg 启动项
        # rocky/alma镜像是独立的boot分区，但我们不是
        # 因此要添加boot目录
        if [ -d /os/boot/loader/entries/ ] && ! grep -q 'initrd /boot/' /os/boot/loader/entries/*.conf; then
            sed -i -E 's,((linux|initrd) /),\1boot/,g' /os/boot/loader/entries/*.conf
        fi

        # efi 分区 grub.cfg
        # https://github.com/rhinstaller/anaconda/blob/346b932a26a19b339e9073c049b08bdef7f166c3/pyanaconda/modules/storage/bootloader/efi.py#L198
        if is_efi && [ "$releasever" -ge 9 ]; then
            cat <<EOF >/os/boot/efi/EFI/$distro_full/grub.cfg
                    search --no-floppy --fs-uuid --set=dev $os_part_uuid
                    set prefix=(\$dev)/boot/grub2
                    export \$prefix
                    configfile \$prefix/grub.cfg
EOF
        fi

        # 主 grub.cfg
        if is_efi && [ "$releasever" -le 8 ]; then
            chroot /os/ grub2-mkconfig -o /boot/efi/EFI/$distro_full/grub.cfg
        else
            chroot /os/ grub2-mkconfig -o /boot/grub2/grub.cfg
        fi

        # 还原 resolv.conf
        mv /os/etc/resolv.conf.orig /os/etc/resolv.conf

        # 删除installer分区，重启后cloud init会自动扩容
        swapoff -a
        umount /installer
        parted /dev/$xda -s rm 3

    else
        # debian ubuntu arch opensuse gentoo
        if true; then
            modprobe nbd
            qemu_nbd -c /dev/nbd0 $qcow_file

            # 检查最后一个分区是否是 btrfs
            # 即使awk结果为空，返回值也是0，加上 grep . 检查是否结果为空
            if part_num=$(parted /dev/nbd0 -s print | awk NF | tail -1 | grep btrfs | awk '{print $1}' | grep .); then
                apk add btrfs-progs
                mkdir -p /mnt/btrfs
                mount /dev/nbd0p$part_num /mnt/btrfs

                # 回收空数据块
                btrfs device usage /mnt/btrfs
                btrfs balance start -dusage=0 /mnt/btrfs
                btrfs device usage /mnt/btrfs

                # 计算可以缩小的空间
                free_bytes=$(btrfs device usage /mnt/btrfs -b | grep Unallocated: | awk '{print $2}')
                reserve_bytes=$((100 * 1024 * 1024)) # 预留 100M 可用空间
                skrink_bytes=$((free_bytes - reserve_bytes))

                if [ $skrink_bytes -gt 0 ]; then
                    # 缩小文件系统
                    btrfs filesystem resize -$skrink_bytes /mnt/btrfs
                    # 缩小分区
                    part_start=$(parted /dev/nbd0 -s 'unit b print' | awk "\$1==$part_num {print \$2}" | sed 's/B//')
                    part_size=$(btrfs filesystem usage /mnt/btrfs -b | grep 'Device size:' | awk '{print $3}')
                    part_end=$((part_start + part_size))
                    umount /mnt/btrfs
                    printf "yes" | parted /dev/nbd0 resizepart $part_num ${part_end}B ---pretend-input-tty

                    # 缩小 qcow2
                    qemu_nbd -d /dev/nbd0
                    qemu-img resize --shrink $qcow_file $part_end

                    # 重新连接
                    qemu_nbd -c /dev/nbd0 $qcow_file
                else
                    umount /mnt/btrfs
                fi
            fi

            # 显示分区
            lsblk -o NAME,SIZE,FSTYPE,LABEL /dev/nbd0

            # 将前1M dd到内存
            dd if=/dev/nbd0 of=/first-1M bs=1M count=1

            # 将1M之后 dd到硬盘
            # shellcheck disable=SC2194
            case 3 in
            1)
                # BusyBox dd
                dd if=/dev/nbd0 of=/dev/$xda bs=1M skip=1 seek=1
                ;;
            2)
                # 用原版 dd status=progress，但没有进度和剩余时间
                apk add coreutils
                dd if=/dev/nbd0 of=/dev/$xda bs=1M skip=1 seek=1 status=progress
                ;;
            3)
                # 用 pv
                apk add pv
                pv -f /dev/nbd0 | dd of=/dev/$xda bs=1M skip=1 seek=1 iflag=fullblock
                ;;
            esac

            qemu_nbd -d /dev/nbd0
        else
            # 将前1M dd到内存，将1M之后 dd到硬盘
            qemu-img dd if=$qcow_file of=/first-1M bs=1M count=1
            qemu-img dd if=$qcow_file of=/dev/disk/by-label/os bs=1M skip=1
        fi

        # 将前1M从内存 dd 到硬盘
        umount /installer/
        dd if=/first-1M of=/dev/$xda
        update_part /dev/$xda

        # 提前扩容
        # 1 修复 vultr 512m debian 10/11 generic/genericcloud 首次启动 kernel panic
        # 2 修复 gentoo websync 时空间不足
        if [ "$distro" = debian ] || [ "$distro" = gentoo ]; then
            apk add parted
            if parted /dev/$xda -s print 2>&1 | grep 'Not all of the space'; then
                printf "fix" | parted /dev/$xda print ---pretend-input-tty
                # TODO: 获取 ext4 分区编号
                [ "$distro" = debian ] && system_part_num=1 || system_part_num=3
                printf "yes" | parted /dev/$xda resizepart $system_part_num 100% ---pretend-input-tty
                update_part /dev/$xda

                if [ "$distro" = gentoo ]; then
                    apk add e2fsprogs-extra
                    e2fsck -p -f /dev/$xda$system_part_num
                    resize2fs /dev/$xda$system_part_num
                fi
            fi
        fi

        modify_dd_os
    fi
}

mount_part() {
    # 挂载主分区
    mkdir -p /os
    mount /dev/disk/by-label/os /os

    # 挂载其他分区
    mkdir -p /os/boot/efi
    if is_efi; then
        mount /dev/disk/by-label/efi /os/boot/efi
    fi
    mkdir -p /os/installer
    if [ "$distro" = windows ]; then
        mount_args="-t ntfs3"
    fi
    mount $mount_args /dev/disk/by-label/installer /os/installer
}

install_windows() {
    # shellcheck disable=SC2154
    download $iso /os/windows.iso
    mkdir -p /iso
    mount /os/windows.iso /iso

    # 从iso复制文件
    # efi: 复制boot开头的文件+efi目录到efi分区，复制iso全部文件(除了boot.wim)到installer分区
    # bios: 复制iso全部文件到installer分区
    if is_efi; then
        mkdir -p /os/boot/efi/sources/
        cp -rv /iso/boot* /os/boot/efi/
        cp -rv /iso/efi/ /os/boot/efi/
        cp -rv /iso/sources/boot.wim /os/boot/efi/sources/
        rsync -rv --exclude=/sources/boot.wim /iso/* /os/installer/
        boot_wim=/os/boot/efi/sources/boot.wim
    else
        rsync -rv /iso/* /os/installer/
        boot_wim=/os/installer/sources/boot.wim
    fi

    if [ -e /os/installer/sources/install.esd ]; then
        install_wim=/os/installer/sources/install.esd
    else
        install_wim=/os/installer/sources/install.wim
    fi

    # 匹配映像版本
    # 需要整行匹配，因为要区分 Windows 10 Pro 和 Windows 10 Pro for Workstations
    # TODO: 如果无法匹配，等待用户输入？安装第一个？
    image_count=$(wiminfo $install_wim | grep "Image Count:" | cut -d: -f2 | xargs)
    if [ "$image_count" = 1 ]; then
        # 只有一个版本就使用第一个版本
        image_name=$(wiminfo $install_wim | grep -ix "Name:[[:blank:]]*.*" | cut -d: -f2 | xargs)
    else
        # 否则改成正确的大小写
        image_name=$(wiminfo $install_wim | grep -ix "Name:[[:blank:]]*$image_name" | cut -d: -f2 | xargs)
    fi

    is_win7_or_win2008r2() {
        echo $image_name | grep -iEw '^Windows (7|Server 2008 R2)'
    }

    # 变量名     使用场景
    # arch_uname uname -m                      x86_64  aarch64
    # arch_wim   wiminfo                  x86  x86_64  ARM64
    # arch       virtio驱动/unattend.xml  x86  amd64   arm64
    # arch_xen   xen驱动                  x86  x64

    # 将 wim 的 arch 转为驱动和应答文件的 arch
    arch_wim=$(wiminfo $install_wim 1 | grep Architecture: | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
    case "$arch_wim" in
    x86)
        arch=x86
        arch_xen=x86
        ;;
    x86_64)
        arch=amd64
        arch_xen=x64
        ;;
    arm64)
        arch=arm64
        arch_xen= # xen 没有 arm64 驱动
        ;;
    esac

    # virt-what 要用最新版
    # vultr 1G High Frequency LAX 实际上是 kvm
    # debian 11 virt-what 1.19 显示为 hyperv qemu
    # debian 11 systemd-detect-virt 显示为 microsoft
    # alpine virt-what 1.25 显示为 kvm
    # 所以不要在原系统上判断具体虚拟化环境

    # lscpu 也可查看虚拟化环境，但 alpine on lightsail 运行结果为 Microsoft
    # 猜测 lscpu 只参考了 cpuid 没参考 dmi
    # 下载 virtio 驱动
    # virt-what 可能会输出多行结果，因此用 grep
    drv=/os/drivers
    mkdir -p $drv
    if virt-what | grep aws &&
        virt-what | grep kvm &&
        [ "$arch_wim" = x86_64 ]; then
        # aws nitro
        # 只有 x64 位驱动
        # https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/migrating-latest-types.html
        apk add unzip
        if is_win7_or_win2008r2; then
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/NVMe/1.3.2/AWSNVMe.zip $drv/AWSNVMe.zip
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/ENA/x64/2.2.3/AwsEnaNetworkDriver.zip $drv/AwsEnaNetworkDriver.zip
        else
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/NVMe/Latest/AWSNVMe.zip $drv/AWSNVMe.zip
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/ENA/Latest/AwsEnaNetworkDriver.zip $drv/AwsEnaNetworkDriver.zip
        fi
        unzip -o -d $drv/aws/ $drv/AWSNVMe.zip
        unzip -o -d $drv/aws/ $drv/AwsEnaNetworkDriver.zip

    elif virt-what | grep aws &&
        virt-what | grep xen &&
        [ "$arch_wim" = x86_64 ]; then
        # aws xen
        # 只有 64 位驱动
        # 未测试
        # https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/Upgrading_PV_drivers.html
        apk add unzip msitools

        if is_win7_or_win2008r2; then
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/AWSPV/8.3.5/AWSPVDriver.zip $drv/AWSPVDriver.zip
        else
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/AWSPV/Latest/AWSPVDriver.zip $drv/AWSPVDriver.zip
        fi

        unzip -o -d $drv $drv/AWSPVDriver.zip
        msiextract $drv/AWSPVDriverSetup.msi -C $drv
        mkdir -p $drv/aws/
        cp -rf $drv/.Drivers/* $drv/aws/

    elif virt-what | grep xen &&
        [ "$arch_wim" != arm64 ]; then
        # xen
        # 有 x86 x64，没arm64驱动
        # https://xenbits.xenproject.org/pvdrivers/win/
        ver='9.0.0'
        # 在 aws t2 上测试，安装 xenbus 会蓝屏，装了其他7个驱动后，能进系统但没网络
        # 但 aws 应该用aws官方xen驱动，所以测试仅供参考
        parts='xenbus xencons xenhid xeniface xennet xenvbd xenvif xenvkbd'
        mkdir -p $drv/xen/
        for part in $parts; do
            download https://xenbits.xenproject.org/pvdrivers/win/$ver/$part.tar $drv/$part.tar
            tar -xf $drv/$part.tar -C $drv/xen/
        done

    elif virt-what | grep kvm; then
        # virtio
        # x86 x64 arm64 都有
        # https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/
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
        'windows vista'*) sys=2k8 ;; # virtio 没有 vista 专用驱动
        esac

        case "$sys" in
        # https://github.com/virtio-win/virtio-win-pkg-scripts/issues/40
        w7) dir=archive-virtio/virtio-win-0.1.173-9 ;;
        # https://github.com/virtio-win/virtio-win-pkg-scripts/issues/61
        2k12*) dir=archive-virtio/virtio-win-0.1.215-1 ;;
        *) dir=stable-virtio ;;
        esac

        download https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/$dir/virtio-win.iso $drv/virtio-win.iso
        mkdir -p $drv/virtio
        mount $drv/virtio-win.iso $drv/virtio
    fi

    # 修改应答文件
    download $confhome/windows.xml /tmp/Autounattend.xml
    locale=$(wiminfo $install_wim | grep 'Default Language' | head -1 | awk '{print $NF}')
    sed -i "s|%arch%|$arch|; s|%image_name%|$image_name|; s|%locale%|$locale|" /tmp/Autounattend.xml

    # 修改应答文件，分区配置
    if is_efi; then
        sed -i "s|%installto_partitionid%|3|" /tmp/Autounattend.xml
        insert_into_file /tmp/Autounattend.xml after '<ModifyPartitions>' <<EOF
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
        insert_into_file /tmp/Autounattend.xml after '<ModifyPartitions>' <<EOF
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
    mkdir -p /wim
    wimmountrw $boot_wim 2 /wim/

    cp_drivers() {
        src=$1
        dist=$2
        path=$3
        [ -n "$path" ] && filter="-ipath $path" || filter=""
        find $src \
            $filter \
            -type f \
            -not -iname "*.pdb" \
            -not -iname "dpinst.exe" \
            -exec /bin/cp -rfv {} $dist \;
    }

    # 添加驱动
    mkdir -p /wim/drivers

    [ -d $drv/virtio ] && cp_drivers $drv/virtio /wim/drivers "*/$sys/$arch/*"
    [ -d $drv/aws ] && cp_drivers $drv/aws /wim/drivers
    [ -d $drv/xen ] && cp_drivers $drv/xen /wim/drivers "*/$arch_xen/*"

    # win7 要添加 bootx64.efi 到 efi 目录
    [ $arch = amd64 ] && boot_efi=bootx64.efi || boot_efi=bootaa64.efi
    if is_efi && [ ! -e /os/boot/efi/efi/boot/$boot_efi ]; then
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
    # TODO: 由于esd文件无法修改，要将resize.bat放到boot.wim
    if [[ "$install_wim" = "*.wim" ]]; then
        wimmountrw $install_wim "$image_name" /wim/
        download $confhome/resize.bat /wim/resize.bat
        wimunmount --commit /wim/
    fi

    # 添加引导
    if is_efi; then
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
}

install_redhat_ubuntu() {
    # 安装 grub2
    if is_efi; then
        # 注意低版本的grub无法启动f38 arm的内核
        # https://forums.fedoraforum.org/showthread.php?330104-aarch64-pxeboot-vmlinuz-file-format-changed-broke-PXE-installs

        apk add grub-efi efibootmgr
        grub-install --efi-directory=/os/boot/efi --boot-directory=/os/boot

        # 添加 netboot 备用
        arch_uname=$(uname -m)
        cd /os/boot/efi
        if [ "$arch_uname" = aarch64 ]; then
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

    # 安装红帽系时，只有最后一个有安装界面显示
    # https://anaconda-installer.readthedocs.io/en/latest/boot-options.html#console
    console_cmdline=$(get_ttys console=)
    grub_cfg=/os/boot/grub/grub.cfg

    # 新版grub不区分linux/linuxefi
    # shellcheck disable=SC2154
    if [ "$distro" = "ubuntu" ]; then
        download $iso /os/installer/ubuntu.iso

        apk add dmidecode
        dmi=$(dmidecode)
        # https://github.com/systemd/systemd/blob/main/src/basic/virt.c
        # https://github.com/canonical/cloud-init/blob/main/tools/ds-identify
        # http://git.annexia.org/?p=virt-what.git;a=blob;f=virt-what.in;hb=HEAD
        if echo "$dmi" | grep -Eiw "amazon|ec2"; then
            kernel=aws
        elif echo "$dmi" | grep -Eiw "Google Compute Engine|GoogleCloud"; then
            kernel=gcp
        elif echo "$dmi" | grep -Eiw "OracleCloud"; then
            kernel=oracle
        elif echo "$dmi" | grep -Eiw "7783-7084-3265-9085-8269-3286-77"; then
            kernel=azure
        else
            kernel=generic
        fi

        # 正常写法应该是 ds="nocloud-net;s=https://xxx/" 但是甲骨文云的ds更优先，自己的ds根本无访问记录
        # $seed 是 https://xxx/
        cat <<EOF >$grub_cfg
        set timeout=5
        menuentry "reinstall" {
            # https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/1851311
            # rmmod tpm
            search --no-floppy --label --set=root installer
            loopback loop /ubuntu.iso
            linux (loop)/casper/vmlinuz iso-scan/filename=/ubuntu.iso autoinstall noprompt noeject cloud-config-url=$ks $extra_cmdline extra.kernel=$kernel --- $console_cmdline
            initrd (loop)/casper/initrd
        }
EOF
    else
        download $vmlinuz /os/vmlinuz
        download $initrd /os/initrd.img
        download $squashfs /os/installer/install.img

        cat <<EOF >$grub_cfg
        set timeout=5
        menuentry "reinstall" {
            search --no-floppy --label --set=root os
            linux /vmlinuz inst.stage2=hd:LABEL=installer:/install.img inst.ks=$ks $extra_cmdline $console_cmdline
            initrd /initrd.img
        }
EOF
    fi
}

# 脚本入口
# arm要手动从硬件同步时间，避免访问https出错
hwclock -s

# 设置密码，安装并打开 ssh
echo root:123@@@ | chpasswd
printf '\nyes' | setup-sshd

extract_env_from_cmdline
# shellcheck disable=SC2154
if [ "$sleep" = 1 ]; then
    exit
fi

if [ "$distro" != "alpine" ]; then
    mod_motd
fi

setup_tty_and_log
clear_previous
add_community_repo

# 找到主硬盘
# shellcheck disable=SC2010
xda=$(ls /dev/ | grep -Ex 'sda|hda|xda|vda|xvda|nvme0n1')
if [ "$distro" != "alpine" ]; then
    setup_nginx_if_enough_ram
fi

# shellcheck disable=SC2154
if [ "$distro" = "alpine" ]; then
    install_alpine
elif [ "$distro" = "dd" ]; then
    install_dd
elif is_use_cloud_image; then
    if [ "$img_type" = "xz" ] || [ "$img_type" = "gzip" ]; then
        install_cloud_image_by_dd
    else
        create_part
        install_cloud_image
    fi
else
    create_part
    mount_part
    if [ "$distro" = "windows" ]; then
        install_windows
    else
        install_redhat_ubuntu
    fi
fi
if [ "$sleep" = 2 ]; then
    exit
fi
reboot

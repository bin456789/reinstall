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
    if grep -q '^http.*/edge/main$' /etc/apk/repositories; then
        alpine_ver=edge
    else
        alpine_ver=v$(cut -d. -f1,2 </etc/alpine-release)
    fi

    if ! grep -q "^http.*/$alpine_ver/community$" /etc/apk/repositories; then
        mirror=$(grep '^http.*/main$' /etc/apk/repositories | sed 's,/[^/]*/main$,,' | head -1)
        echo $mirror/$alpine_ver/community >>/etc/apk/repositories
    fi
}

# busybox 的 wget 没有重试功能
wget() {
    for i in 1 2 3; do
        command wget "$@" && return
    done
}

is_have_cmd() {
    command -v "$1" >/dev/null
}

download() {
    url=$1
    path=$2
    echo $url

    # 阿里云源禁止 axel 下载，检测 user-agent
    # 有ipv4地址无ipv4网关的情况下，aria2可能会用ipv4下载，而不是ipv6
    # axel 在 lightsail 上会占用大量cpu
    # aria2 下载 fedora 官方镜像链接会将meta4文件下载下来，而且占用了指定文件名，造成重命名失效。而且无法指定目录
    # https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2
    # https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-o

    # 构造 aria2 参数
    # 没有指定文件名的情况
    if [ -z "$path" ]; then
        save=""
    else
        # 文件名是绝对路径
        if [[ "$path" = "/*" ]]; then
            save="-d / -o $path"
        else
            # 文件名是相对路径
            save="-o $path"
        fi
    fi

    # stdbuf 在 coreutils 包里面
    if ! is_have_cmd aria2c; then
        apk add aria2 coreutils
    fi

    # 默认 --max-tries 5
    stdbuf -o0 -e0 aria2c -x4 --allow-overwrite=true --summary-interval=0 $save $url
}

update_part() {
    {
        set +e
        hdparm -z $1
        partprobe $1
        partx -u $1
        udevadm settle
        echo 1 >/sys/block/${1#/dev/}/device/rescan
        set -e
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
    # shellcheck disable=SC2154
    wget $confhome/logviewer.html -O /logviewer.html
    wget $confhome/logviewer-nginx.conf -O /etc/nginx/http.d/default.conf

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

get_xda() {
    # 排除只读盘，vda 放前面
    # 有的机器有sda和vda，vda是主硬盘，另一个盘是只读
    # TODO: 找出容量最大的？
    for _xda in vda xda sda hda xvda nvme0n1; do
        if [ -e "/sys/class/block/$_xda/ro" ] &&
            [ "$(cat /sys/class/block/$_xda/ro)" = 0 ]; then
            echo $_xda
            return
        fi
    done
    return 1
}

setup_tty_and_log() {
    # 显示输出到前台
    # script -f /dev/tty0
    dev_ttys=$(get_ttys /dev/)
    exec > >(tee -a $dev_ttys /reinstall.log) 2>&1
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
        done < <(xargs -n1 </proc/cmdline | grep "^$prefix" | sed "s/^$prefix\.//")
    done
}

qemu_nbd() {
    command qemu-nbd "$@"
    sleep 5
}

mod_motd() {
    # 安装后 alpine 后要恢复默认
    if [ "$distro" = alpine ]; then
        cp /etc/motd /etc/motd.orig
        # shellcheck disable=SC2016
        echo 'mv /etc/motd.orig /etc/motd' |
            insert_into_file /sbin/setup-disk after 'mount -t \$ROOTFS \$root_dev "\$SYSROOT"'
    fi

    cat <<EOF >/etc/motd
Reinstalling...
To view logs run:
tail -fn+1 /reinstall.log
EOF
}

# 可能脚本不是首次运行，先清理之前的残留
clear_previous() {
    {
        # TODO: fuser and kill
        set +e
        qemu_nbd -d /dev/nbd0
        swapoff -a
        # alpine 自带的umount没有-R，除非安装了util-linux
        umount -R /iso /wim /installer /os/installer /os /nbd /nbd-boot /nbd-efi /mnt
        umount /iso /wim /installer /os/installer /os /nbd /nbd-boot /nbd-efi /mnt
        set -e
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
        echo "Gathering network info..."
        _ra="$(rdisc6 -1 eth0)"
        apk del ndisc6
    fi
    eval "$1='$_ra'"
}

get_netconf_to() {
    case "$1" in
    slaac | dhcpv6 | rdnss | other) get_ra_to ra ;;
    esac

    # shellcheck disable=SC2154
    case "$1" in
    slaac) echo "$ra" | grep 'Autonomous address conf' | grep Yes && res=1 || res=0 ;;
    dhcpv6) echo "$ra" | grep 'Stateful address conf' | grep Yes && res=1 || res=0 ;;
    rdnss) res=$(echo "$ra" | grep 'Recursive DNS server' | cut -d: -f2- | xargs) ;;
    other) echo "$ra" | grep 'Stateful other conf' | grep Yes && res=1 || res=0 ;;
    *) res=$(cat /dev/$1) ;;
    esac

    eval "$1='$res'"
}

is_in_china() {
    get_netconf_to is_in_china
    # shellcheck disable=SC2154
    [ "$is_in_china" = 1 ]
}

# 有 dhcpv4 不等于有网关，例如 vultr 纯 ipv6
# 没有 dhcpv4 不等于是静态ip，可能是没有 ip
is_dhcpv4() {
    get_netconf_to dhcpv4
    # shellcheck disable=SC2154
    [ "$dhcpv4" = 1 ]
}

is_staticv4() {
    if ! is_dhcpv4; then
        get_netconf_to ipv4_addr
        get_netconf_to ipv4_gateway
        if [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ]; then
            return 0
        fi
    fi
    return 1
}

is_staticv6() {
    if ! is_slaac && ! is_dhcpv6; then
        get_netconf_to ipv6_addr
        get_netconf_to ipv6_gateway
        if [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ]; then
            return 0
        fi
    fi
    return 1
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

is_have_ipv6() {
    is_slaac || is_dhcpv6 || is_staticv6
}

is_enable_other_flag() {
    get_netconf_to other
    # shellcheck disable=SC2154
    [ "$other" = 1 ]
}

is_have_rdnss() {
    get_netconf_to rdnss
    [ -n "$rdnss" ]
}

is_need_manual_set_dnsv6() {
    # 有没有可能是静态但是有 rdnss？
    is_have_ipv6 && ! is_have_rdnss && ! is_dhcpv6 && ! is_enable_other_flag
}

get_current_dns_v4() {
    grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | grep '\.'
}

get_current_dns_v6() {
    grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | grep ':'
}

to_upper() {
    tr '[:lower:]' '[:upper:]'
}

to_lower() {
    tr '[:upper:]' '[:lower:]'
}

unix2dos() {
    target=$1

    # 先原地unix2dos，出错再用复制，可最大限度保留文件权限
    if ! command unix2dos $target 2>/tmp/error.log; then
        # 出错后删除 unix2dos 创建的临时文件
        rm "$(awk -F: '{print $2}' /tmp/error.log | xargs)"
        tmp=$(mktemp)
        cp $target $tmp
        command unix2dos $tmp
        cp $tmp $target
        rm $tmp
    fi
}

insert_into_file() {
    file=$1
    location=$2
    regex_to_find=$3

    if [ "$location" = HEAD ]; then
        in=$(mktemp)
        cat /dev/stdin >$in
        echo -e "0r $in \n w \n q" | ed $file >/dev/null
    else
        line_num=$(grep -E -n "$regex_to_find" "$file" | cut -d: -f1)

        found_count=$(echo "$line_num" | wc -l)
        if [ ! "$found_count" -eq 1 ]; then
            return 1
        fi

        case "$location" in
        before) line_num=$((line_num - 1)) ;;
        after) ;;
        *) return 1 ;;
        esac

        sed -i "${line_num}r /dev/stdin" "$file"
    fi
}

install_alpine() {
    hack_lowram=true
    if $hack_lowram; then
        # 预先加载需要的模块
        if rc-service modloop status; then
            modules="ext4 vfat nls_utf8 nls_cp437 crc32c"
            for mod in $modules; do
                modprobe $mod
            done
        fi

        # 删除 modloop ，释放内存
        rc-service modloop stop
        rm -f /lib/modloop-lts /lib/modloop-virt

        # 复制一份原版，防止再次运行时出错
        if [ -e /sbin/setup-disk.orig ]; then
            cp -f /sbin/setup-disk.orig /sbin/setup-disk
        else
            cp -f /sbin/setup-disk /sbin/setup-disk.orig
        fi

        # 格式化系统分区、mount 后立即开启 swap
        # shellcheck disable=SC2016
        insert_into_file /sbin/setup-disk after 'mount -t \$ROOTFS \$root_dev "\$SYSROOT"' <<EOF
            fallocate -l 1G /mnt/swapfile
            chmod 0600 /mnt/swapfile
            mkswap /mnt/swapfile
            swapon /mnt/swapfile
            rc-update add swap boot
EOF

        # 安装完成后写入 swapfile 到 fstab
        # shellcheck disable=SC2016
        insert_into_file /sbin/setup-disk after 'install_mounted_root "\$SYSROOT" "\$disks"' <<EOF
            echo "/swapfile swap swap defaults 0 0" >>/mnt/etc/fstab
EOF
    fi

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

    # ipv4
    if is_dhcpv4; then
        echo "iface eth0 inet dhcp" >>/etc/network/interfaces

    elif is_staticv4; then
        get_netconf_to ipv4_addr
        get_netconf_to ipv4_gateway
        cat <<EOF >>/etc/network/interfaces
iface eth0 inet static
    address $ipv4_addr
    gateway $ipv4_gateway
EOF
        # dns
        if list=$(get_current_dns_v4); then
            for dns in $list; do
                cat <<EOF >>/etc/network/interfaces
    dns-nameserver $dns
EOF
            done
        fi
    fi

    # ipv6
    if is_slaac; then
        echo 'iface eth0 inet6 auto' >>/etc/network/interfaces

    elif is_dhcpv6; then
        echo 'iface eth0 inet6 dhcp' >>/etc/network/interfaces

    elif is_staticv6; then
        get_netconf_to ipv6_addr
        get_netconf_to ipv6_gateway
        cat <<EOF >>/etc/network/interfaces
iface eth0 inet6 static
    address $ipv6_addr
    gateway $ipv6_gateway
EOF
    fi

    # dns
    # 有 ipv6 但需设置 dns
    if is_need_manual_set_dnsv6 && list=$(get_current_dns_v6); then
        for dns in $list; do
            cat <<EOF >>/etc/network/interfaces
    dns-nameserver $dns
EOF
        done
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

get_http_file_size_to() {
    var_name=$1
    url=$2

    size=''
    if wget --spider -S $url -o /tmp/headers.log; then
        # 网址重定向可能得到多个 Content-Length, 选最后一个
        set -o pipefail
        if size=$(grep 'Content-Length:' /tmp/headers.log |
            tail -1 | awk '{print $2}'); then
            eval "$var_name='$size'"
        fi
        set +o pipefail
    else
        error_and_exit "Can't access $url"
    fi
}

# shellcheck disable=SC2154
dd_gzip_xz() {
    case "$img_type" in
    gzip) prog=gzip ;;
    xz) prog=xz ;;
    *) error_and_exit 'Not supported' ;;
    esac

    # alpine busybox 自带 gzip xz，但官方版也许性能更好
    # 用官方 wget，一来带进度条，二来自带重试
    apk add wget $prog
    command wget $img -O- --tries=3 --progress=bar:force | $prog -dc >/dev/$xda
}

is_xda_gt_2t() {
    disk_size=$(blockdev --getsize64 /dev/$xda)
    disk_2t=$((2 * 1024 * 1024 * 1024 * 1024))
    [ "$disk_size" -gt "$disk_2t" ]
}

create_part() {
    # 目标系统非 alpine 和 dd
    # 脚本开始
    apk add util-linux udev hdparm e2fsprogs parted

    # 打开dev才能刷新分区名
    rc-service udev start

    # 反激活 lvm
    # alpine live 不需要
    false && vgchange -an

    # 移除 lsblk 显示的分区
    partx -d /dev/$xda || true

    # 清除分区签名
    # TODO: 先检测iso链接/各种链接
    # wipefs -a /dev/$xda

    # xda*1 星号用于 nvme0n1p1 的字母 p
    # shellcheck disable=SC2154
    if [ "$distro" = windows ]; then
        get_http_file_size_to size_bytes $iso
        if [ -n "$size_bytes" ]; then
            # 按iso容量计算分区大小，512m用于驱动和文件系统自身占用
            part_size="$((size_bytes / 1024 / 1024 + 512))MiB"
        else
            # 默认值，最大的iso 23h2 需要7g
            part_size="$((7 * 1024))MiB"
        fi

        apk add ntfs-3g-progs virt-what wimlib rsync
        # 虽然ntfs3不需要fuse，但wimmount需要，所以还是要保留
        modprobe fuse ntfs3
        if is_efi; then
            # efi
            apk add dosfstools
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' fat32 1MiB 1025MiB \
                mkpart '" "' fat32 1025MiB 1041MiB \
                mkpart '" "' ext4 1041MiB -${part_size} \
                mkpart '" "' ntfs -${part_size} 100% \
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
                mkpart primary ntfs 1MiB -${part_size} \
                mkpart primary ntfs -${part_size} 100% \
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
            # 最大的 qcow2 是 centos8，1.8g
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
    apk add yq

    yq -i "
        .network.version=1 |
        .network.config[0].type=\"physical\" |
        .network.config[0].name=\"eth0\" |
        .network.config[0].mac_address=\"$mac_addr\"  |
        .network.config[1].type=\"nameserver\"
        " $ci_file

    # ipv4
    if is_dhcpv4; then
        yq -i ".network.config[0].subnets += [{\"type\": \"dhcp\"}]" $ci_file

    elif is_staticv4; then
        get_netconf_to ipv4_addr
        get_netconf_to ipv4_gateway

        yq -i "
            .network.config[0].subnets += [{
                \"type\": \"static\",
                \"address\": \"$ipv4_addr\",
                \"gateway\": \"$ipv4_gateway\" }]
                " $ci_file

        if dns4_list=$(get_current_dns_v4); then
            for cur in $dns4_list; do
                yq -i ".network.config[1].address += [\"$cur\"]" $ci_file
            done
        fi
    fi

    # ipv6
    if is_slaac; then
        if is_enable_other_flag; then
            type=ipv6_dhcpv6-stateless
        else
            type=ipv6_slaac
        fi
        yq -i ".network.config[0].subnets += [{\"type\": \"$type\"}]" $ci_file

    elif is_dhcpv6; then
        yq -i ".network.config[0].subnets += [{\"type\": \"ipv6_dhcpv6-stateful\"}]" $ci_file

    elif is_staticv6; then
        get_netconf_to ipv6_addr
        get_netconf_to ipv6_gateway
        # centos7 不认识 static6，但可改成 static，作用相同
        # https://github.com/canonical/cloud-init/commit/dacdd30080bd8183d1f1c1dc9dbcbc8448301529
        yq -i "
            .network.config[0].subnets += [{
                \"type\": \"static\",
                \"address\": \"$ipv6_addr\",
                \"gateway\": \"$ipv6_gateway\" }]
            " $ci_file
    fi

    # 有 ipv6，且 rdnss 为空，手动添加 dns
    if is_need_manual_set_dnsv6 && dns6_list=$(get_current_dns_v6); then
        for cur in $dns6_list; do
            yq -i ".network.config[1].address += [\"$cur\"]" $ci_file
        done
    fi
}

download_cloud_init_config() {
    os_dir=$1

    ci_file=$os_dir/etc/cloud/cloud.cfg.d/99_nocloud.cfg
    download $confhome/cloud-init.yaml $ci_file
    # 删除注释行，除了第一行
    sed -i '1!{/^[[:space:]]*#/d}' $ci_file

    # swapfile
    # 如果分区表中已经有swapfile就跳过，例如arch
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

modify_windows() {
    # https://learn.microsoft.com/zh-cn/windows-hardware/manufacture/desktop/windows-setup-states
    # https://learn.microsoft.com/zh-cn/troubleshoot/azure/virtual-machines/reset-local-password-without-agent
    # https://learn.microsoft.com/zh-cn/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup

    # 判断用 SetupComplete 还是组策略
    state_ini=/os/Windows/Setup/State/State.ini
    cat $state_ini
    if grep -q IMAGE_STATE_COMPLETE $state_ini; then
        use_gpo=true
    else
        use_gpo=false
    fi

    # 下载共同的子脚本
    # 可能 unattend.xml 已经设置了ExtendOSPartition，不过运行resize没副作用
    bats="windows-resize.bat windows-set-netconf.bat"
    download $confhome/windows-resize.bat /os/windows-resize.bat
    create_win_set_netconf_script /os/windows-set-netconf.bat

    if $use_gpo; then
        # 使用组策略
        gpt_ini=/os/Windows/System32/GroupPolicy/gpt.ini
        scripts_ini=/os/Windows/System32/GroupPolicy/Machine/Scripts/scripts.ini
        mkdir -p "$(dirname $scripts_ini)"

        # 备份 ini
        for file in $gpt_ini $scripts_ini; do
            if [ -f $file ]; then
                cp $file $file.orig
            fi
        done

        # gpt.ini
        cat >$gpt_ini <<EOF
[General]
gPCFunctionalityVersion=2
gPCMachineExtensionNames=[{42B5FAAE-6536-11D2-AE5A-0000F87571E3}{40B6664F-4972-11D1-A7CA-0000F87571E3}]
Version=1
EOF
        unix2dos $gpt_ini

        # scripts.ini
        if ! [ -e $scripts_ini ]; then
            touch $scripts_ini
        fi

        if ! grep -F '[Startup]' $scripts_ini; then
            echo '[Startup]' >>$scripts_ini
        fi

        # 注意没用 pipefail 的话，错误码取自最后一个管道
        if num=$(grep -Eo '^[0-9]+' $scripts_ini | sort -n | tail -1 | grep .); then
            num=$((num + 1))
        else
            num=0
        fi

        bats="$bats windows-del-gpo.bat"
        for bat in $bats; do
            echo "${num}CmdLine=%SystemDrive%\\$bat" >>$scripts_ini
            echo "${num}Parameters=" >>$scripts_ini
            num=$((num + 1))
        done
        cat $scripts_ini
        unix2dos $scripts_ini

        # windows-del-gpo.bat
        download $confhome/windows-del-gpo.bat /os/windows-del-gpo.bat
    else
        # 使用 SetupComplete
        setup_complete=/os/Windows/Setup/Scripts/SetupComplete.cmd
        mkdir -p "$(dirname $setup_complete)"

        # 添加到 C:\Setup\Scripts\SetupComplete.cmd 最前面
        # call 防止子 bat 删除自身后中断主脚本
        my_setup_complete=$(mktemp)
        for bat in $bats; do
            echo "if exist %SystemDrive%\\$bat (call %SystemDrive%\\$bat)" >>$my_setup_complete
        done

        if [ -f $setup_complete ]; then
            # 直接插入而不是覆盖，可以保留权限，虽然没什么影响
            insert_into_file $setup_complete HEAD <$my_setup_complete
        else
            cp $my_setup_complete $setup_complete
        fi

        unix2dos $setup_complete
    fi
}

modify_linux() {
    os_dir=$1

    find_and_mount() {
        mount_point=$1
        mount_dev=$(awk "\$2==\"$mount_point\" {print \$1}" $os_dir/etc/fstab)
        if [ -n "$mount_dev" ]; then
            mount $mount_dev $os_dir$mount_point
        fi
    }

    download_cloud_init_config $os_dir

    # 为红帽系禁用 selinux kdump
    if [ -f $os_dir/etc/redhat-release ]; then
        find_and_mount /boot
        find_and_mount /boot/efi
        disable_selinux_kdump $os_dir
    fi

    # debian 10/11 默认不支持 rdnss，要安装 rdnssd 或者 nm
    if [ -f $os_dir/etc/debian_version ] && grep -E '^(10|11)' $os_dir/etc/debian_version; then
        mv $os_dir/etc/resolv.conf $os_dir/etc/resolv.conf.orig
        cp -f /etc/resolv.conf $os_dir/etc/resolv.conf
        mount_pseudo_fs $os_dir
        chroot $os_dir apt update
        chroot $os_dir apt install -y rdnssd
        # 不会自动建立链接，因此不能删除
        mv $os_dir/etc/resolv.conf.orig $os_dir/etc/resolv.conf
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
        if [ ! -d $os_dir/var/db/repos/gentoo/ ]; then
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

modify_os_on_disk() {
    only_process=$1

    apk add util-linux udev hdparm lsblk
    rc-service udev start
    update_part /dev/$xda

    # dd linux 的时候不用修改硬盘内容
    if [ "$distro" = "dd" ] && ! lsblk -f /dev/$xda | grep ntfs; then
        return
    fi

    mkdir -p /os
    # 按分区容量大到小，依次寻找系统分区
    for part in $(lsblk /dev/$xda --sort SIZE -no NAME | sed '$d' | tac); do
        # btrfs挂载的是默认子卷，如果没有默认子卷，挂载的是根目录
        # fedora 云镜像没有默认子卷，且系统在root子卷中
        if mount -o ro /dev/$part /os; then
            if [ "$only_process" = linux ]; then
                if etc_dir=$({ ls -d /os/etc/ || ls -d /os/*/etc/; } 2>/dev/null); then
                    os_dir=$(dirname $etc_dir)
                    # 重新挂载为读写
                    mount -o remount,rw /os
                    modify_linux $os_dir
                    return
                fi
            elif [ "$only_process" = windows ]; then
                # find 有时会报 I/O error
                if ls -d /os/*/ | grep -i '/windows/' 2>/dev/null; then
                    # 重新挂载为读写、忽略大小写
                    umount /os
                    apk add ntfs-3g
                    mount.lowntfs-3g /dev/$part /os -o ignore_case
                    modify_windows /os
                    return
                fi
            fi
            umount /os
        fi
    done
    error_and_exit "Can't find os partition."
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

download_qcow() {
    apk add qemu-img lsblk

    mkdir -p /installer
    mount /dev/disk/by-label/installer /installer
    qcow_file=/installer/cloud_image.qcow2
    download $img $qcow_file
}

install_qcow_el() {
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
    cp /etc/resolv.conf /os/etc/resolv.conf

    # selinux kdump
    disable_selinux_kdump /os

    # cloud-init
    download_cloud_init_config /os

    # 为 centos 7 ci 安装 NetworkManager
    # 1. 能够自动配置 onlink 网关
    # 2. 解决 cloud-init 关闭了 ra，因为 nm 无视内核 ra 设置
    if grep 'centos:7' /os/etc/system-release-cpe; then
        yum install -y NetworkManager
        chroot /os/ systemctl enable NetworkManager
    fi

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

    # 不删除可能网络管理器不会写入dns
    rm -f /os/etc/resolv.conf

    # 删除installer分区，重启后cloud init会自动扩容
    swapoff -a
    umount /installer
    parted /dev/$xda -s rm 3
}

dd_qcow() {
    if true; then
        modprobe nbd nbds_max=1
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
            echo "Start DD Cloud Image..."
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

}

resize_after_install_cloud_image() {
    # 提前扩容
    # 1 修复 vultr 512m debian 10/11 generic/genericcloud 首次启动 kernel panic
    # 2 修复 gentoo websync 时空间不足
    if [ "$distro" = debian ] || [ "$distro" = gentoo ]; then
        apk add parted
        if parted /dev/$xda -s print 2>&1 | grep 'Not all of the space'; then
            printf "fix" | parted /dev/$xda print ---pretend-input-tty

            system_part_num=$(parted /dev/$xda -m print | tail -1 | cut -d: -f1)
            printf "yes" | parted /dev/$xda resizepart $system_part_num 100% ---pretend-input-tty
            update_part /dev/$xda

            if [ "$distro" = gentoo ]; then
                apk add e2fsprogs-extra
                e2fsck -p -f /dev/$xda$system_part_num
                resize2fs /dev/$xda$system_part_num
            fi
        fi
    fi
}

mount_part_for_install_mode() {
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

get_dns_list_for_win() {
    if dns_list=$(get_current_dns_v$1); then
        i=0
        for dns in $dns_list; do
            i=$((i + 1))
            echo "set ipv${1}_dns$i=$dns"
        done
    fi
}

create_win_set_netconf_script() {
    target=$1

    if is_staticv4 || is_staticv6 || is_need_manual_set_dnsv6; then
        get_netconf_to mac_addr
        echo "set mac_addr=$mac_addr" >$target

        # 生成静态 ipv4 配置
        if is_staticv4; then
            get_netconf_to ipv4_addr
            get_netconf_to ipv4_gateway
            ipv4_dns_list="$(get_dns_list_for_win 4)"
            cat <<EOF >>$target
set ipv4_addr=$ipv4_addr
set ipv4_gateway=$ipv4_gateway
$ipv4_dns_list
EOF
        fi

        # 生成静态 ipv6 配置
        if is_staticv6; then
            get_netconf_to ipv6_addr
            get_netconf_to ipv6_gateway
            cat <<EOF >>$target
set ipv6_addr=$ipv6_addr
set ipv6_gateway=$ipv6_gateway
EOF
        fi

        # 有 ipv6 但需设置 dns
        if is_need_manual_set_dnsv6 && ipv6_dns_list="$(get_dns_list_for_win 6)"; then
            cat <<EOF >>$target
$ipv6_dns_list
EOF
        fi

        cat -n $target
    fi

    # 脚本还有关闭ipv6隐私id的功能，所以不能省略
    # 合并脚本
    wget $confhome/windows-set-netconf.bat -O- >>$target
    unix2dos $target
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

    is_win11() {
        echo $image_name | grep -iEw '^Windows 11'
    }

    # 跳过 win11 硬件限制
    if is_win11; then
        wiminfo "$install_wim" "$image_name" --image-property WINDOWS/INSTALLATIONTYPE=Server
    fi

    # 变量名     使用场景
    # arch_uname uname -m                      x86_64  aarch64
    # arch_wim   wiminfo                  x86  x86_64  ARM64
    # arch       virtio驱动/unattend.xml  x86  amd64   arm64
    # arch_xen   xen驱动                  x86  x64

    # 将 wim 的 arch 转为驱动和应答文件的 arch
    arch_wim=$(wiminfo $install_wim 1 | grep Architecture: | awk '{print $2}' | to_lower)
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
        if is_win7_or_win2008r2; then
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/NVMe/1.3.2/AWSNVMe.zip $drv/AWSNVMe.zip
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/ENA/x64/2.2.3/AwsEnaNetworkDriver.zip $drv/AwsEnaNetworkDriver.zip
        else
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/NVMe/Latest/AWSNVMe.zip $drv/AWSNVMe.zip
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/ENA/Latest/AwsEnaNetworkDriver.zip $drv/AwsEnaNetworkDriver.zip
        fi
        unzip -o -d $drv/aws/ $drv/AWSNVMe.zip
        unzip -o -d $drv/aws/ $drv/AwsEnaNetworkDriver.zip

    elif virt-what | grep xen &&
        [ "$arch_wim" = x86_64 ]; then
        # aws xen
        # 只有 64 位驱动
        # 未测试
        # https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/Upgrading_PV_drivers.html
        apk add msitools

        if is_win7_or_win2008r2; then
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/AWSPV/8.3.5/AWSPVDriver.zip $drv/AWSPVDriver.zip
        else
            download https://s3.amazonaws.com/ec2-windows-drivers-downloads/AWSPV/Latest/AWSPVDriver.zip $drv/AWSPVDriver.zip
        fi

        unzip -o -d $drv $drv/AWSPVDriver.zip
        msiextract $drv/AWSPVDriverSetup.msi -C $drv
        mkdir -p $drv/aws/
        cp -rf $drv/.Drivers/* $drv/aws/

    elif false && virt-what | grep xen &&
        [ "$arch_wim" != arm64 ]; then
        # xen
        # 有 x86 x64，没arm64驱动
        # 没签名，暂时用aws的驱动代替
        # https://lore.kernel.org/xen-devel/E1qKMmq-00035B-SS@xenbits.xenproject.org/
        # https://xenbits.xenproject.org/pvdrivers/win/
        # 在 aws t2 上测试，安装 xenbus 会蓝屏，装了其他7个驱动后，能进系统但没网络
        # 但 aws 应该用aws官方xen驱动，所以测试仅供参考
        parts='xenbus xencons xenhid xeniface xennet xenvbd xenvif xenvkbd'
        mkdir -p $drv/xen/
        for part in $parts; do
            download https://xenbits.xenproject.org/pvdrivers/win/$part.tar $drv/$part.tar
            tar -xf $drv/$part.tar -C $drv/xen/
        done

    elif virt-what | grep kvm; then
        # virtio
        # x86 x64 arm64 都有
        # https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/
        case $(echo "$image_name" | to_lower) in
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

        apk add dmidecode
        dmi=$(dmidecode)

        if echo "$dmi" | grep -Eiw "Google Compute Engine|GoogleCloud"; then
            gce_repo=https://packages.cloud.google.com/yuck
            download $gce_repo/repos/google-compute-engine-stable/index /tmp/gce.json
            # gga 好像只是用于调节后台vnc分辨率
            for name in gvnic gga; do
                mkdir -p $drv/gce/$name
                link=$(grep -o "/pool/.*-google-compute-engine-driver-$name\.goo" /tmp/gce.json)
                wget $gce_repo$link -O- | tar -xzf- -C $drv/gce/$name
            done

            # 没有 vista 驱动
            # 没有专用的 win11 驱动
            case $(echo "$image_name" | to_lower) in
            'windows server 2022'*) sys_gce=win10.0 ;;
            'windows server 2019'*) sys_gce=win10.0 ;;
            'windows server 2016'*) sys_gce=win10.0 ;;
            'windows server 2012 R2'*) sys_gce=win6.3 ;;
            'windows server 2012'*) sys_gce=win6.2 ;;
            'windows server 2008 R2'*) sys_gce=win6.1 ;;
            'windows 11'*) sys_gce=win10.0 ;;
            'windows 10'*) sys_gce=win10.0 ;;
            'windows 8.1'*) sys_gce=win6.3 ;;
            'windows 8'*) sys_gce=win6.2 ;;
            'windows 7'*) sys_gce=win6.1 ;;
            esac
        fi
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
        path=$2

        [ -n "$path" ] && filter="-ipath $path" || filter=""
        find $src \
            $filter \
            -type f \
            -not -iname "*.pdb" \
            -not -iname "dpinst.exe" \
            -exec cp -rfv {} /wim/drivers \;
    }

    # 添加驱动
    mkdir -p /wim/drivers

    [ -d $drv/virtio ] && cp_drivers $drv/virtio "*/$sys/$arch/*"
    [ -d $drv/aws ] && cp_drivers $drv/aws
    [ -d $drv/xen ] && cp_drivers $drv/xen "*/$arch_xen/*"
    [ -d $drv/gce ] && {
        [ "$arch_wim" = x86 ] && gvnic_suffix=-32 || gvnic_suffix=
        cp_drivers $drv/gce/gvnic "*/$sys_gce$gvnic_suffix/*"
        # gga 驱动不分32/64位
        cp_drivers $drv/gce/gga "*/$sys_gce/*"
    }

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
        download $confhome/windows-resize.bat /wim/windows-resize.bat
        create_win_set_netconf_script /wim/windows-set-netconf.bat
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
# do 机器第二次运行会报错
hwclock -s || true

# 设置密码，安装并打开 ssh
echo root:123@@@ | chpasswd
printf '\nyes' | setup-sshd

extract_env_from_cmdline
# shellcheck disable=SC2154
if [ "$sleep" = 1 ]; then
    exit
fi

mod_motd
setup_tty_and_log
clear_previous
add_community_repo

# 找到主硬盘
xda=$(get_xda)

if [ "$distro" != "alpine" ]; then
    setup_nginx_if_enough_ram
fi

# dd qemu 切换成云镜像模式，暂时没用到
if [ "$distro" = "dd" ] && [ "$img_type" = "qemu" ]; then
    cloud_image=1
fi

if [ "$distro" = "alpine" ]; then
    install_alpine
elif [ "$distro" = "dd" ] && [ "$img_type" != "qemu" ]; then
    dd_gzip_xz
    modify_os_on_disk windows
elif is_use_cloud_image; then
    if [ "$img_type" = "qemu" ]; then
        create_part
        download_qcow
        # 这几个系统云镜像系统盘是8~9g xfs，而我们的目标是能在5g硬盘上运行，因此改成复制系统文件
        if [ "$distro" = centos ] || [ "$distro" = alma ] || [ "$distro" = rocky ]; then
            install_qcow_el
        else
            # debian ubuntu fedora opensuse arch gentoo
            dd_qcow
            resize_after_install_cloud_image
            modify_os_on_disk linux
        fi
    else
        # gzip xz 格式的云镜像，暂时没用到
        dd_gzip_xz
        resize_after_install_cloud_image
        modify_os_on_disk linux
    fi
else
    # 安装模式: windows windows ubuntu 红帽
    create_part
    mount_part_for_install_mode
    if [ "$distro" = "windows" ]; then
        install_windows
    else
        install_redhat_ubuntu
    fi
fi
if [ "$sleep" = 2 ]; then
    exit
fi

# 等几秒让 web ssh 输出全部内容
sleep 5
reboot

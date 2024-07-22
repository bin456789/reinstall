#!/bin/ash
# shellcheck shell=dash
# shellcheck disable=SC2086,SC3047,SC3036,SC3010,SC3001
# alpine 默认使用 busybox ash

# 命令出错终止运行，将进入到登录界面，防止失联
set -eE

# debian 安装版、ubuntu 安装版、redhat 安装版不使用该密码
PASSWORD=123@@@
EFI_UUID=C12A7328-F81F-11D2-BA4B-00A0C93EC93B

TRUE=0
FALSE=1

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
    echo -e "${color}Error: $*${plain}" >&2
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
        alpine_mirror=$(grep '^http.*/main$' /etc/apk/repositories | sed 's,/[^/]*/main$,,' | head -1)
        echo $alpine_mirror/$alpine_ver/community >>/etc/apk/repositories
    fi
}

# 有时网络问题下载失败，导致脚本中断
# 因此需要重试
apk() {
    for i in $(seq 5); do
        command apk "$@" && return
        sleep 1
    done
}

# busybox 的 wget 没有重试功能
wget() {
    echo "$@" | grep -o 'http[^ ]*' >&2
    for i in $(seq 5); do
        if command wget "$@"; then
            return
        else
            ret=$?
            # 错误，或者达到重试次数
            if [ $i -eq 5 ]; then
                return $ret
            fi
            sleep 1
        fi
    done
}

is_have_cmd() {
    command -v "$1" >/dev/null
}

is_have_cmd_on_disk() {
    os_dir=$1
    cmd=$2

    for bin_dir in /bin /sbin /usr/bin /usr/sbin; do
        if [ -f "$os_dir$bin_dir/$cmd" ]; then
            return
        fi
    done
    return 1
}

download() {
    url=$1
    path=$2

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
        if [[ "$path" = '/*' ]]; then
            save="-d / -o $path"
        else
            # 文件名是相对路径
            save="-o $path"
        fi
    fi

    if ! is_have_cmd aria2c; then
        apk add aria2
    fi

    # stdbuf 在 coreutils 包里面
    if ! is_have_cmd stdbuf; then
        apk add coreutils
    fi

    # 阿里云源限速，而且检测 user-agent 禁止 axel/aria2 下载
    # aria2 默认 --max-tries 5

    # 默认 --max-tries=5，但以下情况服务器出错，aria2不会重试，而是直接返回错误
    # 因此添加 for 循环
    #     [ERROR] CUID#7 - Download aborted. URI=https://aka.ms/manawindowsdrivers
    # Exception: [AbstractCommand.cc:351] errorCode=1 URI=https://aka.ms/manawindowsdrivers
    #   -> [SocketCore.cc:1019] errorCode=1 SSL/TLS handshake failure:  `not signed by known authorities or invalid'

    # 用 if 的话，报错不会中断脚本
    # if aria2c xxx; then
    #     return
    # fi

    # --user-agent=Wget/1.21.1 \

    echo "$url"
    for i in $(seq 5); do
        stdbuf -oL -eL \
            aria2c -x4 \
            --allow-overwrite=true \
            --summary-interval=0 \
            --max-tries 1 \
            $save $url && return
        sleep 1
    done
}

update_part() {
    sleep 1

    # 玄学
    for i in $(seq 3); do
        sync
        partprobe /dev/$xda 2>/dev/null

        # partx
        # https://access.redhat.com/solutions/199573
        if is_have_cmd partx; then
            partx -u $1
        fi

        if rc-service --exists udev && rc-service -q udev status; then
            # udev
            udevadm trigger
            udevadm settle
        else
            # busybox mdev
            # -f 好像没用
            mdev -sf 2>/dev/null
        fi
    done
}

is_efi() {
    if [ -n "$force" ]; then
        [ "$force" = efi ]
    else
        [ -d /sys/firmware/efi/ ]
    fi
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

get_approximate_ram_size() {
    # lsmem 需要 util-linux
    if false && is_have_cmd lsmem; then
        ram_size=$(lsmem -b 2>/dev/null | grep 'Total online memory:' | awk '{ print $NF/1024/1024 }')
    fi

    if [ -z $ram_size ]; then
        ram_size=$(free -m | awk '{print $2}' | sed -n '2p')
    fi

    echo "$ram_size"
}

setup_nginx_if_enough_ram() {
    total_ram=$(get_approximate_ram_size)
    # 512内存才安装
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

setup_udev_util_linux() {
    # mdev 不会删除 /sys/block/by-label 的旧分区名，所以用 udev
    # util-linux 包含 lsblk
    # util-linux 可自动探测 mount 格式
    apk add udev util-linux
    rc-service udev start
}

get_ttys() {
    prefix=$1
    # shellcheck disable=SC2154
    wget $confhome/ttys.sh -O- | sh -s $prefix
}

find_xda() {
    # 防止 $main_disk 为空
    if [ -z "$main_disk" ]; then
        error_and_exit "cmdline main_disk is empty."
    fi

    # busybox fdisk/lsblk/blkid 不显示 mbr 分区表 id
    # 可用以下工具：
    # fdisk 在 util-linux-misc 里面，占用大
    # sfdisk 占用小
    # lsblk
    # blkid

    tool=sfdisk

    is_have_cmd $tool && need_install_tool=false || need_install_tool=true
    if $need_install_tool; then
        apk add $tool
    fi

    if [ "$tool" = sfdisk ]; then
        # sfdisk
        for disk in $(get_all_disks); do
            if sfdisk --disk-id "/dev/$disk" | sed 's/0x//' | grep -ix "$main_disk"; then
                xda=$disk
                break
            fi
        done
    else
        # lsblk
        xda=$(lsblk --nodeps -rno NAME,PTUUID | grep -iw "$main_disk" | awk '{print $1}')
    fi

    if [ -z "$xda" ]; then
        error_and_exit "Could not find xda: $main_disk"
    fi

    if $need_install_tool; then
        apk del $tool
    fi
}

get_all_disks() {
    # shellcheck disable=SC2010
    ls /sys/block/ | grep -Ev '^(loop|sr|nbd)'
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
        done < <(xargs -n1 </proc/cmdline | grep "^${prefix}_" | sed "s/^${prefix}_//")
    done
}

mod_motd() {
    # 安装后 alpine 后要恢复默认
    # 自动安装失败后，可能手动安装 alpine，因此无需判断 $distro
    file=/etc/motd
    if ! [ -e $file.orig ]; then
        cp $file $file.orig
        # shellcheck disable=SC2016
        echo "mv "\$mnt$file.orig" "\$mnt$file"" |
            insert_into_file /sbin/setup-disk before 'cleanup_chroot_mounts "\$mnt"'

        cat <<EOF >$file
Reinstalling...
To view logs run:
tail -fn+1 /reinstall.log
EOF
    fi
}

umount_all() {
    dirs="/mnt /os /iso /wim /installer /nbd /nbd-boot /nbd-efi /root"
    regex=$(echo "$dirs" | sed 's, ,|,g')
    if mounts=$(mount | grep -Ew "$regex" | awk '{print $3}' | tac); then
        for mount in $mounts; do
            echo "umount $mount"
            umount $mount
        done
    fi
}

# 可能脚本不是首次运行，先清理之前的残留
clear_previous() {
    if is_have_cmd vgchange; then
        umount -R /os /nbd || true
        vgchange -an
        apk add device-mapper
        dmsetup remove_all
    fi
    disconnect_qcow
    swapoff -a
    umount_all

    # 以下情况 umount -R /1 会提示 busy
    # mount /file1 /1
    # mount /1/file2 /2
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
        # shellcheck disable=SC2154
        _ra="$(rdisc6 -1 "$ethx")"
        apk del ndisc6

        # 显示网络配置
        echo
        echo "$_ra" | cat -n
        echo
        ip addr | cat -n
        echo
    fi
    eval "$1='$_ra'"
}

get_netconf_to() {
    case "$1" in
    slaac | dhcpv6 | rdnss | other) get_ra_to ra ;;
    esac

    # shellcheck disable=SC2154
    # debian initrd 没有 xargs
    case "$1" in
    slaac) echo "$ra" | grep 'Autonomous address conf' | grep -q Yes && res=1 || res=0 ;;
    dhcpv6) echo "$ra" | grep 'Stateful address conf' | grep -q Yes && res=1 || res=0 ;;
    rdnss) res=$(echo "$ra" | grep 'Recursive DNS server' | cut -d: -f2-) ;;
    other) echo "$ra" | grep 'Stateful other conf' | grep -q Yes && res=1 || res=0 ;;
    *) res=$(cat /dev/netconf/$ethx/$1) ;;
    esac

    eval "$1='$res'"
}

is_ipv4_has_internet() {
    get_netconf_to ipv4_has_internet
    # shellcheck disable=SC2154
    [ "$ipv4_has_internet" = 1 ]
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

should_disable_ra_slaac() {
    get_netconf_to should_disable_ra_slaac
    # shellcheck disable=SC2154
    [ "$should_disable_ra_slaac" = 1 ]
}

is_slaac() {
    # 防止部分机器slaac/dhcpv6获取的ip/网关无法上网
    if should_disable_ra_slaac; then
        return 1
    fi
    get_netconf_to slaac
    # shellcheck disable=SC2154
    [ "$slaac" = 1 ]
}

is_dhcpv6() {
    # 防止部分机器slaac/dhcpv6获取的ip/网关无法上网
    if should_disable_ra_slaac; then
        return 1
    fi
    get_netconf_to dhcpv6

    # shellcheck disable=SC2154
    # 甲骨文即使没有添加 IPv6 地址，RA DHCPv6 标志也是开的
    # 部分系统开机需要等 DHCPv6 超时
    # 这种情况需要禁用 DHCPv6
    if [ "$dhcpv6" = 1 ] && ! ip -6 -o addr show scope global dev "$ethx" | grep -q .; then
        echo 'DHCPv6 flag is on, but DHCPv6 is not working.'
        return 1
    fi

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
    # rdnss 可能有几个
    get_netconf_to rdnss
    [ -n "$rdnss" ]
}

is_windows() {
    for dir in /os /wim; do
        [ -d $dir/Windows/System32 ] && return 0
    done
    return 1
}

# 15063 或之后才支持 rdnss
is_windows_support_rdnss() {
    apk add pev
    for dir in /os /wim; do
        dll=$dir/Windows/System32/kernel32.dll
        if [ -f $dll ]; then
            build_ver="$(peres -v $dll | grep 'Product Version:' | cut -d. -f3)"
            echo "Windows Build Version: $build_ver"
            apk del pev
            [ "$build_ver" -ge 15063 ] && return 0 || return 1
        fi
    done
    error_and_exit "Not found kernel32.dll"
}

is_need_manual_set_dnsv6() {
    # 有没有可能是静态但是有 rdnss？
    ! is_have_ipv6 && return $FALSE
    is_dhcpv6 && return $FALSE
    is_staticv6 && return $TRUE
    is_slaac && ! is_enable_other_flag &&
        { ! is_have_rdnss || { is_have_rdnss && is_windows && ! is_windows_support_rdnss; }; }
}

get_current_dns_v4() {
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    if false; then
        grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | grep '\.'
    else
        grep '^nameserver' /etc/resolv.conf | cut -d' ' -f2 | grep '\.'
    fi
}

get_current_dns_v6() {
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    if false; then
        grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | grep ':'
    else
        grep '^nameserver' /etc/resolv.conf | cut -d' ' -f2 | grep ':'
    fi
}

to_upper() {
    tr '[:lower:]' '[:upper:]'
}

to_lower() {
    tr '[:upper:]' '[:lower:]'
}

del_empty_lines() {
    # grep .
    sed '/^[[:space:]]*$/d'
}

get_part_num_by_part() {
    dev_part=$1
    echo "$dev_part" | grep -o '[0-9]*' | tail -1
}

get_fallback_efi_file_name() {
    case $(arch) in
    x86_64) echo bootx64.efi ;;
    aarch64) echo bootaa64.efi ;;
    *) error_and_exit ;;
    esac
}

del_invalid_efi_entry() {
    apk add lsblk efibootmgr

    efibootmgr --quiet --remove-dups

    while read -r line; do
        part_uuid=$(echo "$line" | awk -F ',' '{print $3}')
        efi_index=$(echo "$line" | grep_efi_index)
        if ! lsblk -o PARTUUID | grep -q "$part_uuid"; then
            echo "Delete invalid EFI Entry: $line"
            efibootmgr --quiet --bootnum "$efi_index" --delete-bootnum
        fi
    done < <(efibootmgr | grep 'HD(.*,GPT,')
}

grep_efi_index() {
    awk -F '*' '{print $1}' | sed 's/Boot//'
}

# 某些机器可能不会回落到 bootx64.efi
# 因此手动添加一个回落项
add_fallback_efi_to_nvram() {
    apk add lsblk efibootmgr

    if efi_row=$(lsblk /dev/$xda -ro NAME,PARTTYPE,PARTUUID | grep -i "$EFI_UUID"); then
        efi_part_uuid=$(echo "$efi_row" | awk '{print $3}')
        efi_part_name=$(echo "$efi_row" | awk '{print $1}')
        efi_part_num=$(get_part_num_by_part "$efi_part_name")
        efi_file=$(get_fallback_efi_file_name)

        # 创建条目，先判断是否已经存在
        if ! efibootmgr | grep -i "HD($efi_part_num,GPT,$efi_part_uuid,.*)/File(\\\EFI\\\boot\\\\$efi_file)"; then
            fallback_id=$(efibootmgr --create-only \
                --disk "/dev/$xda" \
                --part "$efi_part_num" \
                --label "fallback" \
                --loader "\\EFI\\boot\\$efi_file" |
                tail -1 | grep_efi_index)

            # 添加到最后
            orig_order=$(efibootmgr | grep -F BootOrder: | awk '{print $2}')
            if [ -n "$orig_order" ]; then
                new_order="$orig_order,$fallback_id"
            else
                new_order="$fallback_id"
            fi
            efibootmgr --bootorder "$new_order"
        fi
    else
        # shellcheck disable=SC2154
        if [ "$confirmed_no_efi" = 1 ]; then
            echo 'Confirmed no EFI in previous step.'
        else
            # reinstall.sh 里确认过一遍，但是逻辑扇区大于 512 时，可能漏报？
            # 这里的应该会根据逻辑扇区来判断？
            echo "
Warning: This machine is currently using EFI boot, but the main hard drive does not have an EFI partition.
If this machine supports Legacy BIOS boot (CSM), you can safely restart into the new system by running the reboot command.
If this machine does not support Legacy BIOS boot (CSM), you will not be able to enter the new system after rebooting.

警告：本机目前使用 EFI 引导，但主硬盘没有 EFI 分区。
如果本机支持 Legacy BIOS 引导 (CSM)，你可以运行 reboot 命令安全地重启到新系统。
如果本机不支持 Legacy BIOS 引导 (CSM)，重启后将无法进入新系统。
"
            exit
        fi
    fi
}

unix2dos() {
    target=$1

    # 先原地unix2dos，出错再用cat，可最大限度保留文件权限
    if ! command unix2dos $target 2>/tmp/unix2dos.log; then
        # 出错后删除 unix2dos 创建的临时文件
        rm "$(awk -F: '{print $2}' /tmp/unix2dos.log | xargs)"
        tmp=$(mktemp)
        cp $target $tmp
        command unix2dos $tmp
        # cat 可以保留权限
        cat $tmp >$target
        rm $tmp
    fi
}

insert_into_file() {
    file=$1
    location=$2
    regex_to_find=$3

    if [ "$location" = head ]; then
        bak=$(mktemp)
        cp $file $bak
        cat - $bak >$file
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

get_eths() {
    (
        cd /dev/netconf
        ls
    )
}

is_distro_like_debian() {
    [ "$distro" = debian ] || [ "$distro" = kali ]
}

create_ifupdown_config() {
    conf_file=$1

    rm -f $conf_file

    if is_distro_like_debian; then
        cat <<EOF >>$conf_file
source /etc/network/interfaces.d/*

EOF
    fi

    # 生成 lo配置
    cat <<EOF >>$conf_file
auto lo
iface lo inet loopback
EOF

    # ethx
    for ethx in $(get_eths); do
        mode=auto
        enpx=
        if is_distro_like_debian; then
            if [ -f /etc/network/devhotplug ] && grep -wo "$ethx" /etc/network/devhotplug; then
                mode=allow-hotplug
            fi

            if is_have_cmd udevadm; then
                enpx=$(udevadm test-builtin net_id /sys/class/net/$ethx 2>&1 | grep ID_NET_NAME_PATH= | cut -d= -f2)
            fi
        fi

        # dmit debian 普通内核和云内核网卡名不一致，因此需要 rename
        # 安装系统时 ens18
        # 普通内核   ens18
        # 云内核     enp6s18
        # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=928923

        # 头部
        {
            echo
            if [ -n "$enpx" ] && [ "$enpx" != "$ethx" ]; then
                echo rename $enpx=$ethx >>$conf_file
            fi
            echo $mode $ethx
        } >>$conf_file

        # ipv4
        if is_dhcpv4; then
            echo "iface $ethx inet dhcp" >>$conf_file

        elif is_staticv4; then
            get_netconf_to ipv4_addr
            get_netconf_to ipv4_gateway
            cat <<EOF >>$conf_file
iface $ethx inet static
    address $ipv4_addr
    gateway $ipv4_gateway
EOF
            # dns
            if list=$(get_current_dns_v4); then
                for dns in $list; do
                    cat <<EOF >>$conf_file
    dns-nameservers $dns
EOF
                done
            fi
        fi

        # ipv6
        if is_slaac; then
            echo "iface $ethx inet6 auto" >>$conf_file

        elif is_dhcpv6; then
            echo "iface $ethx inet6 dhcp" >>$conf_file

        elif is_staticv6; then
            get_netconf_to ipv6_addr
            get_netconf_to ipv6_gateway
            cat <<EOF >>$conf_file
iface $ethx inet6 static
    address $ipv6_addr
    gateway $ipv6_gateway
EOF
        fi

        # dns
        # 有 ipv6 但需设置 dns 的情况
        if is_need_manual_set_dnsv6 && list=$(get_current_dns_v6); then
            for dns in $list; do
                cat <<EOF >>$conf_file
    dns-nameserver $dns
EOF
            done
        fi

        # 禁用 ra
        if should_disable_ra_slaac; then
            if [ "$distro" = alpine ]; then
                cat <<EOF >>$conf_file
    pre-up echo 0 >/proc/sys/net/ipv6/conf/$ethx/accept_ra
EOF
            else
                cat <<EOF >>$conf_file
    accept_ra 0
EOF
            fi
        fi
    done
}

install_alpine() {
    hack_lowram_modloop=true
    hack_lowram_swap=true

    if $hack_lowram_modloop; then
        # 预先加载需要的模块
        if rc-service modloop status; then
            modules="ext4 vfat nls_utf8 nls_cp437"
            for mod in $modules; do
                modprobe $mod
            done
            # crc32c 等于 crc32c-intel
            # 没有 sse4.2 的机器加载 crc32c 时会报错 modprobe: ERROR: could not insert 'crc32c_intel': No such device
            modprobe crc32c || modprobe crc32c-generic
        fi

        # 删除 modloop ，释放内存
        rc-service modloop stop
        rm -f /lib/modloop-lts /lib/modloop-virt
    fi

    # bios机器用 setup-disk 自动分区会有 boot 分区
    # 因此手动分区安装
    create_part

    # 挂载系统分区
    if is_efi || is_xda_gt_2t; then
        os_part_num=2
    else
        os_part_num=1
    fi
    mkdir -p /os
    mount -t ext4 /dev/${xda}*${os_part_num} /os

    # 挂载 efi
    if is_efi; then
        mkdir -p /os/boot/efi
        mount -t vfat /dev/${xda}*1 /os/boot/efi
    fi

    # 创建 swap
    if $hack_lowram_swap; then
        create_swap 256 /os/swapfile
    fi

    # 网络配置
    create_ifupdown_config /etc/network/interfaces
    echo
    cat -n /etc/network/interfaces
    echo

    # 在 arm netboot initramfs init 中
    # 如果识别到rtc硬件，就往系统添加hwclock服务，否则添加swclock
    # 这个设置也被复制到安装的系统中
    # 但是从initramfs chroot到真正的系统后，是能识别rtc硬件的
    # 所以我们手动改用hwclock修复这个问题
    rc-update del swclock boot || true
    rc-update add hwclock boot

    # 通过 setup-alpine 安装会启用以下几个服务
    # https://github.com/alpinelinux/alpine-conf/blob/c5131e9a038b09881d3d44fb35e86851e406c756/setup-alpine.in#L189

    # boot
    rc-update add networking boot
    rc-update add seedrng boot

    # default
    rc-update add crond
    if [ -e /dev/input/event0 ]; then
        rc-update add acpid
    fi

    # 如果是 vm 就用 virt 内核
    if is_virt; then
        kernel_flavor="virt"
    else
        kernel_flavor="lts"
    fi

    # 重置为官方仓库配置
    # 国内机可能无法访问mirror列表而报错
    if false; then
        true >/etc/apk/repositories
        setup-apkrepos -1
    fi

    # setup-disk 安装 grub 跳过了添加引导项到 nvram
    # 防止部分机器不会 fallback 到 bootx64.efi
    if is_efi; then
        apk add efibootmgr
        sed -i 's/--no-nvram//' /sbin/setup-disk
    fi

    # 安装到硬盘
    # alpine默认使用 syslinux (efi 环境除外)，这里强制使用 grub，方便用脚本再次重装
    KERNELOPTS="$(get_ttys console=)"
    export KERNELOPTS
    export BOOTLOADER="grub"
    setup-disk -m sys -k $kernel_flavor /os

    # 安装到硬盘后才安装各种应用
    # 避免占用 Live OS 内存

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
    chroot /os apk add dhcpcd
    chroot /os sed -i '/^slaac private/s/^/#/' /etc/dhcpcd.conf
    chroot /os sed -i '/^#slaac hwaddr/s/^#//' /etc/dhcpcd.conf

    # 安装其他部件
    chroot /os setup-keymap us us
    chroot /os setup-timezone -i Asia/Shanghai
    chroot /os setup-ntp chrony || true

    # 3.19 或以上，非 efi 需要手动安装 grub
    if ! is_efi; then
        grub-install --boot-directory=/os/boot --target=i386-pc /dev/$xda
    fi

    # efi grub 添加 fwsetup 条目
    if is_efi; then
        mount_pseudo_fs /os
        chroot /os update-grub
    fi

    # 删除 chroot 历史记录
    rm -rf /os/root/.ash_history

    # 关闭 swap 前删除应用，避免占用内存
    apk del e2fsprogs dosfstools grub*

    # 是否保留 swap
    if [ -e /os/swapfile ]; then
        if false; then
            echo "/swapfile swap swap defaults 0 0" >>/os/etc/fstab
            ln -sf /etc/init.d/swap /os/etc/runlevels/boot/swap
        else
            swapoff -a
            rm /os/swapfile
        fi
    fi
}

get_cpu_vendor() {
    cpu_vendor=$(grep 'vendor_id' /proc/cpuinfo | head -n 1 | cut -d: -f2 | xargs)
    case "$cpu_vendor" in
    GenuineIntel) echo intel ;;
    AuthenticAMD) echo amd ;;
    *) echo other ;;
    esac
}

install_arch_gentoo() {
    set_locale() {
        echo "C.UTF-8 UTF-8" >>$os_dir/etc/locale.gen
        chroot $os_dir locale-gen
    }

    # shellcheck disable=SC2317
    install_arch() {
        # 添加 swap
        create_swap_if_ram_less_than 1024 $os_dir/swapfile

        apk add arch-install-scripts

        # 设置 repo
        insert_into_file /etc/pacman.conf before '\[core\]' <<EOF
SigLevel = Never
ParallelDownloads = 5
EOF
        cat <<EOF >>/etc/pacman.conf
[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF
        mkdir -p /etc/pacman.d
        # shellcheck disable=SC2016
        case "$(uname -m)" in
        x86_64) dir='$repo/os/$arch' ;;
        aarch64) dir='$arch/$repo' ;;
        esac
        # shellcheck disable=SC2154
        echo "Server = $mirror/$dir" >/etc/pacman.d/mirrorlist

        # 安装系统
        # 要安装分区工具(包含 fsck.xxx)，用于 initramfs 检查分区数据
        # base 包含 e2fsprogs
        pkgs="base grub openssh"
        if is_efi; then
            pkgs="$pkgs efibootmgr dosfstools"
        fi
        if [ "$(uname -m)" = aarch64 ]; then
            pkgs="$pkgs archlinuxarm-keyring"
        fi
        pacstrap -K $os_dir $pkgs

        # dns
        cp_resolv_conf $os_dir

        # 挂载伪文件系统
        mount_pseudo_fs $os_dir

        # 要先设置语言，再安装内核，不然出现
        # ==> Creating gzip-compressed initcpio image: '/boot/initramfs-linux.img'
        # bsdtar: bsdtar: Failed to set default locale
        # Failed to set default locale
        set_locale
        if [ "$(uname -m)" = aarch64 ]; then
            chroot $os_dir pacman-key --lsign-key builder@archlinuxarm.org
        fi

        # firmware + microcode
        if ! is_virt; then
            chroot $os_dir pacman -Syu --noconfirm linux-firmware

            # amd microcode 包括在 linux-firmware 里面
            if [ "$(uname -m)" = x86_64 ]; then
                cpu_vendor="$(get_cpu_vendor)"
                case "$cpu_vendor" in
                intel | amd) chroot $os_dir pacman -Syu --noconfirm "$cpu_vendor-ucode" ;;
                esac
            fi
        fi

        # arm 的内核有多种选择，默认是 linux-aarch64，所以要添加 --noconfirm
        chroot $os_dir pacman -Syu --noconfirm linux
    }

    # shellcheck disable=SC2317
    install_gentoo() {
        # 添加 swap
        create_swap_if_ram_less_than 2048 $os_dir/swapfile

        # 解压系统
        apk add tar xz
        # shellcheck disable=SC2154
        download "$img" $os_dir/gentoo.tar.xz
        echo "Uncompressing Gentoo..."
        tar xpf $os_dir/gentoo.tar.xz -C $os_dir --xattrs-include='*.*' --numeric-owner
        rm $os_dir/gentoo.tar.xz
        apk del tar xz

        # dns
        cp_resolv_conf $os_dir

        # 挂载伪文件系统
        mount_pseudo_fs $os_dir

        # 下载仓库，选择 profile
        chroot $os_dir emerge-webrsync
        profile=$(
            # 筛选 stable systemd，再选择最短的
            if false; then
                chroot $os_dir eselect profile list | grep stable | grep systemd |
                    awk '(NR == 1 || length($2) < length(shortest)) { shortest = $2 } END { print shortest }'
            else
                chroot $os_dir eselect profile list | grep stable | grep systemd |
                    awk '{print length($2), $2}' | sort -n | head -1 | awk '{print $2}'
            fi
        )
        echo "Select profile: $profile"
        chroot $os_dir eselect profile set $profile

        # 设置 license
        cat <<EOF >>$os_dir/etc/portage/make.conf
ACCEPT_LICENSE="*"
EOF

        # 设置线程
        # 根据 cpu 核数，2G内存一个线程，取最小值
        threads_by_core=$(nproc --all)
        phy_ram=$(get_approximate_ram_size)
        threads_by_ram=$((phy_ram / 2048))
        if [ $threads_by_ram -eq 0 ]; then
            threads_by_ram=1
        fi
        threads=$(printf "%d\n" $threads_by_ram $threads_by_core | sort -n | head -1)
        cat <<EOF >>$os_dir/etc/portage/make.conf
MAKEOPTS="-j$threads"
EOF

        # 设置 http repo + binpkg repo
        # https://mirrors.ustc.edu.cn/gentoo/releases/amd64/autobuilds/current-stage3-amd64-systemd-mergedusr/stage3-amd64-systemd-mergedusr-20240317T170433Z.tar.xz
        mirror_short=$(echo "$img" | sed 's,/releases/.*,,')
        mirror_long=$(echo "$img" | sed 's,/autobuilds/.*,,')
        profile_ver=$(chroot $os_dir eselect profile show | grep -Eo '/[0-9.]*/' | cut -d/ -f2)

        if [ "$(uname -m)" = x86_64 ]; then
            if chroot $os_dir ld.so --help | grep supported | grep -q x86-64-v3; then
                binpkg_type=x86-64-v3
            else
                binpkg_type=x86-64
            fi
        else
            binpkg_type=arm64
        fi

        cat <<EOF >>$os_dir/etc/portage/make.conf
GENTOO_MIRRORS="$mirror_short"
FEATURES="getbinpkg"
EOF

        cat <<EOF >$os_dir/etc/portage/binrepos.conf/gentoobinhost.conf
[binhost]
priority = 9999
sync-uri = $mirror_long/binpackages/$profile_ver/$binpkg_type
EOF

        # 下载公钥
        chroot $os_dir getuto

        set_locale

        # 安装 git 会升级 glibc，此时 /etc/locale.gen 不能为空，否则会提示生成所有 locale
        # Generating all locales; edit /etc/locale.gen to save time/space
        chroot $os_dir emerge dev-vcs/git

        # 设置 git repo
        if is_in_china; then
            git_uri=https://mirrors.ustc.edu.cn/gentoo.git
        else
            # github 不支持 ipv6
            is_ipv4_has_internet && git_uri=https://github.com/gentoo-mirror/gentoo.git ||
                git_uri=https://anongit.gentoo.org/git/repo/gentoo.git
        fi

        mkdir -p $os_dir/etc/portage/repos.conf
        cat <<EOF >$os_dir/etc/portage/repos.conf/gentoo.conf
[gentoo]
location = /var/db/repos/gentoo
sync-type = git
sync-uri = $git_uri
EOF
        rm -rf $os_dir/var/db/repos/gentoo
        chroot $os_dir emerge --sync

        if [ "$(uname -m)" = x86_64 ]; then
            # https://packages.gentoo.org/packages/sys-block/io-scheduler-udev-rules
            chroot $os_dir emerge sys-block/io-scheduler-udev-rules
        fi

        if is_efi; then
            chroot $os_dir emerge sys-fs/dosfstools
        fi

        # firmware + microcode
        if ! is_virt; then
            chroot $os_dir emerge sys-kernel/linux-firmware

            # amd microcode 包括在 linux-firmware 里面
            if [ "$(uname -m)" = x86_64 ] && [ "$(get_cpu_vendor)" = intel ]; then
                chroot $os_dir emerge sys-firmware/intel-microcode
            fi
        fi

        # 安装 grub + 内核
        # TODO: 先判断是否有 binpkg，有的话不修改 GRUB_PLATFORMS
        is_efi && grub_platforms="efi-64" || grub_platforms="pc"
        echo GRUB_PLATFORMS=\"$grub_platforms\" >>$os_dir/etc/portage/make.conf
        echo "sys-kernel/installkernel dracut grub" >$os_dir/etc/portage/package.use/installkernel
        chroot $os_dir emerge sys-kernel/gentoo-kernel-bin
    }

    os_dir=/os

    # 挂载分区
    if is_efi || is_xda_gt_2t; then
        os_part_num=2
    else
        os_part_num=1
    fi

    mkdir -p /os
    mount -t ext4 /dev/${xda}*${os_part_num} /os

    if is_efi; then
        mkdir -p /os/efi
        mount -t vfat /dev/${xda}*1 /os/efi
    fi

    install_$distro

    # 初始化
    chroot $os_dir systemctl preset-all
    chroot $os_dir systemd-firstboot --force --setup-machine-id
    chroot $os_dir systemd-firstboot --force --timezone=Asia/Shanghai
    chroot $os_dir systemctl enable systemd-networkd
    chroot $os_dir systemctl enable systemd-resolved
    chroot $os_dir systemctl enable sshd
    allow_root_password_login $os_dir

    # 修改密码
    [ "$distro" = gentoo ] && sed -i 's/enforce=everyone/enforce=none/' $os_dir/etc/security/passwdqc.conf
    echo "root:$PASSWORD" | chroot $os_dir chpasswd
    [ "$distro" = gentoo ] && sed -i 's/enforce=none/enforce=everyone/' $os_dir/etc/security/passwdqc.conf

    # 网络配置
    apk add cloud-init
    useradd systemd-network
    touch net.cfg
    create_cloud_init_network_config net.cfg
    # 正常应该是 -D gentoo，但 alpine 的 cloud-init 包缺少 gentoo 配置
    cloud-init devel net-convert -p net.cfg -k yaml -d out -D alpine -O networkd
    cp out/etc/systemd/network/10-cloud-init-eth*.network $os_dir/etc/systemd/network/
    rm -rf out

    # 删除网卡名匹配
    sed -i '/^Name=/d' $os_dir/etc/systemd/network/10-cloud-init-eth*.network
    rm -rf net.cfg
    apk del cloud-init

    # 修复 onlink 网关
    if is_staticv4 || is_staticv6; then
        fix_sh=cloud-init-fix-onlink.sh
        download $confhome/$fix_sh $os_dir/$fix_sh
        chroot $os_dir bash /$fix_sh
        rm -f $os_dir/$fix_sh
    fi

    # ntp 用 systemd 自带的
    # TODO: vm agent + 随机数生成器

    # grub
    if is_efi; then
        # arch gentoo 推荐 efi 挂载在 /efi
        chroot $os_dir grub-install --efi-directory=/efi
        chroot $os_dir grub-install --efi-directory=/efi --removable
    else
        chroot $os_dir grub-install /dev/$xda
    fi

    # cmdline + 生成 grub.cfg
    if [ -d $os_dir/etc/default/grub.d ]; then
        file=$os_dir/etc/default/grub.d/cmdline.conf
    else
        file=$os_dir/etc/default/grub
    fi
    ttys_cmdline=$(get_ttys console=)
    echo GRUB_CMDLINE_LINUX=\"$ttys_cmdline\" >>$file
    chroot $os_dir grub-mkconfig -o /boot/grub/grub.cfg

    # fstab
    # fstab 可不写 efi 条目， systemd automount 会自动挂载
    apk add arch-install-scripts
    genfstab -U $os_dir | sed '/swap/d' >$os_dir/etc/fstab
    apk del arch-install-scripts

    # 删除 resolv.conf，不然 systemd-resolved 无法创建软链接
    rm_resolv_conf $os_dir

    # 删除 swap
    swapoff -a
    rm -rf $os_dir/swapfile
}

get_http_file_size_to() {
    var_name=$1
    url=$2

    size=''
    if wget --spider -S $url -o /tmp/headers.log; then
        # 网址重定向可能得到多个 Content-Length, 选最后一个
        if size=$(grep 'Content-Length:' /tmp/headers.log |
            tail -1 | awk '{print $2}' | grep .); then
            eval "$var_name='$size'"
        fi
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
    if ! command wget $img -O- --tries=5 --progress=bar:force | $prog -dc >/dev/$xda 2>/tmp/dd_stderr; then
        # vhd 文件结尾有 512 字节额外信息，可以忽略
        if grep -iq 'No space' /tmp/dd_stderr; then
            apk add parted
            disk_size=$(get_xda_size)
            disk_end=$((disk_size - 1))
            # 这里要 Ignore 两次
            # Error: Can't have a partition outside the disk!
            # Ignore/Cancel? i
            # Error: Can't have a partition outside the disk!
            # Ignore/Cancel? i
            last_part_end=$(yes i | parted /dev/$xda 'unit b print' ---pretend-input-tty |
                del_empty_lines | tail -1 | awk '{print $3}' | sed 's/B//')

            echo "Last part end: $last_part_end"
            echo "Disk end:      $disk_end"

            if [ "$last_part_end" -le "$disk_end" ]; then
                echo "Safely ignore no space error."
                return
            fi
        fi
        error_and_exit "$(cat /tmp/dd_stderr)"
    fi
}

get_xda_size() {
    blockdev --getsize64 /dev/$xda
}

get_nbd_size() {
    blockdev --getsize64 /dev/nbd0
}

is_xda_gt_2t() {
    disk_size=$(get_xda_size)
    disk_2t=$((2 * 1024 * 1024 * 1024 * 1024))
    [ "$disk_size" -gt "$disk_2t" ]
}

create_part() {
    # 除了 dd 都会用到

    # 分区工具
    apk add parted e2fsprogs
    if is_efi; then
        apk add dosfstools
    fi

    # 清除分区签名
    # TODO: 先检测iso链接/各种链接
    # wipefs -a /dev/$xda

    # xda*1 星号用于 nvme0n1p1 的字母 p
    # shellcheck disable=SC2154
    if [ "$distro" = windows ]; then
        get_http_file_size_to size_bytes $iso

        # 默认值，最大的iso 23h2 需要7g
        if [ -z "$size_bytes" ]; then
            size_bytes=$((7 * 1024 * 1024 * 1024))
        fi

        # 按iso容量计算分区大小
        # 200m 用于驱动/文件系统自身占用 + pagefile (手动 dism 释放镜像时使用)
        part_size="$((size_bytes / 1024 / 1024 + 200))MiB"

        apk add ntfs-3g-progs
        # 虽然ntfs3不需要fuse，但wimmount需要，所以还是要保留
        modprobe fuse ntfs3
        if is_efi; then
            # efi
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

            mkfs.fat -n efi /dev/$xda*1                 #1 efi
            echo                                        #2 msr
            mkfs.ext4 -E nodiscard -F -L os /dev/$xda*3 #3 os
            mkfs.ntfs -f -F -L installer /dev/$xda*4    #4 installer
        else
            # bios + mbr 启动盘最大可用 2t
            is_xda_gt_2t && max_usable_size=2TiB || max_usable_size=100%
            parted /dev/$xda -s -- \
                mklabel msdos \
                mkpart primary ntfs 1MiB -${part_size} \
                mkpart primary ntfs -${part_size} ${max_usable_size} \
                set 1 boot on
            update_part /dev/$xda

            mkfs.ext4 -E nodiscard -F -L os /dev/$xda*1 #1 os
            mkfs.ntfs -f -F -L installer /dev/$xda*2    #2 installer
        fi
    elif is_use_cloud_image; then
        installer_part_size="$(get_ci_installer_part_size)"
        # 这几个系统不使用dd，而是复制文件
        if [ "$distro" = centos ] || [ "$distro" = alma ] || [ "$distro" = rocky ] ||
            [ "$distro" = oracle ] || [ "$distro" = redhat ] ||
            [ "$distro" = anolis ] || [ "$distro" = opencloudos ] || [ "$distro" = openeuler ] ||
            [ "$distro" = ubuntu ]; then
            fs="$(get_os_fs)"
            if is_efi; then
                parted /dev/$xda -s -- \
                    mklabel gpt \
                    mkpart '" "' fat32 1MiB 101MiB \
                    mkpart '" "' $fs 101MiB -$installer_part_size \
                    mkpart '" "' ext4 -$installer_part_size 100% \
                    set 1 esp on
                update_part /dev/$xda

                mkfs.fat -n efi /dev/$xda*1                        #1 efi
                echo                                               #2 os 用目标系统的格式化工具
                mkfs.ext4 -E nodiscard -F -L installer /dev/$xda*3 #3 installer
            else
                parted /dev/$xda -s -- \
                    mklabel gpt \
                    mkpart '" "' ext4 1MiB 2MiB \
                    mkpart '" "' $fs 2MiB -$installer_part_size \
                    mkpart '" "' ext4 -$installer_part_size 100% \
                    set 1 bios_grub on
                update_part /dev/$xda

                echo                                               #1 bios_boot
                echo                                               #2 os 用目标系统的格式化工具
                mkfs.ext4 -E nodiscard -F -L installer /dev/$xda*3 #3 installer
            fi
        else
            # 使用 dd qcow2
            # fedora debian opensuse arch gentoo
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' ext4 1MiB -$installer_part_size \
                mkpart '" "' ext4 -$installer_part_size 100%
            update_part /dev/$xda

            mkfs.ext4 -E nodiscard -F -L os /dev/$xda*1        #1 os
            mkfs.ext4 -E nodiscard -F -L installer /dev/$xda*2 #2 installer
        fi
    elif [ "$distro" = alpine ] || [ "$distro" = arch ] || [ "$distro" = gentoo ]; then
        if is_efi; then
            # efi
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' fat32 1MiB 101MiB \
                mkpart '" "' ext4 101MiB 100% \
                set 1 boot on
            update_part /dev/$xda

            mkfs.fat /dev/$xda*1                  #1 efi
            mkfs.ext4 -E nodiscard -F /dev/$xda*2 #2 os
        elif is_xda_gt_2t; then
            # bios > 2t
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' ext4 1MiB 2MiB \
                mkpart '" "' ext4 2MiB 100% \
                set 1 bios_grub on
            update_part /dev/$xda

            echo                                  #1 bios_boot
            mkfs.ext4 -E nodiscard -F /dev/$xda*2 #2 os
        else
            # bios
            parted /dev/$xda -s -- \
                mklabel msdos \
                mkpart primary ext4 1MiB 100% \
                set 1 boot on
            update_part /dev/$xda

            mkfs.ext4 -E nodiscard -F /dev/$xda*1 #1 os
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

            mkfs.fat -n efi /dev/$xda*1                 #1 efi
            mkfs.ext4 -E nodiscard -F -L os /dev/$xda*2 #2 os
            mkfs.fat -n installer /dev/$xda*3           #3 installer
        elif is_xda_gt_2t; then
            # bios > 2t
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' ext4 1MiB 2MiB \
                mkpart '" "' ext4 2MiB -2GiB \
                mkpart '" "' ext4 -2GiB 100% \
                set 1 bios_grub on
            update_part /dev/$xda

            echo                                        #1 bios_boot
            mkfs.ext4 -E nodiscard -F -L os /dev/$xda*2 #2 os
            mkfs.fat -n installer /dev/$xda*3           #3 installer
        else
            # bios
            parted /dev/$xda -s -- \
                mklabel msdos \
                mkpart primary ext4 1MiB -2GiB \
                mkpart primary ext4 -2GiB 100% \
                set 1 boot on
            update_part /dev/$xda

            mkfs.ext4 -E nodiscard -F -L os /dev/$xda*1 #1 os
            mkfs.fat -n installer /dev/$xda*2           #2 installer
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

    # alpine 删除分区工具，防止 256M 小机爆内存
    # setup-disk /dev/sda 会保留格式化工具，我们也保留
    if [ "$distro" = alpine ]; then
        apk del parted
    fi
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

get_yq_name() {
    if grep -q '3\.1[6789]' /etc/alpine-release; then
        echo yq
    else
        echo yq-go
    fi
}

create_cloud_init_network_config() {
    ci_file=$1

    apk add "$(get_yq_name)"

    need_set_dns4=false
    need_set_dns6=false

    config_id=0
    for ethx in $(get_eths); do
        get_netconf_to mac_addr

        # shellcheck disable=SC2154
        yq -i ".network.version=1 |
           .network.config[$config_id].type=\"physical\" |
           .network.config[$config_id].name=\"$ethx\" |
           .network.config[$config_id].mac_address=\"$mac_addr\"
           " $ci_file

        subnet_id=0

        # ipv4
        if is_dhcpv4; then
            yq -i ".network.config[$config_id].subnets[$subnet_id] = {\"type\": \"dhcp4\"}" $ci_file
            subnet_id=$((subnet_id + 1))
        elif is_staticv4; then
            need_set_dns4=true
            get_netconf_to ipv4_addr
            get_netconf_to ipv4_gateway
            yq -i ".network.config[$config_id].subnets[$subnet_id] = {
                    \"type\": \"static\",
                    \"address\": \"$ipv4_addr\",
                    \"gateway\": \"$ipv4_gateway\" }
                    " $ci_file

            # 旧版 cloud-init 有 bug
            # 有的版本会只从第一种配置中读取 dns，有的从第二种读取
            # 因此写两种配置
            if dns4_list=$(get_current_dns_v4); then
                for cur in $dns4_list; do
                    yq -i ".network.config[$config_id].subnets[$subnet_id].dns_nameservers += [\"$cur\"]" $ci_file
                done
            fi
            subnet_id=$((subnet_id + 1))
        fi

        # ipv6
        # slaac:  ipv6_slaac
        # └─enable_other_flag: ipv6_dhcpv6-stateless
        # dhcpv6: ipv6_dhcpv6-stateful

        # ipv6
        if is_slaac; then
            if is_enable_other_flag; then
                type=ipv6_dhcpv6-stateless
            else
                type=ipv6_slaac
            fi
            yq -i ".network.config[$config_id].subnets[$subnet_id] = {\"type\": \"$type\"}" $ci_file

        elif is_dhcpv6; then
            yq -i ".network.config[$config_id].subnets[$subnet_id] = {\"type\": \"ipv6_dhcpv6-stateful\"}" $ci_file

        elif is_staticv6; then
            get_netconf_to ipv6_addr
            get_netconf_to ipv6_gateway
            # el7 不认识 static6，但可改成 static，作用相同
            # >=20.1 修复
            # https://github.com/canonical/cloud-init/commit/dacdd30080bd8183d1f1c1dc9dbcbc8448301529
            # anolis 7:        cloud-init 19.1
            # openeuler 20.03: cloud-init 19.4
            # shellcheck disable=SC2154
            if { [ "$distro" = centos ] && [ "$releasever" = 7 ]; } ||
                { [ "$distro" = oracle ] && [ "$releasever" = 7 ]; } ||
                { [ "$distro" = anolis ] && [ "$releasever" = 7 ]; } ||
                { [ "$distro" = openeuler ] && [ "$releasever" = 20.03 ]; }; then
                type_ipv6_static=static
            else
                type_ipv6_static=static6
            fi
            yq -i ".network.config[$config_id].subnets[$subnet_id] = {
                    \"type\": \"$type_ipv6_static\",
                    \"address\": \"$ipv6_addr\",
                    \"gateway\": \"$ipv6_gateway\" }
                    " $ci_file
            if should_disable_ra_slaac; then
                yq -i ".network.config[$config_id].accept-ra = false" $ci_file
            fi
        fi

        # 有 ipv6 但需设置 dns 的情况
        if is_need_manual_set_dnsv6 && dns6_list=$(get_current_dns_v6); then
            need_set_dns6=true
            for cur in $dns6_list; do
                yq -i ".network.config[$config_id].subnets[$subnet_id].dns_nameservers += [\"$cur\"]" $ci_file
            done
        fi

        config_id=$((config_id + 1))
    done

    if $need_set_dns4 || $need_set_dns6; then
        yq -i ".network.config[$config_id].type=\"nameserver\"" $ci_file
        if $need_set_dns4 && dns4_list=$(get_current_dns_v4); then
            for cur in $dns4_list; do
                yq -i ".network.config[$config_id].address += [\"$cur\"]" $ci_file
            done
        fi
        if $need_set_dns6 && dns6_list=$(get_current_dns_v6); then
            for cur in $dns6_list; do
                yq -i ".network.config[$config_id].address += [\"$cur\"]" $ci_file
            done
        fi
        # 如果 network.config[$config_id] 没有 address，则删除，避免低版本 cloud-init 报错
        yq -i "del(.network.config[$config_id] | select(has(\"address\") | not))" $ci_file
    fi

    apk del "$(get_yq_name)"
}

truncate_machine_id() {
    os_dir=$1

    truncate -s 0 $os_dir/etc/machine-id
}

download_cloud_init_config() {
    os_dir=$1

    ci_file=$os_dir/etc/cloud/cloud.cfg.d/99_fallback.cfg
    download $confhome/cloud-init.yaml $ci_file
    # 删除注释行，除了第一行
    sed -i '1!{/^[[:space:]]*#/d}' $ci_file

    # 修改密码
    sed -i "s/@PASSWORD@/$PASSWORD/" $ci_file

    # swapfile
    # 如果分区表中已经有swapfile就跳过，例如arch
    if ! grep -w swap $os_dir/etc/fstab; then
        # btrfs
        # 目前只有 arch 和 fedora 镜像使用 btrfs
        # 等 fedora 39 cloud-init 升级到 v23.3 后删除
        if mount | grep 'on /os type btrfs'; then
            insert_into_file $ci_file after '^runcmd:' <<EOF
  - btrfs filesystem mkswapfile --size 1G /swapfile
  - swapon /swapfile
  - echo "/swapfile none swap defaults 0 0" >> /etc/fstab
  - systemctl daemon-reload
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
    os_dir=$1

    # https://learn.microsoft.com/windows-hardware/manufacture/desktop/windows-setup-states
    # https://learn.microsoft.com/troubleshoot/azure/virtual-machines/reset-local-password-without-agent
    # https://learn.microsoft.com/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup

    # 判断用 SetupComplete 还是组策略
    state_ini=$os_dir/Windows/Setup/State/State.ini
    cat $state_ini
    if grep -q IMAGE_STATE_COMPLETE $state_ini; then
        use_gpo=true
    else
        use_gpo=false
    fi

    # 下载共同的子脚本
    # 可能 unattend.xml 已经设置了ExtendOSPartition，不过运行resize没副作用
    bats="windows-resize.bat"
    download $confhome/windows-resize.bat $os_dir/windows-resize.bat
    for ethx in $(get_eths); do
        create_win_set_netconf_script $os_dir/windows-set-netconf-$ethx.bat
        bats="$bats windows-set-netconf-$ethx.bat"
    done

    if $use_gpo; then
        # 使用组策略
        gpt_ini=$os_dir/Windows/System32/GroupPolicy/gpt.ini
        scripts_ini=$os_dir/Windows/System32/GroupPolicy/Machine/Scripts/scripts.ini
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
        download $confhome/windows-del-gpo.bat $os_dir/windows-del-gpo.bat
    else
        # 使用 SetupComplete
        setup_complete=$os_dir/Windows/Setup/Scripts/SetupComplete.cmd
        mkdir -p "$(dirname $setup_complete)"

        # 添加到 C:\Setup\Scripts\SetupComplete.cmd 最前面
        # call 防止子 bat 删除自身后中断主脚本
        setup_complete_mod=$(mktemp)
        for bat in $bats; do
            echo "if exist %SystemDrive%\\$bat (call %SystemDrive%\\$bat)" >>$setup_complete_mod
        done

        # 复制原来的内容
        if [ -f $setup_complete ]; then
            cat $setup_complete >>$setup_complete_mod
        fi

        unix2dos $setup_complete_mod

        # cat 可以保留权限
        cat $setup_complete_mod >$setup_complete
    fi
}

get_axx64() {
    case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    esac
}

is_file_or_link() {
    # -e / -f 坏软连接，返回 false
    # -L 坏软连接，返回 true
    [ -f $1 ] || [ -L $1 ]
}

cp_resolv_conf() {
    os_dir=$1
    if is_file_or_link $os_dir/etc/resolv.conf &&
        ! is_file_or_link $os_dir/etc/resolv.conf.orig; then
        mv $os_dir/etc/resolv.conf $os_dir/etc/resolv.conf.orig
    fi
    cp -f /etc/resolv.conf $os_dir/etc/resolv.conf
}

rm_resolv_conf() {
    os_dir=$1
    rm -f $os_dir/etc/resolv.conf $os_dir/etc/resolv.conf.orig
}

restore_resolv_conf() {
    os_dir=$1
    if is_file_or_link $os_dir/etc/resolv.conf.orig; then
        mv -f $os_dir/etc/resolv.conf.orig $os_dir/etc/resolv.conf
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

    # 修复 onlink 网关
    add_onlink_script_if_need() {
        if is_staticv4 || is_staticv6; then
            fix_sh=cloud-init-fix-onlink.sh
            download $confhome/$fix_sh $os_dir/$fix_sh
            insert_into_file $ci_file after '^runcmd:' <<EOF
  - bash /$fix_sh && rm -f /$fix_sh
EOF
        fi
    }

    download_cloud_init_config $os_dir

    truncate_machine_id $os_dir

    # 为红帽系禁用 selinux kdump
    if [ -f $os_dir/etc/redhat-release ]; then
        find_and_mount /boot
        find_and_mount /boot/efi
        disable_selinux_kdump $os_dir
    fi

    # debian 网络问题
    # 注意 ubuntu 也有 /etc/debian_version
    if [ "$distro" = debian ]; then
        # 修复 onlink 网关
        add_onlink_script_if_need

        mount_pseudo_fs $os_dir

        # 检测机器是否能用 cloud 内核
        axx64=$(get_axx64)
        eths=$(get_eths)
        if ls $os_dir/boot/vmlinuz-*-cloud-$axx64 2>/dev/null &&
            ! sh /can_use_cloud_kernel.sh "$xda" $eths; then

            cp_resolv_conf $os_dir
            chroot $os_dir apt update
            DEBIAN_FRONTEND=noninteractive chroot $os_dir apt install -y linux-image-$axx64

            # 标记云内核包
            # apt-mark showmanual 结果为空，返回值也是 0
            if pkgs=$(chroot $os_dir apt-mark showmanual linux-*-cloud-$axx64 | grep .); then
                chroot $os_dir apt-mark auto $pkgs

                # 使用 autoremove
                chroot_apt_autoremove $os_dir
            fi
            restore_resolv_conf $os_dir
        fi

        if [ "$releasever" -le 11 ]; then
            cp_resolv_conf $os_dir
            chroot $os_dir apt update

            if true; then
                # 将 debian 11 设置为 12 一样的网络管理器
                # 可解决 ifupdown dhcp 不支持 24位掩码+不规则网关的问题
                DEBIAN_FRONTEND=noninteractive chroot $os_dir apt install -y netplan.io
                chroot $os_dir systemctl disable networking resolvconf
                chroot $os_dir systemctl enable systemd-networkd systemd-resolved
                rm_resolv_conf $os_dir
                ln -sf ../run/systemd/resolve/stub-resolv.conf $os_dir/etc/resolv.conf
                insert_into_file $os_dir/etc/cloud/cloud.cfg.d/99_fallback.cfg after '#cloud-config' <<EOF
system_info:
  network:
    renderers: [netplan]
    activators: [netplan]
EOF

            else
                # debian 11 默认不支持 rdnss，要安装 rdnssd 或者 nm
                DEBIAN_FRONTEND=noninteractive chroot $os_dir apt install -y rdnssd
                # 不会自动建立链接，因此不能删除
                restore_resolv_conf $os_dir
            fi
        fi
    fi

    # opensuse leap
    if grep opensuse-leap $os_dir/etc/os-release; then
        # 修复 onlink 网关
        add_onlink_script_if_need
    fi

    # opensuse tumbleweed
    # TODO: cloud-init 更新后删除
    if grep opensuse-tumbleweed $os_dir/etc/os-release; then
        touch $os_dir/etc/NetworkManager/NetworkManager.conf
    fi

    # arch
    if [ -f $os_dir/etc/arch-release ]; then
        # 修复 onlink 网关
        add_onlink_script_if_need

        # 同步证书
        cp_resolv_conf $os_dir
        mount_pseudo_fs $os_dir
        chroot $os_dir pacman-key --init
        chroot $os_dir pacman-key --populate
        rm_resolv_conf $os_dir
    fi

    # gentoo
    if [ -f $os_dir/etc/gentoo-release ]; then
        # 挂载伪文件系统
        mount_pseudo_fs $os_dir
        cp_resolv_conf $os_dir

        # 在这里修改密码，而不是用cloud-init，因为我们的默认密码太弱
        sed -i 's/enforce=everyone/enforce=none/' $os_dir/etc/security/passwdqc.conf
        echo "root:$PASSWORD" | chroot $os_dir chpasswd
        sed -i 's/enforce=none/enforce=everyone/' $os_dir/etc/security/passwdqc.conf

        # 下载仓库，选择 profile
        chroot $os_dir emerge-webrsync
        profile=$(chroot $os_dir eselect profile list | grep stable | grep systemd |
            awk '{print length($2), $2}' | sort -n | head -1 | awk '{print $2}')
        chroot $os_dir eselect profile set $profile

        # 删除 resolv.conf，不然 systemd-resolved 无法创建软链接
        rm_resolv_conf $os_dir

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

        # 如果创建了 cloud-init.disabled，重启后网络不受 networkd 管理
        # 因为网卡名变回了 ens3 而不是 eth0
        # 因此要删除 networkd 的网卡名匹配
        insert_into_file $ci_file after '^runcmd:' <<EOF
  - sed -i '/^Name=/d' /etc/systemd/network/10-cloud-init-eth*.network
EOF

        # 修复 onlink 网关
        add_onlink_script_if_need
    fi
}

modify_os_on_disk() {
    only_process=$1

    update_part /dev/$xda

    # dd linux 的时候不用修改硬盘内容
    if [ "$distro" = "dd" ] && ! lsblk -f /dev/$xda | grep ntfs; then
        return
    fi

    mkdir -p /os
    # 按分区容量大到小，依次寻找系统分区
    for part in $(lsblk /dev/$xda*[0-9] --sort SIZE -no NAME | tac); do
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
                # find 不是很聪明
                # find /mnt/c -iname windows -type d -maxdepth 1
                # find: /mnt/c/pagefile.sys: Permission denied
                # find: /mnt/c/swapfile.sys: Permission denied
                # shellcheck disable=SC2010
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

create_swap_if_ram_less_than() {
    need_ram=$1
    swapfile=$2

    phy_ram=$(get_approximate_ram_size)
    swapsize=$((need_ram - phy_ram))
    if [ $swapsize -gt 0 ]; then
        create_swap $swapsize $swapfile
    fi
}

create_swap() {
    swapsize=$1
    swapfile=$2

    if ! grep $swapfile /proc/swaps; then
        fallocate -l ${swapsize}M $swapfile
        chmod 0600 $swapfile
        mkswap $swapfile
        swapon $swapfile
    fi
}

# arch gentoo 常规安装用
allow_root_password_login() {
    os_dir=$1

    # 允许 root 密码登录
    # arch 没有 /etc/ssh/sshd_config.d/ 文件夹
    # opensuse tumbleweed 有 /etc/ssh/sshd_config.d/ 文件夹，但没有 /etc/ssh/sshd_config，但有/usr/etc/ssh/sshd_config
    if grep 'Include.*/etc/ssh/sshd_config.d' $os_dir/etc/ssh/sshd_config; then
        mkdir -p $os_dir/etc/ssh/sshd_config.d/
        echo 'PermitRootLogin yes' >$os_dir/etc/ssh/sshd_config.d/01-permitrootlogin.conf
    else
        if ! grep -x 'PermitRootLogin yes' $os_dir/etc/ssh/sshd_config; then
            echo 'PermitRootLogin yes' >>$os_dir/etc/ssh/sshd_config
        fi
    fi
}

disable_selinux_kdump() {
    os_dir=$1

    # selinux
    if [ -f $os_dir/etc/selinux/config ]; then
        sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' $os_dir/etc/selinux/config
    fi

    # https://access.redhat.com/solutions/3176
    # shellcheck disable=SC2154
    # openeuler 版本是 24.03
    if [ "$distro" = openeuler ] || [ "$releasever" -ge 9 ]; then
        chroot $os_dir grubby --update-kernel ALL --args selinux=0
    fi

    # kdump
    # grubby 只处理 GRUB_CMDLINE_LINUX，不会处理 GRUB_CMDLINE_LINUX_DEFAULT
    # rocky 的 GRUB_CMDLINE_LINUX_DEFAULT 有 crashkernel=auto

    # 新安装的内核依然有 crashkernel，好像是 bug
    # https://forums.rockylinux.org/t/how-do-i-remove-crashkernel-from-cmdline/13346
    # 验证过程
    # yum remove --oldinstallonly   # 删除旧内核
    # rm -rf /boot/loader/entries/* # 删除启动条目
    # yum reinstall kernel-core     # 重新安装新内核
    # cat /boot/loader/entries/*    # 依然有 crashkernel=1G-4G:192M,4G-64G:256M,64G-:512M

    sed -i 's/crashkernel=[^ ]*/crashkernel=no/' $os_dir/etc/default/grub
    chroot $os_dir grubby --update-kernel ALL --args crashkernel=no
    # el7 上面那条 grubby 命令不能设置 /etc/default/grub
    sed -i 's/crashkernel=[^ "]*/crashkernel=no/' $os_dir/etc/default/grub
    if chroot $os_dir systemctl is-enabled kdump; then
        chroot $os_dir systemctl disable kdump
    fi
}

download_qcow() {
    apk add qemu-img

    mkdir -p /installer
    mount /dev/disk/by-label/installer /installer

    qcow_file=/installer/cloud_image.qcow2
    if [ "$distro" = openeuler ]; then
        prog=xz
        apk add wget $prog
        command wget $img -O- --tries=5 --progress=bar:force | $prog -dc >$qcow_file
    else
        download "$img" "$qcow_file"
    fi
}

connect_qcow() {
    modprobe nbd nbds_max=1
    qemu-nbd -c /dev/nbd0 $qcow_file

    # 需要等待一下
    # https://github.com/canonical/cloud-utils/blob/main/bin/mount-image-callback
    while ! blkid /dev/nbd0; do
        echo "Waiting for qcow file to be mounted..."
        sleep 5
    done
}

disconnect_qcow() {
    if [ -f /sys/block/nbd0/pid ]; then
        qemu-nbd -d /dev/nbd0

        # 需要等待一下
        while fuser -sm $qcow_file; do
            echo "Waiting for qcow file to be unmounted..."
            sleep 5
        done
    fi
}

get_os_fs() {
    case "$distro" in
    ubuntu) echo ext4 ;;
    anolis | openeuler) echo ext4 ;;
    centos | alma | rocky | oracle | redhat) echo xfs ;;
    opencloudos) echo xfs ;;
    esac
}

get_ci_installer_part_size() {
    # 8
    # https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2 600m
    # https://download.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 1.8g
    # https://yum.oracle.com/templates/OracleLinux/OL8/u9/x86_64/OL8U9_x86_64-kvm-b219.qcow2 1g
    # https://rhel-8.10-x86_64-kvm.qcow2 1g

    # 9
    # https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2 1.2g
    # https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2 600m
    # https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2 600m
    # https://yum.oracle.com/templates/OracleLinux/OL9/u3/x86_64/OL9U3_x86_64-kvm-b220.qcow2 600m
    # rhel-9.4-x86_64-kvm.qcow2 900m

    # https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/cloud/nocloud_alpine-3.19.1-x86_64-uefi-cloudinit-r0.qcow2 200m
    # https://kali.download/cloud-images/current/kali-linux-2024.1-cloud-genericcloud-amd64.tar.xz 200m
    # https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2 300m
    # https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.aarch64-Cloud.qcow2 300m
    # https://mirror.fcix.net/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2 400m
    # https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2 500m
    # https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 500m
    # https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img 500m
    # https://gentoo.osuosl.org/experimental/amd64/openstack/gentoo-openstack-amd64-systemd-latest.qcow2 800m

    # openeuler 20.03 3g
    if [ "$distro" = openeuler ]; then
        echo 3GiB
    else
        if get_http_file_size_to size_bytes $img >&2 && [ -n "$size_bytes" ]; then
            # 额外 +100M 文件系统保留大小 和 qcow2 写入空间
            size_bytes_mb=$((size_bytes / 1024 / 1024 + 100))
            # 最少 1g ，因为可能要用作临时 swap
            echo "$((size_bytes_mb / 1024 + 1))GiB"
        else
            # 如果没获取到文件大小
            echo 2GiB
        fi
    fi
}

chroot_dnf() {
    if is_have_cmd_on_disk /os/ dnf; then
        chroot /os/ dnf -y "$@"
    else
        chroot /os/ yum -y "$@"
    fi
}

chroot_apt_autoremove() {
    os_dir=$1

    change_confs() {
        action=$1

        # 只有 16.04 有 01autoremove-kernels
        # 16.04 结束支持后删除
        for conf in 01autoremove 01autoremove-kernels; do
            file=$os_dir/etc/apt/apt.conf.d/$conf
            case "$action" in
            change)
                if [ -f $file ]; then
                    sed -i.orig 's/VersionedKernelPackages/x/; s/NeverAutoRemove/x/' $file
                fi
                ;;
            restore)
                if [ -f $file.orig ]; then
                    mv $file.orig $file
                fi
                ;;
            esac
        done
    }

    change_confs change
    DEBIAN_FRONTEND=noninteractive chroot $os_dir apt autoremove --purge -y
    change_confs restore
}

del_default_user() {
    os_dir=$1

    while read -r user; do
        if grep ^$user':\$' "$os_dir/etc/shadow"; then
            echo "Deleting user $user"
            chroot "$os_dir" userdel -rf "$user"
        fi
    done < <(grep -v nologin$ "$os_dir/etc/passwd" | cut -d: -f1 | grep -v root)
}

install_qcow_by_copy() {
    mount_nouuid() {
        case "$(get_os_fs)" in
        ext4) mount "$@" ;;
        xfs) mount -o nouuid "$@" ;;
        esac
    }

    efi_mount_opts=$(
        case "$distro" in
        ubuntu) echo "umask=0077" ;;
        *) echo "defaults,uid=0,gid=0,umask=077,shortname=winnt" ;;
        esac
    )

    connect_qcow

    # 镜像分区格式
    # centos/rocky/alma/rhel: xfs
    # oracle x86_64:          lvm + xfs
    # oracle aarch64 cloud:   xfs

    is_lvm_image=false
    if lsblk -f /dev/nbd0p* | grep LVM2_member; then
        is_lvm_image=true
        apk add lvm2
        lvscan
        vg=$(pvs | grep /dev/nbd0p | awk '{print $2}')
        lvchange -ay "$vg"
    fi

    # TODO: 系统分区应该是最后一个分区
    # 选择最大分区
    os_part=$(lsblk /dev/nbd0p* --sort SIZE -no NAME,FSTYPE | grep -E 'ext4|xfs' | tail -1 | awk '{print $1}')
    efi_part=$(lsblk /dev/nbd0p* --sort SIZE -no NAME,PARTTYPE | grep -i "$EFI_UUID" | awk '{print $1}')
    # 排除前两个，再选择最大分区
    # alma 9 boot 分区的类型不是规定的 uuid
    # openeuler boot 分区是 fat 格式
    boot_part=$(lsblk /dev/nbd0p* --sort SIZE -no NAME,FSTYPE | grep -E 'ext4|xfs|fat' | awk '{print $1}' |
        grep -vx "$os_part" | {
        if [ -n "$efi_part" ]; then
            grep -vx "$efi_part"
        else
            cat
        fi
    } | tail -1 | awk '{print $1}')

    if $is_lvm_image; then
        os_part="mapper/$os_part"
    fi

    lsblk -f /dev/nbd0 -o +PARTTYPE
    echo "Part OS:   $os_part"
    echo "Part EFI:  $efi_part"
    echo "Part Boot: $boot_part"

    # 分区寻找方式
    # 系统/分区          cmdline:root  fstab:efi
    # rocky             LABEL=rocky   LABEL=EFI
    # ubuntu            PARTUUID      LABEL=UEFI
    # 其他el/ol         UUID           UUID

    # read -r os_part_uuid os_part_label < <(lsblk /dev/$os_part -no UUID,LABEL)
    os_part_uuid=$(lsblk /dev/$os_part -no UUID)
    os_part_label=$(lsblk /dev/$os_part -no LABEL)

    if [ -n "$efi_part" ]; then
        efi_part_uuid=$(lsblk /dev/$efi_part -no UUID)
        efi_part_label=$(lsblk /dev/$efi_part -no LABEL)
    fi

    mkdir -p /nbd /nbd-boot /nbd-efi /os

    # 使用目标系统的格式化程序
    # centos8 如果用alpine格式化xfs，grub2-mkconfig和grub2里面都无法识别xfs分区
    mount_nouuid /dev/$os_part /nbd/
    mount_pseudo_fs /nbd/
    case "$(get_os_fs)" in
    ext4) chroot /nbd mkfs.ext4 -E nodiscard -F -L "$os_part_label" -U "$os_part_uuid" /dev/$xda*2 ;;
    xfs) chroot /nbd mkfs.xfs -K -f -L "$os_part_label" -m uuid=$os_part_uuid /dev/$xda*2 ;;
    esac
    umount -R /nbd/

    # TODO: ubuntu 镜像缺少 mkfs.fat/vfat/dosfstools? initrd 不需要检查fs完整性？

    # 复制系统
    echo Copying os partition...
    mount_nouuid -o ro /dev/$os_part /nbd/
    mount -o noatime /dev/$xda*2 /os/
    cp -a /nbd/* /os/

    # 复制boot分区，如果有
    if [ -n "$boot_part" ]; then
        echo Copying boot partition...
        mount_nouuid -o ro /dev/$boot_part /nbd-boot/
        cp -a /nbd-boot/* /os/boot/
    fi

    # efi 分区
    if is_efi; then
        # 挂载 efi
        mkdir -p /os/boot/efi/
        mount -o $efi_mount_opts /dev/$xda*1 /os/boot/efi/

        # 复制文件
        if [ -n "$efi_part" ]; then
            echo Copying efi partition...
            mount -o ro /dev/$efi_part /nbd-efi/
            cp -a /nbd-efi/* /os/boot/efi/
        fi
    fi

    # 取消挂载 nbd
    umount /nbd/ /nbd-boot/ /nbd-efi/ || true
    if is_have_cmd vgchange; then
        vgchange -an
    fi
    disconnect_qcow

    # 已复制并断开连接 qcow，可删除 qemu-img
    apk del qemu-img

    # 如果镜像有efi分区，复制其uuid
    # 如果有相同uuid的fat分区，则无法挂载
    # 所以要先复制efi分区，断开nbd再复制uuid
    if is_efi && [ -n "$efi_part_uuid" ]; then
        umount /os/boot/efi/
        apk add mtools
        mlabel -N "$(echo $efi_part_uuid | sed 's/-//')" -i /dev/$xda*1 ::$efi_part_label
        update_part /dev/$xda
        mount -o $efi_mount_opts /dev/$xda*1 /os/boot/efi/
    fi

    # 挂载伪文件系统
    mount_pseudo_fs /os/

    # 创建 swap
    umount /installer/
    mkswap /dev/$xda*3
    swapon /dev/$xda*3

    modify_el_ol() {
        # resolv.conf
        cp_resolv_conf /os

        # 删除镜像的默认账户，防止使用默认账户密码登录 ssh
        del_default_user /os

        # selinux kdump
        disable_selinux_kdump /os

        # 部分镜像例如 centos7 要手动删除 machine-id
        truncate_machine_id /os

        # el7 yum 可能会使用 ipv6，即使没有 ipv6 网络
        if [ "$releasever" = 7 ]; then
            if [ "$(cat /dev/netconf/eth*/ipv6_has_internet | sort -u)" = 0 ]; then
                echo 'ip_resolve=4' >>/os/etc/yum.conf
            fi
        fi

        # centos 7 eol 特殊处理
        if [ "$releasever" = 7 ] && [ -f /os/etc/yum.repos.d/CentOS-Base.repo ]; then
            # 保持默认的 http 因为自带的 ssl 证书可能过期
            if is_in_china; then
                mirror=mirrors.ustc.edu.cn/centos-vault
            else
                mirror=vault.centos.org
            fi
            sed -Ei -e 's,(mirrorlist=),#\1,' \
                -e "s,#(baseurl=http://)mirror.centos.org,\1$mirror," /os/etc/yum.repos.d/CentOS-Base.repo
            chroot_dnf install NetworkManager
        fi

        # anolis 7 镜像自带 nm

        # 删除云镜像自带的 dhcp 配置，防止歧义
        # clout-init 网络配置在 /etc/sysconfig/network-scripts/
        rm -rf /os/etc/NetworkManager/system-connections/*.nmconnection
        rm -rf /os/etc/sysconfig/network-scripts/ifcfg-*

        # 修复 cloud-init 添加了 IPV*_FAILURE_FATAL
        # 甲骨文 dhcp6 获取不到 IP 将视为 fatal，原有的 ipv4 地址也会被删除
        insert_into_file $ci_file after '^runcmd:' <<EOF
  - sed -i '/IPV4_FAILURE_FATAL/d' /etc/sysconfig/network-scripts/ifcfg-* || true
  - sed -i '/IPV6_FAILURE_FATAL/d' /etc/sysconfig/network-scripts/ifcfg-* || true
  - systemctl restart NetworkManager
EOF

        # fstab 删除多余分区
        # alma/rocky 镜像有 boot 分区
        # oracle 镜像有 swap 分区
        sed -i '/[[:space:]]\/boot[[:space:]]/d' /os/etc/fstab
        sed -i '/[[:space:]]swap[[:space:]]/d' /os/etc/fstab

        # os_part 变量:
        # mapper/vg_main-lv_root
        # mapper/opencloudos-root

        # oracle/opencloudos 系统盘从 lvm 改成 uuid 挂载
        sed -i "s,/dev/$os_part,UUID=$os_part_uuid," /os/etc/fstab
        if ls /os/boot/loader/entries/*.conf 2>/dev/null; then
            # options root=/dev/mapper/opencloudos-root ro console=ttyS0,115200n8 no_timer_check net.ifnames=0 crashkernel=1800M-64G:256M,64G-128G:512M,128G-486G:768M,486G-972G:1024M,972G-:2048M rd.lvm.lv=opencloudos/root rhgb quiet
            sed -i "s,/dev/$os_part,UUID=$os_part_uuid," /os/boot/loader/entries/*.conf
        fi

        # oracle/opencloudos 移除 lvm cmdline
        chroot /os grubby --update-kernel ALL --remove-args "resume rd.lvm.lv"
        # el7 上面那条 grubby 命令不能设置 /etc/default/grub
        sed -i 's/rd.lvm.lv=[^ "]*//g' /os/etc/default/grub

        # fstab 添加 efi 分区
        if is_efi; then
            # centos/oracle 要创建efi条目
            if ! grep /boot/efi /os/etc/fstab; then
                efi_part_uuid=$(lsblk /dev/$xda*1 -no UUID)
                echo "UUID=$efi_part_uuid /boot/efi vfat $efi_mount_opts 0 0" >>/os/etc/fstab
            fi
        else
            # 删除 efi 条目
            sed -i '/[[:space:]]\/boot\/efi[[:space:]]/d' /os/etc/fstab
        fi

        remove_grub_conflict_files() {
            # bios 和 efi 转换前先删除

            # bios转efi出错
            # centos 和 oracle x86_64 镜像只有 bios 镜像，/boot/grub2/grubenv 是真身
            # 安装grub-efi时，grubenv 会改成指向efi分区grubenv软连接
            # 如果安装grub-efi前没有删除原来的grubenv，原来的grubenv将不变，新建的软连接将变成 grubenv.rpmnew
            # 后续grubenv的改动无法同步到efi分区，会造成grub2-setdefault失效

            # efi转bios出错
            # 如果是指向efi目录的软连接（例如el8），先删除它，否则 grub2-install 会报错
            rm -rf /os/boot/grub2/grubenv /os/boot/grub2/grub.cfg
        }

        # 安装引导
        if is_efi; then
            # 只有centos 和 oracle x86_64 镜像没有efi，其他系统镜像已经从efi分区复制了文件
            if [ -z "$efi_part" ]; then
                remove_grub_conflict_files
                # openeuler 自带 grub2-efi-ia32，此时安装 grub2-efi 提示已经安装了 grub2-efi-ia32，不会继续安装 grub2-efi-x64
                [ "$(uname -m)" = x86_64 ] && arch=x64 || arch=aa64
                chroot_dnf install efibootmgr grub2-efi-$arch shim-$arch
            fi
        else
            # bios
            remove_grub_conflict_files
            chroot /os/ grub2-install /dev/$xda
        fi

        # blscfg 启动项
        # rocky/alma镜像是独立的boot分区，但我们不是
        # 因此要添加boot目录
        if ls /os/boot/loader/entries/*.conf 2>/dev/null &&
            ! grep -q 'initrd /boot/' /os/boot/loader/entries/*.conf; then

            sed -i -E 's,((linux|initrd) /),\1boot/,g' /os/boot/loader/entries/*.conf
        fi

        if is_efi; then
            # oracle linux 文件夹是 redhat
            # shellcheck disable=SC2010
            distro_efi=$(cd /os/boot/efi/EFI/ && ls -d -- * | grep -Eiv BOOT)
        fi

        is_grub_efi_load_config_from_os() {
            { [ "$distro" = openeuler ] && ! [ "$releasever" = 20.03 ]; } ||
                [ "$releasever" -ge 9 ]
        }

        # efi 分区 grub.cfg
        # >=34.24
        # https://github.com/rhinstaller/anaconda/blob/346b932a26a19b339e9073c049b08bdef7f166c3/pyanaconda/modules/storage/bootloader/efi.py#L198
        # https://github.com/rhinstaller/anaconda/commit/15c3b2044367d375db6739e8b8f419ef3e17cae7
        if is_efi && is_grub_efi_load_config_from_os; then
            cat <<EOF >/os/boot/efi/EFI/$distro_efi/grub.cfg
search --no-floppy --fs-uuid --set=dev $os_part_uuid
set prefix=(\$dev)/boot/grub2
export \$prefix
configfile \$prefix/grub.cfg
EOF
        fi

        # 主 grub.cfg
        if is_efi && ! is_grub_efi_load_config_from_os; then
            chroot /os/ grub2-mkconfig -o /boot/efi/EFI/$distro_efi/grub.cfg
        else
            # --update-bls-cmdline
            chroot /os/ grub2-mkconfig -o /boot/grub2/grub.cfg
        fi

        # 不删除可能网络管理器不会写入dns
        rm_resolv_conf /os
    }

    modify_ubuntu() {
        os_dir=/os

        cp_resolv_conf $os_dir

        # 关闭 os prober，因为 os prober 有时很慢
        cp $os_dir/etc/default/grub $os_dir/etc/default/grub.orig
        echo 'GRUB_DISABLE_OS_PROBER=true' >>$os_dir/etc/default/grub

        # 更改源
        if is_in_china; then
            # 22.04 使用 /etc/apt/sources.list
            # 24.04 使用 /etc/apt/sources.list.d/ubuntu.sources
            for file in $os_dir/etc/apt/sources.list $os_dir/etc/apt/sources.list.d/ubuntu.sources; do
                if [ -f $file ]; then
                    # cn.archive.ubuntu.com 不在国内还严重丢包
                    # https://www.itdog.cn/ping/cn.archive.ubuntu.com
                    sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/' $file # x64
                    sed -i 's/ports.ubuntu.com/mirrors.ustc.edu.cn/' $file   # arm
                fi
            done
        fi

        # 16.04 arm64 镜像没有 grub 引导文件
        if is_efi && ! [ -d $os_dir/boot/efi/EFI/ubuntu ]; then
            DEBIAN_FRONTEND=noninteractive chroot $os_dir \
                apt-get upgrade --reinstall -y efibootmgr shim "grub-efi-$(get_axx64)"

            cat <<EOF >"$os_dir/boot/efi/EFI/ubuntu/grub.cfg"
search.fs_uuid $os_part_uuid root
set prefix=(\$root)'/boot/grub'
configfile \$prefix/grub.cfg
EOF
        fi

        # 安装最佳内核
        flavor=$(get_ubuntu_kernel_flavor)
        echo "Use kernel flavor: $flavor"
        chroot $os_dir apt update
        DEBIAN_FRONTEND=noninteractive chroot $os_dir apt install -y "linux-image-$flavor"

        # 自带内核：
        # 常规版本             generic
        # minimal 20.04/22.04 kvm      # 后台 vnc 无显示
        # minimal 24.04       virtual

        # debian cloud 内核不支持 ahci，ubuntu virtual 支持

        # 标记旧内核包
        # 注意排除 linux-base
        if pkgs=$(chroot $os_dir apt-mark showmanual linux-* | grep -E 'generic|virtual|kvm' | grep -v $flavor); then
            chroot $os_dir apt-mark auto $pkgs

            # 使用 autoremove
            chroot_apt_autoremove $os_dir
        fi

        # 16.04 镜像用 ifupdown/networking 管理网络
        # 要安装 resolveconf，不然 /etc/resolv.conf 为空
        if [ "$releasever" = 16.04 ]; then
            chroot $os_dir apt install -y resolvconf
            ln -sf /run/resolvconf/resolv.conf $os_dir/etc/resolv.conf.orig
        fi

        # 安装 bios 引导
        if ! is_efi; then
            chroot $os_dir grub-install /dev/$xda
        fi

        # 更改 efi 目录的 grub.cfg 写死的 fsuuid
        # 因为 24.04 fsuuid 对应 boot 分区
        efi_grub_cfg=$os_dir/boot/efi/EFI/ubuntu/grub.cfg
        if is_efi; then
            os_uuid=$(lsblk -rno UUID /dev/$xda*2)
            sed -Ei "s|[0-9a-f-]{36}|$os_uuid|i" $efi_grub_cfg

            # 24.04 移除 boot 分区后，需要添加 /boot 路径
            if grep "'/grub'" $efi_grub_cfg; then
                sed -i "s|'/grub'|'/boot/grub'|" $efi_grub_cfg
            fi
        fi

        # 处理 40-force-partuuid.cfg
        force_partuuid_cfg=$os_dir/etc/default/grub.d/40-force-partuuid.cfg
        if [ -e $force_partuuid_cfg ]; then
            if is_virt; then
                # 更改写死的 partuuid
                os_part_uuid=$(lsblk -rno PARTUUID /dev/$xda*2)
                sed -i "s/^GRUB_FORCE_PARTUUID=.*/GRUB_FORCE_PARTUUID=$os_part_uuid/" $force_partuuid_cfg
            else
                # 独服不应该使用 initrdless boot
                sed -i "/^GRUB_FORCE_PARTUUID=/d" $force_partuuid_cfg
            fi
        fi

        # 要重新生成 grub.cfg，因为
        # 1 我们删除了 boot 分区
        # 2 改动了 /etc/default/grub.d/40-force-partuuid.cfg
        chroot $os_dir update-grub

        # 还原 grub 配置（os prober）
        mv $os_dir/etc/default/grub.orig $os_dir/etc/default/grub

        # fstab
        # 24.04 镜像有boot分区，但我们不需要
        sed -i '/[[:space:]]\/boot[[:space:]]/d' $os_dir/etc/fstab
        if ! is_efi; then
            # bios 删除 efi 条目
            sed -i '/[[:space:]]\/boot\/efi[[:space:]]/d' $os_dir/etc/fstab
        fi

        restore_resolv_conf $os_dir
    }

    # anolis/openeuler/opencloudos 可能要安装 cloud-init
    # opencloudos 无法使用 chroot $os_dir command -v xxx
    # chroot: failed to run command ‘command’: No such file or directory
    if is_have_cmd_on_disk $os_dir rpm &&
        ! is_have_cmd_on_disk $os_dir cloud-init; then

        cp_resolv_conf $os_dir
        chroot_dnf install cloud-init
        restore_resolv_conf $os_dir
    fi

    # cloud-init
    download_cloud_init_config $os_dir

    case "$distro" in
    ubuntu) modify_ubuntu ;;
    *) modify_el_ol ;;
    esac

    # 查看最终的 cloud-init 配置
    cat /os/etc/cloud/cloud.cfg.d/99_*.cfg

    # 删除installer分区，重启后cloud init会自动扩容
    swapoff -a
    parted /dev/$xda -s rm 3
}

dd_qcow() {
    if true; then
        connect_qcow

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
                part_end=$((part_start + part_size - 1))
                umount /mnt/btrfs
                printf "yes" | parted /dev/nbd0 resizepart $part_num ${part_end}B ---pretend-input-tty

                # 缩小 qcow2
                disconnect_qcow
                qemu-img resize --shrink $qcow_file $((part_end + 1))

                # 重新连接
                connect_qcow
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

        disconnect_qcow
    else
        # 将前1M dd到内存，将1M之后 dd到硬盘
        qemu-img dd if=$qcow_file of=/first-1M bs=1M count=1
        qemu-img dd if=$qcow_file of=/dev/disk/by-label/os bs=1M skip=1
    fi

    # 已 dd 并断开连接 qcow，可删除 qemu-img
    apk del qemu-img

    # 将前1M从内存 dd 到硬盘
    umount /installer/
    dd if=/first-1M of=/dev/$xda
    update_part /dev/$xda

}

fix_partition_table_by_parted() {
    parted /dev/$xda -f -s print
}

resize_after_install_cloud_image() {
    # 提前扩容
    # 1 修复 vultr 512m debian 11 generic/genericcloud 首次启动 kernel panic
    # 2 修复 gentoo websync 时空间不足
    if [ "$distro" = debian ] || [ "$distro" = gentoo ]; then
        apk add parted
        if fix_partition_table_by_parted 2>&1 | grep -q 'Fixing'; then
            system_part_num=$(parted /dev/$xda -m print | tail -1 | cut -d: -f1)
            printf "yes" | parted /dev/$xda resizepart $system_part_num 100% ---pretend-input-tty
            update_part /dev/$xda

            if [ "$distro" = gentoo ]; then
                apk add e2fsprogs-extra
                e2fsck -p -f /dev/$xda*$system_part_num
                resize2fs /dev/$xda*$system_part_num
            fi
            update_part /dev/$xda
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

        # 有 ipv6 但需设置 dns 的情况
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

# virt-what 要用最新版
# vultr 1G High Frequency LAX 实际上是 kvm
# debian 11 virt-what 1.19 显示为 hyperv qemu
# debian 11 systemd-detect-virt 显示为 microsoft
# alpine virt-what 1.25 显示为 kvm
# 所以不要在原系统上判断具体虚拟化环境

# lscpu 也可查看虚拟化环境，但 alpine on lightsail 运行结果为 Microsoft
# 猜测 lscpu 只参考了 cpuid 没参考 dmi
# virt-what 可能会输出多行结果，因此用 grep
is_virt_contains() {
    if [ -z "$_virt" ]; then
        apk add virt-what
        _virt=$(virt-what)
        apk del virt-what
    fi
    echo "$_virt" | grep -Eiw "$1"
}

is_dmi_contains() {
    if [ -z "$_dmi" ]; then
        apk add dmidecode
        _dmi=$(dmidecode)
        apk del dmidecode
    fi
    echo "$_dmi" | grep -Eiw "$1"
}

get_aws_repo() {
    if is_in_china >&2; then
        echo https://s3.cn-north-1.amazonaws.com.cn/ec2-windows-drivers-downloads-cn
    else
        echo https://s3.amazonaws.com/ec2-windows-drivers-downloads
    fi
}

get_client_name_by_build_ver() {
    build_ver=$1

    if [ "$build_ver" -ge 22000 ]; then
        echo 11
    elif [ "$build_ver" -ge 10240 ]; then
        echo 10
    elif [ "$build_ver" -ge 9600 ]; then
        echo 8.1
    elif [ "$build_ver" -ge 9200 ]; then
        echo 8
    elif [ "$build_ver" -ge 7600 ]; then
        echo 7
    elif [ "$build_ver" -ge 6000 ]; then
        echo vista
    else
        error_and_exit "Unknown Build Version: $build_ver"
    fi
}

# 将 AC/SAC 版本号 转换为 LTSC 版本号
# 用于查找驱动
get_server_name_by_build_ver() {
    build_ver=$1

    if [ "$build_ver" -ge 26100 ]; then
        echo 2025
    elif [ "$build_ver" -ge 20348 ]; then
        echo 2022
    elif [ "$build_ver" -ge 17763 ]; then
        echo 2019
    elif [ "$build_ver" -ge 14393 ]; then
        echo 2016
    elif [ "$build_ver" -ge 9600 ]; then
        echo 2012 r2
    elif [ "$build_ver" -ge 9200 ]; then
        echo 2012
    elif [ "$build_ver" -ge 7600 ]; then
        echo 2008 r2
    elif [ "$build_ver" -ge 6000 ]; then
        echo 2008
    else
        error_and_exit "Unknown Build Version: $build_ver"
    fi
}

install_windows() {
    apk add wimlib

    download $iso /os/windows.iso
    mkdir -p /iso
    mount -o ro /os/windows.iso /iso

    # 复制 boot.wim 到 /os，用于临时编辑
    cp /iso/sources/boot.wim /os/boot.wim

    # 从iso复制文件
    # 复制iso全部文件(除了boot.wim)到installer分区
    # efi: 额外复制boot开头的文件+efi目录到efi分区，
    if is_efi; then
        cp -rv /iso/boot* /os/boot/efi/
        cp -rv /iso/efi/ /os/boot/efi/
    fi

    echo 'Copying installer files...'
    if false; then
        rsync -rv --exclude=/sources/boot.wim /iso/* /os/installer/
    else
        (
            cd /iso
            find . -type f -not -name boot.wim -exec cp -r --parents {} /os/installer/ \;
        )
    fi

    if [ -e /os/installer/sources/install.esd ]; then
        install_wim=/os/installer/sources/install.esd
    else
        install_wim=/os/installer/sources/install.wim
    fi

    # 匹配映像版本
    # 需要整行匹配，因为要区分 Windows 10 Pro 和 Windows 10 Pro for Workstations
    image_count=$(wiminfo $install_wim | grep "^Image Count:" | cut -d: -f2 | xargs)
    all_image_names=$(wiminfo $install_wim | grep ^Name: | sed 's/^Name: *//')

    if [ "$image_count" = 1 ]; then
        # 只有一个版本就用那个版本
        image_name=$all_image_names
    else
        while true; do
            # 匹配成功
            # 改成正确的大小写
            if matched_image_name=$(echo "$all_image_names" | grep -ix "$image_name"); then
                image_name=$matched_image_name
                break
            fi

            # 匹配失败
            file=/image-name
            error "Invalid image name: $image_name"
            echo "Choose a correct image name by one of follow command to continue:"
            while read -r line; do
                echo "  echo '$line' >$file"
            done < <(echo "$all_image_names")

            # sleep 直到有输入
            true >$file
            while ! { [ -s $file ] && image_name=$(cat $file) && [ -n "$image_name" ]; }; do
                sleep 1
            done
        done
    fi
    echo "Image Name: $image_name"

    get_selected_image_prop() {
        property=$1
        wiminfo "$install_wim" "$image_name" | grep -i "^$property:" | cut -d: -f2- | xargs
    }

    # PRODUCTTYPE:
    # - WinNT    (普通 windows)
    # - ServerNT (windows server)

    # INSTALLATIONTYPE:
    # - Client      (普通 windows)
    # - Server      (windows server 带桌面体验)
    # - Server Core (windows server 不带桌面体验)

    # 用内核版本号筛选驱动
    # 使得可以安装 Hyper-V Server / Azure Stack HCI 等 Windows Server 变种
    nt_ver=$(get_selected_image_prop "Major Version").$(get_selected_image_prop "Minor Version")
    build_ver=$(get_selected_image_prop "Build")
    product_type=$(get_selected_image_prop "Product Type")

    product_ver=$(
        case $product_type in
        WinNT) get_client_name_by_build_ver "$build_ver" ;;
        ServerNT) get_server_name_by_build_ver "$build_ver" ;;
        esac
    )

    echo "NT Version: $nt_ver"
    echo "Build Version: $build_ver"
    echo "Product Type: $product_type"
    echo "Product Version: $product_ver"

    # win11 要求 1GHz 2核（1核超线程也行）
    # 用注册表无法绕过
    # https://github.com/pbatard/rufus/issues/1990
    # https://learn.microsoft.com/windows/iot/iot-enterprise/Hardware/System_Requirements
    if [ "$product_ver" = "11" ]; then
        if [ "$(grep -c '^processor' /proc/cpuinfo)" -le 1 ]; then
            wiminfo "$install_wim" "$image_name" --image-property WINDOWS/INSTALLATIONTYPE=Server
        fi
    fi

    # 变量名     使用场景
    # arch_uname arch命令 / uname -m             x86_64  aarch64
    # arch_wim   wiminfo                    x86  x86_64  ARM64
    # arch       virtio iso / unattend.xml  x86  amd64   arm64
    # arch_xdd   virtio msi / xen驱动       x86  x64

    # 将 wim 的 arch 转为驱动和应答文件的 arch
    arch_wim=$(get_selected_image_prop Architecture | to_lower)
    case "$arch_wim" in
    x86)
        arch=x86
        arch_xdd=x86
        ;;
    x86_64)
        arch=amd64
        arch_xdd=x64
        ;;
    arm64)
        arch=arm64
        arch_xdd= # xen 没有 arm64 驱动，# virtio 也没有 arm64 msi
        ;;
    esac

    # 驱动
    drv=/os/drivers
    mkdir -p $drv

    # aws nitro
    # 不支持 vista
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/aws-nvme-drivers.html
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/enhanced-networking-ena.html
    if is_virt_contains aws &&
        is_virt_contains kvm &&
        { [ "$arch_wim" = x86_64 ] || [ "$arch_wim" = arm64 ]; } &&
        ! [ "$nt_ver" = 6.0 ]; then

        # 未打补丁的 win7 无法使用 sha256 签名的驱动
        nvme_ver=$(
            case "$nt_ver" in
            6.1) echo 1.3.2 ;; # sha1 签名
            *) echo Latest ;;
            esac
        )

        ena_ver=$(
            case "$nt_ver" in
            6.1) echo 2.1.4 ;; # sha1 签名
            # 6.1) echo 2.2.3 ;; # sha256 签名
            6.2 | 6.3) echo 2.6.0 ;;
            *) echo Latest ;;
            esac
        )

        [ "$arch_wim" = arm64 ] && arch_dir=/ARM64 || arch_dir=

        download "$(get_aws_repo)/NVMe$arch_dir/$nvme_ver/AWSNVMe.zip" $drv/AWSNVMe.zip
        download "$(get_aws_repo)/ENA$arch_dir/$ena_ver/AwsEnaNetworkDriver.zip" $drv/AwsEnaNetworkDriver.zip

        unzip -o -d $drv/aws/ $drv/AWSNVMe.zip
        unzip -o -d $drv/aws/ $drv/AwsEnaNetworkDriver.zip
    fi

    # citrix xen
    # 仅支持 vista
    if is_virt_contains xen &&
        { [ "$arch_wim" = x86 ] || [ "$arch_wim" = x86_64 ]; } &&
        [ "$nt_ver" = 6.0 ]; then

        apk add 7zip
        download https://s3.amazonaws.com/ec2-downloads-windows/Drivers/Citrix-Win_PV.zip $drv/Citrix-Win_PV.zip
        unzip -o -d $drv $drv/Citrix-Win_PV.zip
        case "$arch_wim" in
        x86) override=s ;;    # skip
        x86_64) override=a ;; # always
        esac
        # 排除 $PLUGINSDIR $TEMP
        exclude='$*'
        7z x $drv/Citrix_xensetup.exe -o$drv/aws/ -ao$override -x!$exclude
    fi

    # aws xen
    # 不支持 vista
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/xen-drivers-overview.html
    if is_virt_contains xen &&
        [ "$arch_wim" = x86_64 ] &&
        ! [ "$nt_ver" = 6.0 ]; then

        apk add msitools

        aws_pv_ver=$(
            case "$nt_ver" in
            6.1) echo 8.3.2 ;; # sha1 签名
            # 6.1) echo 8.3.5 ;; # sha256 签名
            *) echo Latest ;;
            esac
        )

        download "$(get_aws_repo)/AWSPV/$aws_pv_ver/AWSPVDriver.zip" $drv/AWSPVDriver.zip

        unzip -o -d $drv $drv/AWSPVDriver.zip
        msiextract $drv/AWSPVDriverSetup.msi -C $drv
        mkdir -p $drv/aws/
        cp -rf $drv/.Drivers/* $drv/aws/
    fi

    # xen
    # 没签名，暂时用aws的驱动代替
    # https://lore.kernel.org/xen-devel/E1qKMmq-00035B-SS@xenbits.xenproject.org/
    # https://xenbits.xenproject.org/pvdrivers/win/
    # 在 aws t2 上测试，安装 xenbus 会蓝屏，装了其他7个驱动后，能进系统但没网络
    # 但 aws 应该用aws官方xen驱动，所以测试仅供参考
    if false &&
        is_virt_contains xen &&
        { [ "$arch_wim" = x86 ] || [ "$arch_wim" = x86_64 ]; }; then

        parts='xenbus xencons xenhid xeniface xennet xenvbd xenvif xenvkbd'
        mkdir -p $drv/xen/
        for part in $parts; do
            download https://xenbits.xenproject.org/pvdrivers/win/$part.tar $drv/$part.tar
            tar -xf $drv/$part.tar -C $drv/xen/
        done
    fi

    # kvm (排除 aws)
    # x86 x86_64 arm64 都有
    # https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/
    if is_virt_contains kvm &&
        ! is_virt_contains aws; then

        # 要区分 win10 / win11 驱动，虽然他们的 NT 版本号都是 10.0
        # 但他们可能用不同的编译器编译
        # 未来 inf 也有可能不同
        # https://github.com/virtio-win/kvm-guest-drivers-windows/commit/9af43da9e16e2d4bf4ea4663cdc4f29275fff48f
        # vista >>> 2k8
        # 10 >>> w10
        # 2012 r2 >>> 2k12R2
        virtio_sys=$(
            case "$(echo "$product_ver" | to_lower)" in
            'vista') echo 2k8 ;; # 没有 vista 文件夹
            '2025') echo 2k22 ;; # 暂时没有
            *)
                case "$product_type" in
                WinNT) echo "w$product_ver" ;;
                ServerNT) echo "$product_ver" | sed -E -e 's/ //' -e 's/^200?/2k/' -e 's/r2/R2/' ;;
                esac
                ;;
            esac
        )

        # https://github.com/virtio-win/virtio-win-pkg-scripts/issues/40
        # https://github.com/virtio-win/virtio-win-pkg-scripts/issues/61
        case "$nt_ver" in
        6.0 | 6.1) dir=archive-virtio/virtio-win-0.1.173-9 ;; # vista|w7|2k8|2k8R2
        6.2 | 6.3) dir=archive-virtio/virtio-win-0.1.215-1 ;; # w8|w8.1|2k12|2k12R2
        *) dir=stable-virtio ;;
        esac

        # vista|w7|2k8|2k8R2|arm64 要从 iso 获取驱动
        if [ "$nt_ver" = 6.0 ] || [ "$nt_ver" = 6.1 ] || [ "$arch_wim" = arm64 ]; then
            virtio_source=iso
        else
            virtio_source=msi
        fi

        baseurl=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads

        if [ "$virtio_source" = iso ]; then
            download $baseurl/$dir/virtio-win.iso $drv/virtio.iso
            mkdir -p $drv/virtio
            mount -o ro $drv/virtio.iso $drv/virtio
        else
            # coreutils 的 cp mv rm 才有 -v 参数
            apk add 7zip file coreutils
            download $baseurl/$dir/virtio-win-gt-$arch_xdd.msi $drv/virtio.msi
            match="FILE_*_${virtio_sys}_${arch}*"
            7z x $drv/virtio.msi -o$drv/virtio -i!$match -y -bb1

            (
                cd $drv/virtio
                # 为没有后缀名的文件添加后缀名
                echo "Recognizing file extension..."
                for file in *"${virtio_sys}_${arch}"; do
                    recognized=false
                    maybe_exts=$(file -b --extension "$file")

                    # exe/sys -> sys
                    # exe/com -> exe
                    # dll/cpl/tlb/ocx/acm/ax/ime -> dll
                    for ext in sys exe dll; do
                        if echo $maybe_exts | grep -qw $ext; then
                            recognized=true
                            mv -v "$file" "$file.$ext"
                            break
                        fi
                    done

                    # 如果识别不了后缀名，就删除此文件
                    # 因为用不了，免得占用空间
                    if ! $recognized; then
                        rm -fv "$file"
                    fi
                done

                # 将
                # FILE_netkvm_netkvmco_w8.1_amd64.dll
                # FILE_netkvm_w8.1_amd64.cat
                # 改名为
                # netkvmco.dll
                # netkvm.cat
                echo "Renaming files..."
                for file in *; do
                    new_file=$(echo "$file" | sed "s|FILE_||; s|_${virtio_sys}_${arch}||; s|.*_||")
                    mv -v "$file" "$new_file"
                done
            )
        fi
    fi

    # gcp
    # x86 x86_64 arm64 都有
    if { is_dmi_contains "Google Compute Engine" || is_dmi_contains "GoogleCloud"; }; then

        gce_repo=https://packages.cloud.google.com/yuck
        download $gce_repo/repos/google-compute-engine-stable/index /tmp/gce.json
        for name in gvnic gga; do
            # gvnic 没有 arm64
            if [ "$name" = gvnic ] && [ "$arch_wim" = arm64 ]; then
                continue
            fi

            mkdir -p $drv/gce/$name
            link=$(grep -o "/pool/.*-google-compute-engine-driver-$name.*\.goo" /tmp/gce.json)
            wget $gce_repo$link -O- | tar -xzf- -C $drv/gce/$name

            # 没有 win6.0 文件夹
            # 但 inf 没限制
            # TODO: 测试是否可用
            if false; then
                for suffix in '' '-32'; do
                    if [ -d "$drv/gce/$name/win6.1$suffix" ]; then
                        cp -r "$drv/gce/$name/win6.1$suffix" "$drv/gce/$name/win6.0$suffix"
                    fi
                done
            fi
        done
    fi

    # azure
    # https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-windows
    if is_dmi_contains "7783-7084-3265-9085-8269-3286-77" &&
        { [ "$arch_wim" = x86 ] || [ "$arch_wim" = x86_64 ]; }; then

        download https://aka.ms/manawindowsdrivers $drv/azure.zip
        unzip $drv/azure.zip -d $drv/azure/
    fi

    # 修改应答文件
    download $confhome/windows.xml /tmp/autounattend.xml
    locale=$(get_selected_image_prop 'Default Language')
    sed -i "s|%arch%|$arch|; s|%image_name%|$image_name|; s|%locale%|$locale|; s|%password%|$PASSWORD|" \
        /tmp/autounattend.xml

    # 修改应答文件，分区配置
    if is_efi; then
        sed -i "s|%installto_partitionid%|3|" /tmp/autounattend.xml
    else
        sed -i "s|%installto_partitionid%|1|" /tmp/autounattend.xml
    fi

    # vista/2008 有这行安装会报错
    if [ "$nt_ver" = 6.0 ]; then
        sed -i "/EnableFirewall/d" /tmp/autounattend.xml
    fi

    # 2012 r2，删除 key 字段，报错 Windows cannot read the <ProductKey> setting from the unattend answer file，即使创建 ei.cfg
    # ltsc 2021，有 ei.cfg，填空白 key 正常
    # ltsc 2021 n，有 ei.cfg，填空白 key 报错 Windows Cannot find Microsoft software license terms
    # 评估版 iso ei.cfg 有 EVAL 字样，填空白 key 报错 Windows Cannot find Microsoft software license terms

    # key
    if [[ "$image_name" = 'Windows Vista'* ]]; then
        # vista 需密钥，密钥可与 edition 不一致
        # TODO: 改成从网页获取？
        # https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys
        key=VKK3X-68KWM-X2YGT-QR4M6-4BWMV
        sed -i "s/%key%/$key/" /tmp/autounattend.xml
    else
        # shellcheck disable=SC2010
        if ls -d /os/installer/sources/* | grep -iq ei.cfg; then
            # 镜像有 ei.cfg，删除 key 字段
            sed -i "/%key%/d" /tmp/autounattend.xml
        else
            # 镜像无 ei.cfg，填空白 key
            sed -i "s/%key%//" /tmp/autounattend.xml
        fi
    fi

    # 挂载 boot.wim
    mkdir -p /wim
    wimmountrw /os/boot.wim 2 /wim/

    cp_drivers() {
        src=$1
        shift

        find $src \
            -type f \
            -not -iname "*.pdb" \
            -not -iname "dpinst.exe" \
            "$@" \
            -exec cp -rfv {} /wim/drivers \;
    }

    # 添加驱动
    mkdir -p /wim/drivers
    [ -d $drv/virtio ] && {
        if [ "$virtio_source" = iso ]; then
            # iso
            if [ "$nt_ver" = 6.0 ]; then
                # win7 气球驱动有问题
                cp_drivers $drv/virtio -ipath "*/$virtio_sys/$arch/*" -not -ipath "*/balloon/*"
            else
                cp_drivers $drv/virtio -ipath "*/$virtio_sys/$arch/*"
            fi
        else
            # msi
            # 虽然 win7 气球驱动有问题，但 msi 里面没有 win7 驱动
            # 因此不用额外处理
            cp_drivers $drv/virtio
        fi
    }
    [ -d $drv/aws ] && cp_drivers $drv/aws
    [ -d $drv/xen ] && cp_drivers $drv/xen -ipath "*/$arch_xdd/*"
    [ -d $drv/azure ] && cp_drivers $drv/azure
    [ -d $drv/gce ] && {
        [ "$arch_wim" = x86 ] && gvnic_suffix=-32 || gvnic_suffix=
        cp_drivers $drv/gce/gvnic -ipath "*/win$nt_ver$gvnic_suffix/*"
        cp_drivers $drv/gce/gga -ipath "*/win$nt_ver/*"
    }

    # win7 要添加 bootx64.efi 到 efi 目录
    [ $arch = amd64 ] && boot_efi=bootx64.efi || boot_efi=bootaa64.efi
    if is_efi && [ ! -e /os/boot/efi/efi/boot/$boot_efi ]; then
        mkdir -p /os/boot/efi/efi/boot/
        cp /wim/Windows/Boot/EFI/bootmgfw.efi /os/boot/efi/efi/boot/$boot_efi
    fi

    # 复制应答文件
    # 移除注释，否则 windows-setup.bat 重新生成的 autounattend.xml 有问题
    apk add xmlstarlet
    xmlstarlet ed -d '//comment()' /tmp/autounattend.xml >/wim/autounattend.xml
    apk del xmlstarlet
    unix2dos /wim/autounattend.xml
    cat /wim/autounattend.xml

    # 复制安装脚本
    # https://slightlyovercomplicated.com/2016/11/07/windows-pe-startup-sequence-explained/
    mv /wim/setup.exe /wim/setup.exe.disabled

    # 如果有重复的 Windows/System32 文件夹，会提示找不到 winload.exe 无法引导
    # win7 win10 是 Windows/System32
    # win2016    是 windows/system32
    # shellcheck disable=SC2010
    system32_dir=$(ls -d /wim/*/*32 | grep -i windows/system32)
    download $confhome/windows-setup.bat $system32_dir/startnet.cmd

    # 提交修改 boot.wim
    wimunmount --commit /wim/

    # 优化 boot.wim 大小
    # vista 删除镜像1 会报错
    # Windows cannot access the required file Drive:\Sources\Boot.wim.
    # Make sure all files required for installation are available and restart the installation.
    # Error code: 0x80070491
    du -h /iso/sources/boot.wim
    du -h /os/boot.wim
    # wimdelete /os/boot.wim 1
    wimoptimize /os/boot.wim
    du -h /os/boot.wim

    # 将 boot.wim 放到正确的位置
    if is_efi; then
        mkdir -p /os/boot/efi/sources/
        cp /os/boot.wim /os/boot/efi/sources/boot.wim
    else
        cp /os/boot.wim /os/installer/sources/boot.wim
    fi

    # windows 7 没有 invoke-webrequest
    # installer分区盘符不一定是D盘
    # 所以复制 resize.bat 到 install.wim
    # TODO: 由于esd文件无法修改，要将resize.bat放到boot.wim
    if [[ "$install_wim" = '*.wim' ]]; then
        wimmountrw $install_wim "$image_name" /wim/
        if false; then
            # 使用 autounattend.xml
            # win7 在此阶段找不到网卡
            download $confhome/windows-resize.bat /wim/windows-resize.bat
            for ethx in $(get_eths); do
                create_win_set_netconf_script /wim/windows-set-netconf-$ethx.bat
            done
        else
            modify_windows /wim
        fi
        wimunmount --commit /wim/
    fi

    # 添加引导
    if is_efi; then
        apk add efibootmgr
        efibootmgr -c -L "Windows Installer" -d /dev/$xda -p1 -l "\\EFI\\boot\\$boot_efi"
    else
        # 或者用 ms-sys
        apk add grub-bios
        # efi 下，强制安装 mbr 引导，需要添加 --target i386-pc
        grub-install --target i386-pc --boot-directory=/os/boot /dev/$xda
        cat <<EOF >/os/boot/grub/grub.cfg
            set timeout=5
            menuentry "reinstall" {
                search --no-floppy --label --set=root installer
                ntldr /bootmgr
            }
EOF
    fi
}

# 添加 netboot.efi 备用
download_netboot_xyz_efi() {
    dir=$1

    file=$dir/netboot.xyz.efi
    if [ "$(uname -m)" = aarch64 ]; then
        download https://boot.netboot.xyz/ipxe/netboot.xyz-arm64.efi $file
    else
        download https://boot.netboot.xyz/ipxe/netboot.xyz.efi $file
    fi
}

refind_main_disk() {
    if true; then
        apk add sfdisk
        main_disk=$(sfdisk --disk-id /dev/$xda | sed 's/0x//')
    else
        apk add lsblk
        # main_disk=$(blkid --match-tag PTUUID -o value /dev/$xda)
        main_disk=$(lsblk --nodeps -rno PTUUID /dev/$xda)
    fi
}

get_ubuntu_kernel_flavor() {
    # 20.04/22.04 kvm 内核 vnc 没显示
    # 24.04 kvm = virtual
    # linux-image-virtual = linux-image-6.x-generic
    # linux-image-generic = linux-image-6.x-generic + amd64-microcode + intel-microcode + linux-firmware + linux-modules-extra-generic
    # https://github.com/systemd/systemd/blob/main/src/basic/virt.c
    # https://github.com/canonical/cloud-init/blob/main/tools/ds-identify
    # http://git.annexia.org/?p=virt-what.git;a=blob;f=virt-what.in;hb=HEAD
    {
        # busybox blkid 不显示 sr0 的 UUID
        if [ "$releasever" = 16.04 ]; then
            if is_virt; then
                flavor=virtual-hwe-$releasever
            else
                flavor=generic-hwe-$releasever
            fi
        else
            apk add lsblk

            if is_dmi_contains "amazon" || is_dmi_contains "ec2"; then
                flavor=aws
            elif is_dmi_contains "Google Compute Engine" || is_dmi_contains "GoogleCloud"; then
                flavor=gcp
            elif is_dmi_contains "OracleCloud"; then
                flavor=oracle
            elif is_dmi_contains "7783-7084-3265-9085-8269-3286-77"; then
                flavor=azure
            elif lsblk -o UUID,LABEL | grep -i 9796-932E | grep -i config-2; then
                flavor=ibm
            elif is_virt; then
                flavor=virtual-hwe-$releasever
            else
                flavor=generic-hwe-$releasever
            fi
        fi
    } >&2
    echo $flavor
}

install_redhat_ubuntu() {
    # 安装 grub2
    if is_efi; then
        # 注意低版本的grub无法启动f38 arm的内核
        # https://forums.fedoraforum.org/showthread.php?330104-aarch64-pxeboot-vmlinuz-file-format-changed-broke-PXE-installs
        apk add grub-efi efibootmgr
        grub-install --efi-directory=/os/boot/efi --boot-directory=/os/boot
    else
        apk add grub-bios
        grub-install --boot-directory=/os/boot /dev/$xda
    fi

    # 重新整理 extra，因为grub会处理掉引号，要重新添加引号
    extra_cmdline=''
    for var in $(grep -o '\bextra_[^ ]*' /proc/cmdline | xargs); do
        if [[ "$var" = "extra_main_disk="* ]]; then
            # 重新记录主硬盘
            refind_main_disk
            extra_cmdline="$extra_cmdline extra_main_disk=$main_disk"
        else
            extra_cmdline="$extra_cmdline $(echo $var | sed -E "s/(extra_[^=]*)=(.*)/\1='\2'/")"
        fi
    done

    # 安装红帽系时，只有最后一个有安装界面显示
    # https://anaconda-installer.readthedocs.io/en/latest/boot-options.html#console
    console_cmdline=$(get_ttys console=)
    grub_cfg=/os/boot/grub/grub.cfg

    # 新版grub不区分linux/linuxefi
    # shellcheck disable=SC2154
    if [ "$distro" = "ubuntu" ]; then
        download $iso /os/installer/ubuntu.iso

        kernel=$(get_ubuntu_kernel_flavor)

        # 正常写法应该是 ds="nocloud-net;s=https://xxx/" 但是甲骨文云的ds更优先，自己的ds根本无访问记录
        # $seed 是 https://xxx/
        cat <<EOF >$grub_cfg
        set timeout=5
        menuentry "reinstall" {
            # https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/1851311
            # rmmod tpm
            insmod all_video
            search --no-floppy --label --set=root installer
            loopback loop /ubuntu.iso
            linux (loop)/casper/vmlinuz iso-scan/filename=/ubuntu.iso autoinstall noprompt noeject cloud-config-url=$ks $extra_cmdline extra_kernel=$kernel --- $console_cmdline
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
            insmod all_video
            search --no-floppy --label --set=root os
            linux /vmlinuz inst.stage2=hd:LABEL=installer:/install.img inst.ks=$ks $extra_cmdline $console_cmdline
            initrd /initrd.img
        }
EOF
    fi

    cat "$grub_cfg"
}

# 脚本入口
# debian initrd 会寻找 main
# 并调用本文件的 create_ifupdown_config 方法
: main

# 允许 ramdisk 使用所有内存，默认是 50%
mount / -o remount,size=100%

# arm要手动从硬件同步时间，避免访问https出错
# do 机器第二次运行会报错
hwclock -s || true

# 设置密码，安装并打开 ssh
echo "root:$PASSWORD" | chpasswd
printf '\nyes' | setup-sshd

extract_env_from_cmdline
# shellcheck disable=SC2154
if [ "$hold" = 1 ]; then
    exit
fi

mod_motd
setup_tty_and_log
cat /proc/cmdline
clear_previous
add_community_repo

# 需要在重新分区之前，找到主硬盘
# 重新运行脚本时，可指定 xda
# xda=sda ash trans.start
if [ -z "$xda" ]; then
    find_xda
fi

if [ "$distro" != "alpine" ]; then
    setup_nginx_if_enough_ram
    setup_udev_util_linux
fi

# dd qemu 切换成云镜像模式，暂时没用到
if [ "$distro" = "dd" ] && [ "$img_type" = "qemu" ]; then
    # 移到 reinstall.sh ?
    distro=any
    cloud_image=1
fi

if is_use_cloud_image; then
    case "$img_type" in
    qemu)
        create_part
        download_qcow
        case "$distro" in
        centos | alma | rocky | oracle | redhat | anolis | opencloudos | openeuler)
            # 这几个系统云镜像系统盘是8~9g xfs，而我们的目标是能在5g硬盘上运行，因此改成复制系统文件
            install_qcow_by_copy
            ;;
        ubuntu)
            # 24.04 云镜像有 boot 分区（在系统分区之前），因此不直接 dd 云镜像
            install_qcow_by_copy
            ;;
        *)
            # debian fedora opensuse arch gentoo any
            dd_qcow
            resize_after_install_cloud_image
            modify_os_on_disk linux
            ;;
        esac
        ;;
    gzip | xz)
        # 暂时没用到 gzip xz 格式的云镜像
        dd_gzip_xz
        resize_after_install_cloud_image
        modify_os_on_disk linux
        ;;
    esac
elif [ "$distro" = "dd" ]; then
    case "$img_type" in
    gzip | xz)
        dd_gzip_xz
        modify_os_on_disk windows
        ;;
    qemu) # dd qemu 不可能到这里，因为上面已处理
        ;;
    esac
else
    # 安装模式
    case "$distro" in
    alpine)
        install_alpine
        ;;
    arch | gentoo)
        create_part
        install_arch_gentoo
        ;;
    *)
        create_part
        mount_part_for_install_mode
        case "$distro" in
        centos | alma | rocky | fedora | ubuntu | redhat) install_redhat_ubuntu ;;
        windows) install_windows ;;
        esac
        ;;
    esac
fi

# 需要用到 lsblk efibootmgr ，只要 1M 左右容量
# 因此 alpine 不单独处理
if is_efi; then
    del_invalid_efi_entry
    add_fallback_efi_to_nvram
fi

sync
echo 'done'
if [ "$hold" = 2 ]; then
    exit
fi

cd /
# 让 web 输出全部内容
sleep 5
reboot

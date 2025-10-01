#!/bin/ash
# shellcheck shell=dash
# shellcheck disable=SC2086,SC3047,SC3036,SC3010,SC3001,SC3060
# alpine 默认使用 busybox ash
# 注意 bash 和 ash 以下语句结果不同
# [[ a = '*a' ]] && echo 1

# 出错后停止运行，将进入到登录界面，防止失联
set -eE

# 用于判断 reinstall.sh 和 trans.sh 是否兼容
# shellcheck disable=SC2034
SCRIPT_VERSION=4BACD833-A585-23BA-6CBB-9AA4E08E0003

TRUE=0
FALSE=1
EFI_UUID=C12A7328-F81F-11D2-BA4B-00A0C93EC93B

error() {
    color='\e[31m'
    plain='\e[0m'
    echo -e "${color}***** ERROR *****${plain}" >&2
    echo -e "${color}$*${plain}" >&2
}

info() {
    color='\e[32m'
    plain='\e[0m'
    local msg

    if [ "$1" = false ]; then
        shift
        msg=$*
    else
        msg=$(echo "$*" | to_upper)
    fi

    echo -e "${color}***** $msg *****${plain}" >&2
}

warn() {
    color='\e[33m'
    plain='\e[0m'
    echo -e "${color}Warning: $*${plain}" >&2
}

error_and_exit() {
    error "$@"
    echo "Run '/trans.sh' to retry." >&2
    echo "Run '/trans.sh alpine' to install Alpine Linux instead." >&2
    exit 1
}

trap_err() {
    line_no=$1
    ret_no=$2

    error_and_exit "$(
        echo "Line $line_no return $ret_no"
        if [ -f "/trans.sh" ]; then
            sed -n "$line_no"p /trans.sh
        fi
    )"
}

is_run_from_locald() {
    [[ "$0" = "/etc/local.d/*" ]]
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
    retry 5 command apk "$@" >&2
}

# 在没有设置 set +o pipefail 的情况下，限制下载大小：
# retry 5 command wget | head -c 1048576 会触发 retry，下载 5 次
# command wget "$@" --tries=5 | head -c 1048576 不会触发 wget 自带的 retry，只下载 1 次
wget() {
    echo "$@" | grep -o 'http[^ ]*' >&2
    if command wget 2>&1 | grep -q BusyBox; then
        # busybox wget 没有重试功能
        # 好像默认永不超时
        retry 5 command wget "$@" -T 10
    else
        # 原版 wget 自带重试功能
        command wget --tries=5 --progress=bar:force "$@"
    fi
}

is_have_cmd() {
    # command -v 包括脚本里面的方法
    is_have_cmd_on_disk / "$1"
}

is_have_cmd_on_disk() {
    local os_dir=$1
    local cmd=$2

    for bin_dir in /bin /sbin /usr/bin /usr/sbin; do
        if [ -f "$os_dir$bin_dir/$cmd" ]; then
            return
        fi
    done
    return 1
}

is_num() {
    echo "$1" | grep -Exq '[0-9]*\.?[0-9]*'
}

retry() {
    local max_try=$1
    shift

    if is_num "$1"; then
        local interval=$1
        shift
    else
        local interval=5
    fi

    for i in $(seq $max_try); do
        if "$@"; then
            return
        else
            ret=$?
            if [ $i -ge $max_try ]; then
                return $ret
            fi
            sleep $interval
        fi
    done
}

get_url_type() {
    if [[ "$1" = magnet:* ]]; then
        echo bt
    else
        echo http
    fi
}

is_magnet_link() {
    [[ "$1" = magnet:* ]]
}

download() {
    url=$1
    path=$2

    # 有ipv4地址无ipv4网关的情况下，aria2可能会用ipv4下载，而不是ipv6
    # axel 在 lightsail 上会占用大量cpu
    # https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2
    # https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-o

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
    # --retry-wait 5

    # 检测大小时已经下载了种子
    if [ "$(get_url_type "$url")" = bt ]; then
        torrent="$(get_torrent_path_by_magnet $url)"
        if ! [ -f "$torrent" ]; then
            download_torrent_by_magnet "$url" "$torrent"
        fi
        url=$torrent
    fi

    # intel 禁止了 aria2 下载
    # 腾讯云 virtio 驱动也禁止了 aria2 下载

    # -o 设置 http 下载文件名
    # -O 设置 bt 首个文件的文件名
    aria2c "$url" \
        -d "$(dirname "$path")" \
        -o "$(basename "$path")" \
        -O "1=$(basename "$path")" \
        -U Wget/1.25.0

    # opensuse 官方镜像支持 metalink
    # aira2 无法重命名用 metalink 下载的文件
    # 需用以下方法重命名
    if head -c 1024 "$path" | grep -Fq 'urn:ietf:params:xml:ns:metalink'; then
        real_file=$(tr -d '\n' <"$path" | sed -E 's|.*<file[[:space:]]+name="([^"]*)".*|\1|')
        mv "$(dirname "$path")/$real_file" "$path"
    fi
}

update_part() {
    sleep 1
    sync

    # partprobe
    # 有分区挂载中会报 Resource busy 错误
    if is_have_cmd partprobe; then
        partprobe /dev/$xda 2>/dev/null || true
    fi

    # partx
    # https://access.redhat.com/solutions/199573
    if is_have_cmd partx; then
        partx -u /dev/$xda
    fi

    # mdev
    # mdev 不会删除 /dev/disk/ 的旧分区，因此手动删除
    # 如果 rm -rf 的时候刚好 mdev 在创建链接，rm -rf 会报错 Directory not empty
    # 因此要先停止 mdev 服务
    # 还要删除 /dev/$xda*?
    ensure_service_stopped mdev
    # 即使停止了 mdev，有时也会报 Directory not empty，因此添加 retry
    retry 5 rm -rf /dev/disk/*

    # 没挂载 modloop 时会提示
    # modprobe: can't change directory to '/lib/modules': No such file or directory
    # 因此强制不显示上面的提示
    mdev -sf 2>/dev/null
    ensure_service_started mdev 2>/dev/null
    sleep 1
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

is_allow_ping() {
    [ -n "$allow_ping" ] && [ "$allow_ping" = 1 ]
}

setup_nginx() {
    apk add nginx
    # shellcheck disable=SC2154
    wget $confhome/logviewer.html -O /logviewer.html
    wget $confhome/logviewer-nginx.conf -O /etc/nginx/http.d/default.conf

    if [ -z "$web_port" ]; then
        web_port=80
    fi
    sed -i "s/@WEB_PORT@/$web_port/gi" /etc/nginx/http.d/default.conf

    # rc-service -q nginx start
    if pgrep nginx >/dev/null; then
        nginx -s reload
    else
        nginx
    fi
}

setup_websocketd() {
    apk add websocketd
    wget $confhome/logviewer.html -O /tmp/index.html
    apk add coreutils

    if [ -z "$web_port" ]; then
        web_port=80
    fi

    pkill websocketd || true
    # websocketd 遇到 \n 才推送，因此要转换 \r 为 \n
    websocketd --port "$web_port" --loglevel=fatal --staticdir=/tmp \
        stdbuf -oL -eL sh -c "tail -fn+0 /reinstall.log | tr '\r' '\n'" &
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

setup_web_if_enough_ram() {
    total_ram=$(get_approximate_ram_size)
    # 512内存才安装
    if [ $total_ram -gt 400 ]; then
        # lighttpd 虽然运行占用内存少，但安装占用空间大
        # setup_lighttpd
        # setup_nginx
        setup_websocketd
    fi
}

setup_lighttpd() {
    apk add lighttpd
    ln -sf /reinstall.html /var/www/localhost/htdocs/index.html
    rc-service -q lighttpd start
}

get_ttys() {
    prefix=$1
    # shellcheck disable=SC2154
    wget $confhome/ttys.sh -O- | sh -s $prefix
}

find_xda() {
    # 出错后再运行脚本，硬盘可能已经格式化，之前记录的分区表 id 无效
    # 因此找到 xda 后要保存 xda 到 /configs/xda

    # 先读取之前保存的
    if xda=$(get_config xda 2>/dev/null) && [ -n "$xda" ]; then
        return
    fi

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

    if [ -n "$xda" ]; then
        set_config xda "$xda"
    else
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

ensure_service_started() {
    service=$1

    if ! rc-service -q $service status; then
        if ! retry 5 rc-service -q $service start; then
            error_and_exit "Failed to start $service."
        fi
    fi
}

ensure_service_stopped() {
    service=$1

    if rc-service -q $service status; then
        if ! retry 5 rc-service -q $service stop; then
            error_and_exit "Failed to stop $service."
        fi
    fi
}

mod_motd() {
    # 安装后 alpine 后要恢复默认
    # 自动安装失败后，可能手动安装 alpine，因此无需判断 $distro
    file=/etc/motd
    if ! [ -e $file.orig ]; then
        cp $file $file.orig
        # shellcheck disable=SC2016
        echo "mv "\$mnt$file.orig" "\$mnt$file"" |
            insert_into_file "$(which setup-disk)" before 'cleanup_chroot_mounts "\$mnt"'

        cat <<EOF >$file
Reinstalling...
To view logs run:
tail -fn+1 /reinstall.log
EOF
    fi
}

umount_all() {
    dirs="/mnt /os /iso /wim /installer /nbd /nbd-boot /nbd-efi /nbd-test /root /nix"
    regex=$(echo "$dirs" | sed 's, ,|,g')
    if mounts=$(mount | grep -Ew "on $regex" | awk '{print $3}' | tac); then
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
    # 安装 arch 有 gpg-agent 进程驻留
    pkill gpg-agent || true
    rc-service -q --ifexists --ifstarted nix-daemon stop
    swapoff -a
    umount_all

    # 以下情况 umount -R /1 会提示 busy
    # mount /file1 /1
    # mount /1/file2 /2
}

# virt-what 自动安装 dmidecode，因此同时缓存
cache_dmi_and_virt() {
    if ! [ "$_dmi_and_virt_cached" = 1 ]; then
        apk add virt-what

        # 区分 kvm 和 virtio，原因:
        # 1. 阿里云 c8y virt-what 不显示 kvm
        # 2. 不是所有 kvm 都需要 virtio 驱动，例如 aws nitro
        # 3. virt-what 不会检测 virtio
        _virt=$(
            virt-what

            # hyper-v 环境下 modprobe virtio_scsi 也会创建 /sys/bus/virtio/drivers/virtio_scsi
            # 因此用 devices 判断更准确，有设备时才有 /sys/bus/virtio/drivers/*
            # 或者加上 lspci 检测?

            # 不要用 ls /sys/bus/virtio/devices/* && echo virtio
            # 因为有可能返回值不为 0 而中断脚本
            if ls /sys/bus/virtio/devices/* >/dev/null 2>&1; then
                echo virtio
            fi
        )

        _dmi=$(dmidecode | grep -E '(Manufacturer|Asset Tag|Vendor): ' | awk -F': ' '{print $2}')
        _dmi_and_virt_cached=1
        apk del virt-what
    fi
}

is_virt() {
    cache_dmi_and_virt
    [ -n "$_virt" ]
}

is_virt_contains() {
    cache_dmi_and_virt
    echo "$_virt" | grep -Eiwq "$1"
}

is_dmi_contains() {
    # Manufacturer: Alibaba Cloud
    # Manufacturer: Tencent Cloud
    # Manufacturer: Huawei Cloud
    # Asset Tag: OracleCloud.com
    # Vendor: Amazon EC2
    # Manufacturer: Amazon EC2
    # Asset Tag: Amazon EC2
    cache_dmi_and_virt
    echo "$_dmi" | grep -Eiwq "$1"
}

cache_lspci() {
    if [ -z "$_lspci" ]; then
        apk add pciutils
        _lspci=$(lspci)
        apk del pciutils
    fi
}

is_lspci_contains() {
    cache_lspci
    echo "$_lspci" | grep -Eiwq "$1"
}

get_config() {
    cat "/configs/$1"
}

set_config() {
    printf '%s' "$2" >"/configs/$1"
}

# ubuntu 安装版、el/ol 安装版不使用该密码
get_password_linux_sha512() {
    get_config password-linux-sha512
}

get_password_windows_administrator_base64() {
    get_config password-windows-administrator-base64
}

get_password_plaintext() {
    get_config password-plaintext
}

is_password_plaintext() {
    get_password_plaintext >/dev/null 2>&1
}

show_netconf() {
    grep -r . /dev/netconf/
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
        info "Network info:"
        echo
        echo "$_ra" | cat -n
        echo
        ip addr | cat -n
        echo
        show_netconf | cat -n
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

is_any_ipv4_has_internet() {
    grep -q 1 /dev/netconf/*/ipv4_has_internet
}

is_in_china() {
    grep -q 1 /dev/netconf/*/is_in_china
}

# 有 dhcpv4 不等于有网关，例如 vultr 纯 ipv6
# 没有 dhcpv4 不等于是静态ip，可能是没有 ip
is_dhcpv4() {
    if ! is_ipv4_has_internet || should_disable_dhcpv4; then
        return 1
    fi

    get_netconf_to dhcpv4
    # shellcheck disable=SC2154
    [ "$dhcpv4" = 1 ]
}

is_staticv4() {
    if ! is_ipv4_has_internet; then
        return 1
    fi

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
    if ! is_ipv6_has_internet; then
        return 1
    fi

    if ! is_slaac && ! is_dhcpv6; then
        get_netconf_to ipv6_addr
        get_netconf_to ipv6_gateway
        if [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ]; then
            return 0
        fi
    fi
    return 1
}

is_dhcpv6_or_slaac() {
    get_netconf_to dhcpv6_or_slaac
    # shellcheck disable=SC2154
    [ "$dhcpv6_or_slaac" = 1 ]
}

is_ipv4_has_internet() {
    get_netconf_to ipv4_has_internet
    # shellcheck disable=SC2154
    [ "$ipv4_has_internet" = 1 ]
}

is_ipv6_has_internet() {
    get_netconf_to ipv6_has_internet
    # shellcheck disable=SC2154
    [ "$ipv6_has_internet" = 1 ]
}

should_disable_dhcpv4() {
    get_netconf_to should_disable_dhcpv4
    # shellcheck disable=SC2154
    [ "$should_disable_dhcpv4" = 1 ]
}

should_disable_accept_ra() {
    get_netconf_to should_disable_accept_ra
    # shellcheck disable=SC2154
    [ "$should_disable_accept_ra" = 1 ]
}

should_disable_autoconf() {
    get_netconf_to should_disable_autoconf
    # shellcheck disable=SC2154
    [ "$should_disable_autoconf" = 1 ]
}

is_slaac() {
    # 如果是静态（包括自动获取到 IP 但无法联网而切换成静态）直接返回 1，不考虑 ra
    # 防止部分机器slaac/dhcpv6获取的ip/网关无法上网

    # 有可能 ra 的 dhcpv6/slaac 是打开的，但实测无法获取到 ipv6 地址
    # is_dhcpv6_or_slaac 是实测结果，因此如果实测不通过，也返回 1

    # 不要判断 is_staticv6，因为这会导致死循环
    if ! is_ipv6_has_internet || ! is_dhcpv6_or_slaac || should_disable_accept_ra || should_disable_autoconf; then
        return 1
    fi
    get_netconf_to slaac
    # shellcheck disable=SC2154
    [ "$slaac" = 1 ]
}

is_dhcpv6() {
    # 如果是静态（包括自动获取到 IP 但无法联网而切换成静态）直接返回 1，不考虑 ra
    # 防止部分机器slaac/dhcpv6获取的ip/网关无法上网

    # 有可能 ra 的 dhcpv6/slaac 是打开的，但实测无法获取到 ipv6 地址
    # is_dhcpv6_or_slaac 是实测结果，因此如果实测不通过，也返回 1

    # 不要判断 is_staticv6，因为这会导致死循环
    if ! is_ipv6_has_internet || ! is_dhcpv6_or_slaac || should_disable_accept_ra || should_disable_autoconf; then
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

# dd 完检测到镜像是 windows 时会改写此方法
is_windows() {
    [ "$distro" = windows ]
}

# 15063 或之后才支持 rdnss
is_windows_support_rdnss() {
    [ "$build_ver" -ge 15063 ]
}

get_windows_version_from_dll() {
    local dll=$1
    [ -f "$dll" ] || error_and_exit "File not found: $dll"

    apk add pev
    local ver
    ver="$(peres -v "$dll" | grep 'Product Version:' | awk '{print $NF}')"
    echo "Version: $ver" >&2
    IFS=. read -r nt_ver_major nt_ver_minor build_ver rev_ver _ < <(echo "$ver")
    nt_ver="$nt_ver_major.$nt_ver_minor"
    apk del pev
}

is_elts() {
    [ -n "$elts" ] && [ "$elts" = 1 ]
}

is_need_set_ssh_keys() {
    [ -s /configs/ssh_keys ]
}

is_need_change_ssh_port() {
    [ -n "$ssh_port" ] && ! [ "$ssh_port" = 22 ]
}

is_need_change_rdp_port() {
    [ -n "$rdp_port" ] && ! [ "$rdp_port" = 3389 ]
}

is_need_manual_set_dnsv6() {
    # 有没有可能是静态但是有 rdnss？
    ! is_have_ipv6 && return $FALSE
    is_dhcpv6 && return $FALSE
    is_staticv6 && return $TRUE
    is_slaac && ! is_enable_other_flag &&
        { ! is_have_rdnss || { is_have_rdnss && is_windows && ! is_windows_support_rdnss; }; }
}

get_current_dns() {
    mark=$(
        case "$1" in
        4) echo . ;;
        6) echo : ;;
        esac
    )
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    if false; then
        grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | grep -F "$mark" | cut -d '%' -f1
    else
        grep '^nameserver' /etc/resolv.conf | cut -d' ' -f2 | grep -F "$mark" | cut -d '%' -f1
    fi
}

to_upper() {
    tr '[:lower:]' '[:upper:]'
}

to_lower() {
    tr '[:upper:]' '[:lower:]'
}

del_cr() {
    sed 's/\r$//'
}

del_comment_lines() {
    sed '/^[[:space:]]*#/d'
}

del_empty_lines() {
    sed '/^[[:space:]]*$/d'
}

del_head_empty_lines_inplace() {
    # 从第一行直到找到 ^[:space:]
    # 这个区间内删除所有空行
    sed -i '1,/[^[:space:]]/ { /^[[:space:]]*$/d }' "$@"
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
    info "del invalid EFI entry"
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

# reinstall.sh 有同名方法
grep_efi_index() {
    awk '{print $1}' | sed -e 's/Boot//' -e 's/\*//'
}

# 某些机器可能不会回落到 bootx64.efi
# 阿里云 ECS 启动项有 EFI Shell
# 添加 bootx64.efi 到最后的话，会进入 EFI Shell
# 因此添加到最前面
add_default_efi_to_nvram() {
    info "add default EFI to nvram"

    apk add lsblk efibootmgr

    if efi_row=$(lsblk /dev/$xda -ro NAME,PARTTYPE,PARTUUID | grep -i "$EFI_UUID"); then
        efi_part_uuid=$(echo "$efi_row" | awk '{print $3}')
        efi_part_name=$(echo "$efi_row" | awk '{print $1}')
        efi_part_num=$(get_part_num_by_part "$efi_part_name")
        efi_file=$(get_fallback_efi_file_name)

        # 创建条目，先判断是否已经存在
        # 好像没必要先判断
        if true || ! efibootmgr | grep -i "HD($efi_part_num,GPT,$efi_part_uuid,.*)/File(\\\EFI\\\boot\\\\$efi_file)"; then
            efibootmgr --create \
                --disk "/dev/$xda" \
                --part "$efi_part_num" \
                --label "$efi_file" \
                --loader "\\EFI\\boot\\$efi_file"
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
    shift 3

    # 默认 grep -E
    if [ $# -eq 0 ]; then
        set -- -E
    fi

    if [ "$location" = head ]; then
        bak=$(mktemp)
        cp $file $bak
        cat - $bak >$file
    else
        line_num=$(grep "$@" -n "$regex_to_find" "$file" | cut -d: -f1)

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
        # shellcheck disable=SC2154
        if false; then
            if { [ "$distro" = debian ] && [ "$releasever" -ge 12 ]; } ||
                [ "$distro" = kali ]; then
                # alice + allow-hotplug 会有问题
                # 问题 1 debian 9/10/11/12:
                # 如果首次启动时，/etc/networking/interfaces 的 ethx 跟安装时不同
                # 即使启动 networking 服务前成功执行了 fix-eth-name.sh ，网卡也不会启动
                # 测试方法: 安装时手动修改 /etc/networking/interfaces enp3s0 为其他名字
                # 问题 2 debian 9/10/11:
                # 重启系统后会自动启动网卡，但运行 systemctl restart networking 会关闭网卡
                # 可能的原因: /lib/systemd/system/networking.service 没有 hotplug 相关内容，而 debian 12+ 有
                if [ -f /etc/network/devhotplug ] && grep -wo "$ethx" /etc/network/devhotplug; then
                    mode=allow-hotplug
                fi
            fi

            # if is_have_cmd udevadm; then
            #     enpx=$(udevadm test-builtin net_id /sys/class/net/$ethx 2>&1 | grep ID_NET_NAME_PATH= | cut -d= -f2)
            # fi
        fi

        # dmit debian 普通内核和云内核网卡名不一致，因此需要 rename
        # 安装系统时 ens18
        # 普通内核   ens18
        # 云内核     enp6s18
        # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=928923

        # 头部
        get_netconf_to mac_addr
        {
            echo
            # 这是标记，fix-eth-name 要用，不要删除
            # shellcheck disable=SC2154
            echo "# mac $mac_addr"
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
            if list=$(get_current_dns 4); then
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
            # debian 13 使用 ifupdown + dhcpcd-base
            # inet/inet6 都配置成 dhcp 时，重启后 dhcpv4 会丢失
            # 手动 systemctl restart networking 后正常
            # 删除 dhcpcd-base 安装 isc-dhcp-client（类似 debian 12 升级到 13），轮到 dhcpv6 丢失
            if { [ "$distro" = debian ] && [ "$releasever" -ge 13 ]; } ||
                [ "$distro" = kali ]; then
                echo "iface $ethx inet6 auto" >>$conf_file
            else
                echo "iface $ethx inet6 dhcp" >>$conf_file
            fi

        elif is_staticv6; then
            get_netconf_to ipv6_addr
            get_netconf_to ipv6_gateway
            cat <<EOF >>$conf_file
iface $ethx inet6 static
    address $ipv6_addr
    gateway $ipv6_gateway
EOF
            # debian 9
            # ipv4 支持静态 onlink 网关
            # ipv6 不支持静态 onlink 网关，需使用 post-up 添加，未测试动态
            # ipv6 也不支持直接 ip route add default via xxx onlink
            if [ "$distro" = debian ] && [ "$releasever" -le 9 ]; then
                # debian 添加 gateway 失败时不会执行 post-up
                # 因此 gateway post-up 只能二选一

                # 注释最后一行，也就是 gateway
                sed -Ei '$s/^( *)/\1# /' "$conf_file"
                cat <<EOF >>$conf_file
    post-up ip route add $ipv6_gateway dev $ethx
    post-up ip route add default via $ipv6_gateway dev $ethx
EOF
            fi
        fi

        # dns
        # 有 ipv6 但需设置 dns 的情况
        if is_need_manual_set_dnsv6; then
            for dns in $(get_current_dns 6); do
                cat <<EOF >>$conf_file
    dns-nameserver $dns
EOF
            done
        fi

        # 禁用 ra
        if should_disable_accept_ra; then
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

        # 禁用 autoconf
        if should_disable_autoconf; then
            if [ "$distro" = alpine ]; then
                cat <<EOF >>$conf_file
    pre-up echo 0 >/proc/sys/net/ipv6/conf/$ethx/autoconf
EOF
            else
                cat <<EOF >>$conf_file
    autoconf 0
EOF
            fi
        fi
    done
}

newline_to_comma() {
    tr '\n' ','
}

space_to_newline() {
    sed 's/ /\n/g'
}

trim() {
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

quote_word() {
    sed -E 's/([^[:space:]]+)/"\1"/g'
}

quote_line() {
    awk '{print "\""$0"\""}'
}

add_space() {
    space_count=$1

    spaces=$(printf '%*s' "$space_count" '')
    sed "s/^/$spaces/"
}

# 不够严谨，谨慎使用
nix_replace() {
    local key=$1
    local value=$2
    local type=$3
    local file=$4
    local key_ value_

    key_=$(echo "$key" | sed 's \. \\\. g') # . 改成 \.

    if [ "$type" = array ]; then
        local value_="[ $value ]"
    fi

    sed -i "s/$key_ =.*/$key = $value_;/" "$file"
}

create_nixos_network_config() {
    conf_file=$1
    true >$conf_file

    # 头部
    cat <<EOF >>$conf_file
networking = {
  usePredictableInterfaceNames = false;
EOF

    for ethx in $(get_eths); do
        # ipv4
        if is_staticv4; then
            get_netconf_to ipv4_addr
            get_netconf_to ipv4_gateway
            IFS=/ read -r address prefix < <(echo "$ipv4_addr")
            cat <<EOF >>$conf_file
  interfaces.$ethx.ipv4.addresses = [
    {
      address = "$address";
      prefixLength = $prefix;
    }
  ];
  defaultGateway = {
    address = "$ipv4_gateway";
    interface = "$ethx";
  };
EOF
        fi

        # ipv6
        if is_staticv6; then
            get_netconf_to ipv6_addr
            get_netconf_to ipv6_gateway
            IFS=/ read -r address prefix < <(echo "$ipv6_addr")
            cat <<EOF >>$conf_file
  interfaces.$ethx.ipv6.addresses = [
    {
      address = "$address";
      prefixLength = $prefix;
    }
  ];
  defaultGateway6 = {
    address = "$ipv6_gateway";
    interface = "$ethx";
  };
EOF
        fi
    done

    # 全局 dns
    need_set_dns=false
    for ethx in $(get_eths); do
        if is_staticv4 || is_staticv6 || is_need_manual_set_dnsv6; then
            need_set_dns=true
            break
        fi
    done

    if $need_set_dns; then
        cat <<EOF >>$conf_file
  nameservers = [
$(get_current_dns | quote_line | add_space 4)
  ];
EOF
    fi

    # 尾部
    cat <<EOF >>$conf_file
};
EOF

    # nixos 默认网络管理器是 dhcpcd
    # 但配置静态 ip 时用的是脚本
    # /nix/store/qcr1xxjdxcrnwqwrgysqpxx2aibp9fdl-unit-script-network-addresses-eth0-start/bin/network-addresses-eth0-start
    # ...
    # if out=$(ip addr replace "181.x.x.x/24" dev "eth0" 2>&1); then
    #   echo "done"
    # else
    #   echo "'ip addr replace "181.x.x.x/24" dev "eth0"' failed: $out"
    #   exit 1
    # fi
    # ...

    # 禁用 ra/autoconf
    local mode=1
    for ethx in $(get_eths); do
        if should_disable_accept_ra; then
            case "$mode" in
            1)
                cat <<EOF >>$conf_file
boot.kernel.sysctl."net.ipv6.conf.$ethx.accept_ra" = false;
EOF
                ;;
            2)
                # nixos 配置静态 ip 时用的是脚本
                # 好像因此不起作用
                cat <<EOF >>$conf_file
networking.dhcpcd.extraConfig =
  ''
    interface $ethx
      ipv6ra_noautoconf
  '';
EOF
                ;;
            3)
                # 暂时没用到 networkd
                cat <<EOF >>$conf_file
systemd.network.networks.$ethx = {
   matchConfig.Name = "$ethx";
   networkConfig = {
     IPv6AcceptRA = false;
   };
 };
EOF
                ;;
            esac
        fi

        if should_disable_autoconf; then
            case "$mode" in
            1)
                cat <<EOF >>$conf_file
boot.kernel.sysctl."net.ipv6.conf.$ethx.autoconf" = false;
EOF
                ;;
            2) ;;
            3) ;;
            esac
        fi
    done
}

install_alpine() {
    info "install alpine"

    need_ram=512
    swap_size=$(get_need_swap_size $need_ram)
    [ "$swap_size" -gt 0 ] && hack_lowram=true || hack_lowram=false

    # alpine 安装时会自动检测安装需要的 firmware
    # https://github.com/alpinelinux/alpine-conf/blob/3.18.1/setup-disk.in#L421
    # 但如果没有 modloop 则无法检测
    # 所以删除 modloop 前先记录用到的 firmware 包
    fw_pkgs=$(get_alpine_firmware_pkgs)

    if $hack_lowram; then
        # 预先加载需要的模块
        if rc-service -q modloop status; then
            modules="ext4 vfat nls_utf8 nls_cp437"
            for mod in $modules; do
                modprobe $mod
            done
            # crc32c 等于 crc32c-intel
            # 没有 sse4.2 的机器加载 crc32c 时会报错 modprobe: ERROR: could not insert 'crc32c_intel': No such device
            modprobe crc32c || modprobe crc32c-generic
        fi

        # 删除 modloop ，释放内存
        ensure_service_stopped modloop
        rm -f /lib/modloop-lts /lib/modloop-virt
    fi

    # bios机器用 setup-disk 自动分区会有 boot 分区
    # 因此手动分区安装
    create_part
    mount_part_basic_layout /os /os/boot/efi

    # 创建 swap
    if $hack_lowram; then
        create_swap $swap_size /os/swapfile
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
    # https://github.com/alpinelinux/alpine-conf/blob/3.18.1/setup-alpine.in#L229

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
        sed -i 's/--no-nvram//' "$(which setup-disk)"
    fi

    # 安装到硬盘
    # alpine默认使用 syslinux (efi 环境除外)，这里强制使用 grub，方便用脚本再次重装
    KERNELOPTS="$(get_ttys console=)"
    export KERNELOPTS
    export BOOTLOADER="grub"
    setup-disk -m sys -k $kernel_flavor /os

    # 删除 setup-disk 时自动安装的包
    apk del e2fsprogs dosfstools efibootmgr grub*

    # 如果没有挂载 /proc

    # 1. chroot /os setup-keymap us us 会报错
    # grep: /proc/filesystems: No such file or directory

    # 2. 安装固件微码会触发 grub-probe，如果没挂载会报错
    # Executing grub-2.12-r5.trigger
    # /usr/sbin/grub-probe: error: failed to get canonical path of `/dev/vda1'.
    # ERROR: grub-2.12-r5.trigger: script exited with error 1

    mount_pseudo_fs /os

    # 安装到硬盘后才安装各种应用
    # 避免占用 Live OS 内存

    # 网络
    # udhcpc
    # 坑1 ip -4 addr 无法知道是否是 dhcp
    # 坑2 networking 服务不会运行 udhcpc6
    # 坑3 h3c 移动云电脑 udhcpc6 无法获取 dhcpv6

    # dhcpcd
    # 坑1 slaac默认开了隐私保护，造成ip和后台面板不一致

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
    # 3.21 默认是 chrony
    # 3.22 默认是 busybox ntp
    printf '\n' | chroot /os setup-ntp || true

    # 设置公钥
    if is_need_set_ssh_keys; then
        set_ssh_keys_and_del_password /os
    fi

    # 下载 fix-eth-name
    download "$confhome/fix-eth-name.sh" /os/fix-eth-name.sh
    download "$confhome/fix-eth-name.initd" /os/etc/init.d/fix-eth-name
    chmod +x /os/etc/init.d/fix-eth-name
    chroot /os rc-update add fix-eth-name boot

    # 安装 frpc
    if [ -s /configs/frpc.toml ]; then
        chroot /os apk add frp
        # chroot rc-update add 默认添加到 sysinit
        # 但不加 chroot 默认添加到 default
        chroot /os rc-update add frpc boot
        cp /configs/frpc.toml /os/etc/frp/frpc.toml
    fi

    # setup-disk 会自动选择固件，但不包括微码？
    # https://github.com/alpinelinux/alpine-conf/blob/3.18.1/setup-disk.in#L421
    if fw_pkgs="$fw_pkgs $(get_ucode_firmware_pkgs)" && [ -n "$fw_pkgs" ]; then
        chroot /os apk add $fw_pkgs
    fi

    # 3.19 或以上，非 efi 需要手动安装 grub
    if ! is_efi; then
        chroot /os grub-install --target=i386-pc /dev/$xda
    fi

    # efi grub 添加 fwsetup 条目
    chroot /os update-grub

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
    cpu_vendor=$(grep 'vendor_id' /proc/cpuinfo | head -1 | awk '{print $NF}')
    case "$cpu_vendor" in
    GenuineIntel) echo intel ;;
    AuthenticAMD) echo amd ;;
    *) echo other ;;
    esac
}

min() {
    printf "%d\n" "$@" | sort -n | head -n 1
}

# 设置线程
# 根据 cpu 核数，每个线程的内存，取最小值
get_build_threads() {
    threads_per_mb=$1

    threads_by_core=$(nproc)
    threads_by_ram=$(($(get_approximate_ram_size) / threads_per_mb))
    [ $threads_by_ram -eq 0 ] && threads_by_ram=1
    min $threads_by_ram $threads_by_core
}

add_newline() {
    # shellcheck disable=SC1003
    case "$1" in
    head | start) sed -e '1s/^/\n/' ;;
    tail | end) sed -e '$a\\' ;;
    both) sed -e '1s/^/\n/' -e '$a\\' ;;
    esac
}

install_nixos() {
    info "Install NixOS"

    os_dir=/os
    keep_swap=true
    nix_from=website
    ram_per_thread=2048

    threads=$(get_build_threads $ram_per_thread)
    swap_size=$(get_need_swap_size $ram_per_thread)

    show_nixos_config() {
        echo
        # 过滤 frp auth.token
        cat -n /os/etc/nixos/configuration.nix | grep -Fv 'auth.token'
        echo
        cat -n /os/etc/nixos/hardware-configuration.nix
        echo
    }

    # 挂载分区，创建 swapfile
    mount_part_basic_layout /os /os/efi
    if [ "$swap_size" -gt 0 ]; then
        create_swap "$swap_size" /os/swapfile
    fi

    # 步骤
    # 1. 安装 nix (nix-xxx)
    # 2. 用 nix 安装 nixos-install-tools (nixos-xxx)
    # 3. 运行 nixos-generate-config 生成配置 + 编辑
    # 4. 运行 nixos-install
    # https://nixos.org/manual/nixos/stable/index.html#sec-installing-from-other-distro

    # nix 安装方式                                    分支          版本
    # apk add nix                                    3.20         2.22.0  # nix 本体跟 alpine 正常的软件一样，不在 /nix/store 里面
    # env -iA nixpkgs.nix                            24.05        2.18.5
    # sh <(curl -L https://nixos.org/nix/install)   unstable?     2.24.2

    # apk add 安装的 nix 有时会卡在
    # copying path '/nix/store/gcbrjlfm5h21ybf1h2lfq773zafjmzjr-curl-8.7.1-man' from 'https://cache.nixos.org'...
    # 但是 cpu 空载

    # 安装 nix
    mkdir -p /os/nix /nix
    mount --bind /os/nix /nix

    # nix 安装脚本和 /root/.nix-profile/etc/profile.d/nix.sh 都会用到这两个变量
    # 但从 alpine local.d 运行没有这两个变量
    export USER=root
    export HOME=/root

    case "$nix_from" in
    alpine)
        apk add nix
        # 设置 nix 镜像和线程
        # alpine 默认设置了 4 线程
        # https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/community/nix/APKBUILD#L125
        sed -i '/max-jobs/d' /etc/nix/nix.conf
        echo "max-jobs = $threads" >>/etc/nix/nix.conf
        if is_in_china; then
            echo "substituters = $mirror/store" >>/etc/nix/nix.conf
        fi
        rc-service -q nix-daemon restart
        # 添加 nix-env 安装的软件到 PATH
        PATH="/root/.nix-profile/bin:$PATH"
        ;;
    website)
        # https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/community/nix/nix.pre-install
        # https://nix.dev/manual/nix/latest/installation/multi-user
        if ! grep -q nixbld /etc/passwd; then
            addgroup -S nixbld
            for n in $(seq 1 10); do
                adduser -S -D -H -h /var/empty -s /sbin/nologin -G nixbld \
                    -g "Nix build user $n" nixbld$n
            done
        fi

        if is_in_china; then
            sh=https://mirror.nju.edu.cn/nix/latest/install
        else
            sh=https://nixos.org/nix/install
        fi
        apk add xz
        wget -O- "$sh" | sh -s -- --no-daemon --no-channel-add
        apk del xz
        # shellcheck source=/dev/null
        . /root/.nix-profile/etc/profile.d/nix.sh
        ;;
    esac

    # 添加 channel
    # shellcheck disable=SC2154
    nix-channel --add $mirror/nixos-$releasever nixpkgs
    nix-channel --update

    # 安装 channal 的 nix
    # shellcheck source=/dev/null
    if false; then
        nix-env -iA nixpkgs.nix -j $threads
        . ~/.nix-profile/etc/profile.d/nix.sh
    fi

    # 安装 nixos-install-tools
    nix-env -iA nixpkgs.nixos-install-tools -j $threads

    # 生成配置并显示
    nixos-generate-config --root /os
    echo "Original NixOS Configuration:"
    show_nixos_config

    # 修改 configuration.nix
    if is_efi; then
        nix_bootloader="boot.loader.efi.efiSysMountPoint = \"/efi\";"
    else
        nix_bootloader="boot.loader.grub.device = \"/dev/$xda\";"
    fi

    if is_in_china; then
        nix_substituters="nix.settings.substituters = lib.mkForce [ \"$mirror/store\" ];"
    fi

    if [ -e /os/swapfile ] && $keep_swap; then
        nix_swap="swapDevices = [{ device = \"/swapfile\"; size = $swap_size; }];"
    fi

    if is_need_set_ssh_keys; then
        nix_ssh_keys_or_PermitRootLogin="
users.users.root.openssh.authorizedKeys.keys = [
$(del_comment_lines </configs/ssh_keys | del_empty_lines | quote_line | add_space 2)
];
"
    else
        nix_ssh_keys_or_PermitRootLogin='services.openssh.settings.PermitRootLogin = "yes";'
    fi

    if is_need_change_ssh_port; then
        nix_ssh_ports="services.openssh.ports = [ $ssh_port ];"
    fi

    # 虽然是原始 frpc.toml (string) 转成 toml 类型，再转成最终使用的 frpc.toml (string)
    # 但是可以避免原始 frpc.toml 有错误导致失联
    if [ -s /configs/frpc.toml ]; then
        nix_frpc=$(
            cat <<EOF
services.frp = {
  enable = true;
  role = "client";
  settings = builtins.fromTOML ''
$(del_comment_lines </configs/frpc.toml | add_space 4)
  '';
};
EOF
        )
    fi

    # TODO: 准确匹配网卡，添加 udev 或者直接配置 networkd 匹配 mac
    create_nixos_network_config /tmp/nixos_network_config.nix

    del_empty_lines <<EOF | add_space 2 | add_newline both |
############### Add by reinstall.sh ###############
$nix_bootloader
$nix_swap
$nix_substituters
boot.kernelParams = [ $(get_ttys console= | quote_word) ];
services.openssh.enable = true;
$nix_ssh_keys_or_PermitRootLogin
$nix_ssh_ports
$nix_frpc
$(cat /tmp/nixos_network_config.nix)
###################################################
EOF
        insert_into_file /os/etc/nixos/configuration.nix before "networking.hostName" -F

    # 修改 hardware-configuration.nix
    # 在 vultr efi 机器上，nixos-generate-config 不会添加 virtio_pci
    # 导致 virtio_blk 用不了，启动时 initrd 找不到系统分区
    # 可能由于 alpine 的 virtio_pci 编译进内核而不是模块
    # 因此 nixos-generate-config 不会添加 virtio_pci 到配置文件
    olds=$(
        grep -F 'boot.initrd.availableKernelModules' /os/etc/nixos/hardware-configuration.nix |
            cut -d= -f2 | tr -d '"[];' | xargs
    )
    alls="$olds"
    # https://github.com/search?q=repo%3ANixOS%2Fnixpkgs+availableKernelModules&type=code
    for mod in ahci ata_piix uhci_hcd sr_mod nvme \
        virtio_pci virtio_blk virtio_scsi \
        xen_blkfront xen_scsifront \
        hv_storvsc \
        vmw_pvscsi \
        mptspi; do
        if [ -d /sys/module/$mod ] && ! echo "$olds" | grep -wq "$mod"; then
            echo "Adding modules: $mod"
            alls="$alls $mod"
        fi
    done
    # 去除多余的空格
    alls=$(echo "$alls" | xargs)

    # boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
    nix_replace \
        boot.initrd.availableKernelModules \
        "$(echo "$alls" | quote_word)" \
        array \
        /os/etc/nixos/hardware-configuration.nix

    # 显示修改后的配置
    echo "Modified NixOS Configuration:"
    show_nixos_config

    # 安装系统
    nixos-install --root /os --no-root-passwd -j $threads

    # 设置密码
    if ! is_need_set_ssh_keys; then
        echo "root:$(get_password_linux_sha512)" | nixos-enter --root /os -- \
            /run/current-system/sw/bin/chpasswd -e
    fi

    # 设置 channel
    if is_in_china; then
        nixos-enter --root /os -- \
            /run/current-system/sw/bin/nix-channel \
            --add https://mirrors.cernet.edu.cn/nix-channels/nixos-$releasever nixos
    fi

    # 清理
    nix-env -e '*'
    # /nix/var/nix/profiles/system/sw/bin/nix-collect-garbage -d
    /nix/var/nix/profiles/system/sw/bin/nixos-enter --root /os -- \
        /run/current-system/sw/bin/nix-collect-garbage -d

    # 删除 nix
    umount /nix
    apk del nix

    # swapfile
    if [ -e /os/swapfile ]; then
        if $keep_swap; then
            :
        else
            swapoff -a
            rm -rf /os/swapfile
        fi
    fi

    # 重新显示配置，方便查看
    show_nixos_config
}

add_systemd_service() {
    local os_dir=$1
    local service_name=$2

    download "$confhome/$service_name.service" "$os_dir/etc/systemd/system/$service_name.service"
    chroot "$os_dir" systemctl enable "$service_name.service"

    # aosc 首次开机会执行 preset-all
    # 因此需要设置 fix-eth-name 的 preset 状态
    # 不然首次开机 /etc/systemd/system/multi-user.target.wants/fix-eth-name.service 会被删除
    # 通常 /etc/systemd/system-preset/ 文件夹要新建，因此不放在这里

    # 可能是 /usr/lib/systemd/system-preset/ 或者 /lib/systemd/system-preset/
    if [ -d "$os_dir/usr/lib/systemd/system-preset" ]; then
        echo "enable $service_name.service" >"$os_dir/usr/lib/systemd/system-preset/01-$service_name.preset"
    else
        echo "enable $service_name.service" >"$os_dir/lib/systemd/system-preset/01-$service_name.preset"
    fi
}

add_fix_eth_name_systemd_service() {
    local os_dir=$1

    # 无需执行 systemctl daemon-reload
    # 因为 chroot 下执行会提示 Running in chroot, ignoring command 'daemon-reload'
    download "$confhome/fix-eth-name.sh" "$os_dir/fix-eth-name.sh"
    add_systemd_service "$os_dir" fix-eth-name
}

get_frpc_url() {
    wget "$confhome/get-frpc-url.sh" -O- | sh -s "$@"
}

add_frpc_systemd_service_if_need() {
    local os_dir=$1

    if [ -s /configs/frpc.toml ]; then
        mkdir -p "$os_dir/usr/local/bin"
        mkdir -p "$os_dir/usr/local/etc/frpc"

        # 下载 frpc
        # 注意下载的 frpc owner 不是 root:root
        frpc_url=$(get_frpc_url linux)
        basename=$(echo "$frpc_url" | awk -F/ '{print $NF}' | sed 's/\.tar\.gz//')
        download "$frpc_url" "$os_dir/frpc.tar.gz"
        tar xzf "$os_dir/frpc.tar.gz" "$basename/frpc" -O >"$os_dir/usr/local/bin/frpc"
        rm -f "$os_dir/frpc.tar.gz"
        chmod a+x "$os_dir/usr/local/bin/frpc"

        # frpc conf
        cp /configs/frpc.toml "$os_dir/usr/local/etc/frpc/frpc.toml"

        # 添加服务
        add_systemd_service "$os_dir" frpc
    fi
}

basic_init() {
    os_dir=$1

    # 此时不能用
    # chroot $os_dir timedatectl set-timezone Asia/Shanghai
    # Failed to create bus connection: No such file or directory

    # debian 11 没有 systemd-firstboot
    if is_have_cmd_on_disk $os_dir systemd-firstboot; then
        if chroot $os_dir systemd-firstboot --help | grep -wq '\--force'; then
            chroot $os_dir systemd-firstboot --timezone=Asia/Shanghai --force
        else
            chroot $os_dir systemd-firstboot --timezone=Asia/Shanghai
        fi
    fi

    # gentoo 不会自动创建 machine-id
    clear_machine_id $os_dir

    # sshd
    chroot $os_dir ssh-keygen -A

    sshd_enabled=false
    sshs="sshd.service ssh.service sshd.socket ssh.socket"
    for i in $sshs; do
        if chroot $os_dir systemctl -q is-enabled $i; then
            sshd_enabled=true
            break
        fi
    done
    if ! $sshd_enabled; then
        for i in $sshs; do
            if chroot $os_dir systemctl -q enable $i; then
                break
            fi
        done
    fi

    if is_need_change_ssh_port; then
        change_ssh_port $os_dir $ssh_port
    fi

    # 公钥/密码
    if is_need_set_ssh_keys; then
        set_ssh_keys_and_del_password $os_dir
    else
        change_root_password $os_dir
        allow_root_password_login $os_dir
        allow_password_login $os_dir
    fi

    # 下载 fix-eth-name.service
    # 即使开了 net.ifnames=0 也需要
    # 因为 alpine live 和目标系统的网卡顺序可能不同
    add_fix_eth_name_systemd_service $os_dir

    # frpc
    add_frpc_systemd_service_if_need $os_dir
}

install_arch_gentoo_aosc() {
    info "install $distro"

    network_app=$(
        case "$distro" in
        arch | gentoo) echo systemd-networkd ;;
        aosc) echo network-manager ;;
        esac
    )

    set_locale() {
        echo "C.UTF-8 UTF-8" >>$os_dir/etc/locale.gen
        chroot $os_dir locale-gen
    }

    # shellcheck disable=SC2317
    install_arch() {
        # 添加 swap
        create_swap_if_ram_less_than 1024 $os_dir/swapfile

        apk add arch-install-scripts

        # 为了二次运行时 /etc/pacman.conf 未修改
        if [ -f /etc/pacman.conf.orig ]; then
            cp /etc/pacman.conf.orig /etc/pacman.conf
        else
            cp /etc/pacman.conf /etc/pacman.conf.orig
        fi

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
        if fw_pkgs=$(get_ucode_firmware_pkgs) && [ -n "$fw_pkgs" ]; then
            chroot $os_dir pacman -Syu --noconfirm $fw_pkgs
        fi

        # arm 的内核有多种选择，默认是 linux-aarch64，所以要添加 --noconfirm
        chroot $os_dir pacman -Syu --noconfirm linux
    }

    # shellcheck disable=SC2317
    install_gentoo() {
        # 添加 swap
        create_swap_if_ram_less_than 2048 $os_dir/swapfile

        # 解压系统
        apk add tar xz pv
        # shellcheck disable=SC2154
        download "$img" $os_dir/gentoo.tar.xz
        echo "Uncompressing Gentoo..."
        pv -f $os_dir/gentoo.tar.xz | tar xpJ --numeric-owner --xattrs-include='*.*' -C $os_dir
        rm $os_dir/gentoo.tar.xz
        apk del tar xz pv

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

        cat <<EOF >>$os_dir/etc/portage/make.conf
MAKEOPTS="-j$(get_build_threads 2048)"
EOF

        # 设置 http repo + binpkg repo
        # https://mirror.nju.edu.cn/gentoo/releases/amd64/autobuilds/current-stage3-amd64-systemd-mergedusr/stage3-amd64-systemd-mergedusr-20240317T170433Z.tar.xz
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
            git_uri=https://mirror.nju.edu.cn/git/gentoo-portage.git
        else
            # github 不支持 ipv6
            is_any_ipv4_has_internet && git_uri=https://github.com/gentoo-mirror/gentoo.git ||
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
        if fw_pkgs=$(get_ucode_firmware_pkgs) && [ -n "$fw_pkgs" ]; then
            chroot $os_dir emerge $fw_pkgs
        fi

        # 安装 grub + 内核
        # TODO: 先判断是否有 binpkg，有的话不修改 GRUB_PLATFORMS
        is_efi && grub_platforms="efi-64" || grub_platforms="pc"
        echo GRUB_PLATFORMS=\"$grub_platforms\" >>$os_dir/etc/portage/make.conf
        echo "sys-kernel/installkernel dracut grub" >$os_dir/etc/portage/package.use/installkernel
        chroot $os_dir emerge sys-kernel/gentoo-kernel-bin
    }

    install_aosc() {
        # 解压系统
        apk add wget tar xz
        wget "$img" -O- | tar xpJ --numeric-owner --xattrs-include='*.*' -C $os_dir
        apk del wget tar xz

        # 添加 swap
        create_swap_if_ram_less_than 1024 $os_dir/swapfile

        # 挂载伪文件系统
        mount_pseudo_fs $os_dir

        # 生成 initramfs
        chroot $os_dir update-initramfs
    }

    os_dir=/os

    # 挂载分区
    mount_part_basic_layout /os /os/efi

    # 安装系统
    install_$distro

    # 安装 arch 有 gpg-agent 进程驻留
    pkill gpg-agent || true

    # 初始化
    if false; then
        # preset-all 后多了很多服务，内存占用多了几十M
        chroot $os_dir systemctl preset-all
    fi

    # 网络配置
    case "$network_app" in
    systemd-networkd)
        chroot $os_dir systemctl enable systemd-networkd
        chroot $os_dir systemctl enable systemd-resolved

        apk add cloud-init
        # 第二次运行会报错
        useradd systemd-network || true
        create_cloud_init_network_config net.cfg
        cat -n net.cfg
        # 正常应该是 -D gentoo，但 alpine 的 cloud-init 包缺少 gentoo 配置
        cloud-init devel net-convert -p net.cfg -k yaml -d out -D alpine -O networkd

        # 注意名字是 10-cloud-init-eth*.network，fix-eth-name.sh 会此文件名查找配置文件
        cp out/etc/systemd/network/10-cloud-init-eth*.network $os_dir/etc/systemd/network/

        # 删除网卡名匹配
        sed -i '/^Name=/d' $os_dir/etc/systemd/network/10-cloud-init-eth*.network

        # 删除 Generated by cloud-init. Changes will be lost.
        # 并删除头部的空行
        sed -i '/^# Generated by cloud-init/d' $os_dir/etc/systemd/network/10-cloud-init-eth*.network
        del_head_empty_lines_inplace $os_dir/etc/systemd/network/10-cloud-init-eth*.network

        # 清理
        rm -rf net.cfg out
        apk del cloud-init

        # 显示网络配置
        cat -n $os_dir/etc/systemd/network/10-cloud-init-eth*.network
        ;;
    network-manager)
        chroot $os_dir systemctl enable NetworkManager

        # 可以直接用 alpine 的 cloud-init 生成 Network Manager 配置
        create_cloud_init_network_config /net.cfg
        create_network_manager_config /net.cfg "$os_dir"
        rm /net.cfg
        ;;
    esac

    # arch gentoo 网络配置是用 alpine cloud-init 生成的
    # cloud-init 版本够新，因此无需修复 onlink 网关

    basic_init $os_dir

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
        file=$os_dir/etc/default/grub.d/tty.cfg
    else
        file=$os_dir/etc/default/grub
    fi
    ttys_cmdline=$(get_ttys console=)
    echo GRUB_CMDLINE_LINUX=\"\$GRUB_CMDLINE_LINUX $ttys_cmdline\" >>$file
    chroot $os_dir grub-mkconfig -o /boot/grub/grub.cfg

    # fstab
    # fstab 可不写 efi 条目， systemd automount 会自动挂载
    # fstab 头部有使用说明，因此用 >>
    apk add arch-install-scripts
    genfstab -U $os_dir | sed '/swap/d' >>$os_dir/etc/fstab
    apk del arch-install-scripts

    # 删除 resolv.conf，不然 systemd-resolved 无法创建软链接
    rm_resolv_conf $os_dir

    # 删除 swap
    swapoff -a
    rm -rf $os_dir/swapfile
}

get_http_file_size() {
    url=$1

    # 网址重定向可能得到多个 Content-Length, 选最后一个
    wget --spider -S "$url" 2>&1 | grep 'Content-Length:' |
        tail -1 | awk '{print $2}' | grep .
}

get_url_hash() {
    url=$1

    echo "$url" | md5sum | awk '{print $1}'
}

aria2c() {
    if ! is_have_cmd aria2c; then
        apk add aria2
    fi

    # stdbuf 在 coreutils 包里面
    if ! is_have_cmd stdbuf; then
        apk add coreutils
    fi

    # 指定 bt 种子时没有链接，因此忽略错误
    echo "$@" | grep -oE '(http|https|magnet):[^ ]*' || true

    # 下载 tracker
    # 在 sub shell 里面无法保存变量，因此写入到文件
    if echo "$@" | grep -Eq 'magnet:|\.torrent' && ! [ -f "/tmp/trackers" ]; then
        # 独自一行下载，不然下载失败不会报错
        # 里面有空行
        # txt=$(wget -O- https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt | grep .)
        # txt=$(wget -O- https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt | grep .)
        txt=$(wget -O- https://cf.trackerslist.com/best.txt | grep .)
        # sed 删除最后一个逗号
        echo "$txt" | newline_to_comma | sed 's/,$//' >/tmp/trackers
    fi

    # --dht-entry-point=router.bittorrent.com:6881 \
    # --dht-entry-point=dht.transmissionbt.com:6881 \
    # --dht-entry-point=router.utorrent.com:6881 \
    retry 5 5 stdbuf -oL -eL aria2c \
        -x4 \
        --seed-time=0 \
        --allow-overwrite=true \
        --summary-interval=0 \
        --max-tries 1 \
        --bt-tracker="$([ -f "/tmp/trackers" ] && cat /tmp/trackers)" \
        "$@"
}

download_torrent_by_magnet() {
    url=$1
    dst=$2

    url_hash=$(get_url_hash "$url")

    mkdir -p /tmp/bt/$url_hash

    # 不支持 -o bt.torrent 指定文件名
    aria2c "$url" \
        --bt-metadata-only=true \
        --bt-save-metadata=true \
        -d /tmp/bt/$url_hash

    mv /tmp/bt/$url_hash/*.torrent "$dst"
    rm -rf /tmp/bt/$url_hash
}

get_torrent_path_by_magnet() {
    echo "/tmp/bt/$(get_url_hash "$1").torrent"
}

get_bt_file_size() {
    url=$1

    torrent="$(get_torrent_path_by_magnet $url)"
    download_torrent_by_magnet "$url" "$torrent" >&2

    # 列出第一个文件的大小
    # idx|path/length
    # ===+===========================================================================
    #   1|./zh-cn_windows_11_consumer_editions_version_24h2_updated_jan_2025_x64_dvd_7a8e5a29.iso
    #    |6.1GiB (6,557,558,784)

    aria2c --show-files=true "$torrent" |
        grep -F -A1 '  1|./' | tail -1 | grep -o '(.*)' | sed -E 's/[(),]//g' | grep .
}

get_link_file_size() {
    if is_magnet_link "$1" >&2; then
        get_bt_file_size "$1"
    else
        get_http_file_size "$1"
    fi
}

pipe_extract() {
    # alpine busybox 自带 gzip，但官方版也许性能更好
    case "$img_type_warp" in
    xz | gzip | zstd)
        apk add $img_type_warp
        "$img_type_warp" -dc
        ;;
    tar)
        apk add tar
        tar x -O
        ;;
    tar.*)
        type=$(echo "$img_type_warp" | cut -d. -f2)
        apk add tar "$type"
        tar x "--$type" -O
        ;;
    '') cat ;;
    *) error_and_exit "Not supported img_type_warp: $img_type_warp" ;;
    esac
}

dd_raw_with_extract() {
    info "dd raw"

    # 用官方 wget，一来带进度条，二来自带重试功能
    apk add wget

    if ! wget $img -O- | pipe_extract >/dev/$xda 2>/tmp/dd_stderr; then
        # vhd 文件结尾有 512 字节额外信息，可以忽略
        if grep -iq 'No space' /tmp/dd_stderr; then
            apk add parted
            disk_size=$(get_disk_size /dev/$xda)
            disk_end=$((disk_size - 1))

            # 如果报错，那大概是因为镜像比硬盘大
            if last_part_end=$(parted -sf /dev/$xda 'unit b print' ---pretend-input-tty |
                del_empty_lines | tail -1 | awk '{print $3}' | sed 's/B//' | grep .); then

                echo "Last part end: $last_part_end"
                echo "Disk end:      $disk_end"

                if [ "$last_part_end" -le "$disk_end" ]; then
                    echo "Safely ignore no space error."
                    return
                fi
            fi
        fi
        error_and_exit "$(cat /tmp/dd_stderr)"
    fi
}

get_disk_sector_count() {
    # cat /proc/partitions
    blockdev --getsz "$1"
}

get_disk_size() {
    blockdev --getsize64 "$1"
}

get_disk_logic_sector_size() {
    blockdev --getss "$1"
}

is_4kn() {
    [ "$(blockdev --getss "$1")" = 4096 ]
}

is_xda_gt_2t() {
    disk_size=$(get_disk_size /dev/$xda)
    disk_2t=$((2 * 1024 * 1024 * 1024 * 1024))
    [ "$disk_size" -gt "$disk_2t" ]
}

create_part() {
    # 除了 dd 都会用到
    info "Create Part"

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
        if ! size_bytes=$(get_link_file_size "$iso"); then
            # 默认值，最大的iso 23h2 假设 7g
            size_bytes=$((7 * 1024 * 1024 * 1024))
        fi

        # 按iso容量计算分区大小
        # 200m 用于驱动/文件系统自身占用 + pagefile
        # 理论上 installer 分区可以删除 boot.wim，这样就不用额外添加 200m，但是
        # 1. vista/2008 不能删除 boot.wim
        # 2. 下载镜像前不知道是 vista/2008，因为 --image-name 可以随便输入
        # 因此还是要额外添加 200m
        # 注意这里单位要用 MiB，因为后面的 border 要以 MiB 计算
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
                mkpart '" "' ntfs 1041MiB -${part_size} \
                mkpart '" "' ntfs -${part_size} 100% \
                set 1 boot on \
                set 2 msftres on \
                set 3 msftdata on
            update_part

            mkfs.fat -n efi /dev/$xda*1                           #1 efi
            dd if=/dev/zero of="$(ls /dev/$xda*2)" bs=1M count=16 #2 msr
            mkfs.ntfs -f -F -L os /dev/$xda*3                     #3 os
            mkfs.ntfs -f -F -L installer /dev/$xda*4              #4 installer
        else
            # bios + mbr 启动盘最大可用 2t
            if is_xda_gt_2t; then
                border=$((2 * 1024 * 1024 - ${part_size%MiB}))MiB
                max_usable_size=2TiB
            else
                border=-${part_size}
                max_usable_size=100%
            fi
            parted /dev/$xda -s -- \
                mklabel msdos \
                mkpart primary ntfs 1MiB ${border} \
                mkpart primary ntfs ${border} ${max_usable_size} \
                set 1 boot on
            update_part

            mkfs.ntfs -f -F -L os /dev/$xda*1        #1 os
            mkfs.ntfs -f -F -L installer /dev/$xda*2 #2 installer
        fi
    elif [ "$distro" = fnos ]; then
        # 先用 100% 分区安装后再缩小没意义，因为小硬盘用 100% 还是装不了
        # 因此直接用用户输入的分区大小

        # 1. 官方安装器对系统盘大小的定义包含引导分区大小
        # 2. 官方 efi 用的是 1MiB-100M，但我们用 1MiB-101MiB

        # 预期的系统分区大小，包括引导的 1M + 100M 的引导分区
        expect_m=$((${fnos_part_size%[Gg]} * 1024))

        sector_size=$(get_disk_logic_sector_size /dev/$xda)
        total_sector_count=$(get_disk_sector_count /dev/$xda)

        # 截止最后一个分区的总扇区数（也就是总硬盘扇区数 - 备份分区表扇区数）
        if is_efi; then
            total_sector_count_except_backup_gpt=$((total_sector_count - 33))
        else
            total_sector_count_except_backup_gpt=$total_sector_count
        fi

        # 向下取整 MiB
        # gpt 最后 33 个扇区是备份分区表，不可用
        # parted 结束位置填 100% 时也会忽略最后不足 1MiB 的部分，我们模仿它
        max_can_use_m=$((total_sector_count_except_backup_gpt * sector_size / 1024 / 1024))

        echo "expect_m: $expect_m"
        echo "max_can_use_m: $max_can_use_m"

        # 20G 的硬盘，即使用 msdos 分区表，parted 也不接受 part end 为 20480MiB，因此要用 100%
        # The location 20480MiB is outside of the device /dev/vda.
        # 但是 100% 分区后 end 就是 20480MiB

        os_part_end=${expect_m}MiB
        if [ "$expect_m" -ge "$max_can_use_m" ]; then
            echo "Expect size is equal/greater than max size. Setting to 100%"
            os_part_end=100%
        fi

        # 需关闭这几个特性，否则 grub 无法识别
        ext4_opts="-O ^metadata_csum_seed,^orphan_file"
        if is_efi; then
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart BOOT fat32 1MiB 101MiB \
                mkpart SYSTEM ext4 101MiB $os_part_end \
                set 1 esp on
            update_part

            mkfs.fat /dev/$xda*1                #1 efi
            mkfs.ext4 -F $ext4_opts /dev/$xda*2 #2 os + installer
        else
            # bios
            # 官方安装器不支持 bios + >2t
            parted /dev/$xda -s -- \
                mklabel msdos \
                mkpart primary 1MiB 101MiB \
                mkpart primary 101MiB $os_part_end \
                set 2 boot on
            update_part

            echo                                #1 官方安装有这个分区
            mkfs.ext4 -F $ext4_opts /dev/$xda*2 #2 os + installer
        fi
    elif is_use_cloud_image; then
        installer_part_size="$(get_cloud_image_part_size)"
        # 这几个系统不使用dd，而是复制文件
        if [ "$distro" = centos ] || [ "$distro" = almalinux ] || [ "$distro" = rocky ] ||
            [ "$distro" = oracle ] || [ "$distro" = redhat ] ||
            [ "$distro" = anolis ] || [ "$distro" = opencloudos ] || [ "$distro" = openeuler ] ||
            [ "$distro" = ubuntu ]; then
            # 这里的 fs 没有用，最终使用目标系统的格式化工具
            fs=ext4
            if is_efi; then
                parted /dev/$xda -s -- \
                    mklabel gpt \
                    mkpart '" "' fat32 1MiB 101MiB \
                    mkpart '" "' $fs 101MiB -$installer_part_size \
                    mkpart '" "' ext4 -$installer_part_size 100% \
                    set 1 esp on
                update_part

                mkfs.fat -n efi /dev/$xda*1           #1 efi
                echo                                  #2 os 用目标系统的格式化工具
                mkfs.ext4 -F -L installer /dev/$xda*3 #3 installer
            else
                parted /dev/$xda -s -- \
                    mklabel gpt \
                    mkpart '" "' ext4 1MiB 2MiB \
                    mkpart '" "' $fs 2MiB -$installer_part_size \
                    mkpart '" "' ext4 -$installer_part_size 100% \
                    set 1 bios_grub on
                update_part

                echo                                  #1 bios_boot
                echo                                  #2 os 用目标系统的格式化工具
                mkfs.ext4 -F -L installer /dev/$xda*3 #3 installer
            fi
        else
            # 使用 dd qcow2
            # fedora debian opensuse arch gentoo
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' ext4 1MiB -$installer_part_size \
                mkpart '" "' ext4 -$installer_part_size 100%
            update_part

            mkfs.ext4 -F -L os /dev/$xda*1        #1 os
            mkfs.ext4 -F -L installer /dev/$xda*2 #2 installer
        fi
    elif [ "$distro" = alpine ] || [ "$distro" = arch ] || [ "$distro" = gentoo ] ||
        [ "$distro" = nixos ] || [ "$distro" = aosc ]; then
        # alpine 本身关闭了 64bit ext4
        # https://gitlab.alpinelinux.org/alpine/alpine-conf/-/blob/3.18.1/setup-disk.in?ref_type=tags#L908
        # 而且 alpine 的 extlinux 不兼容 64bit ext4
        [ "$distro" = alpine ] && ext4_opts="-O ^64bit" || ext4_opts=
        if is_efi; then
            # efi
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' fat32 1MiB 101MiB \
                mkpart '" "' ext4 101MiB 100% \
                set 1 boot on
            update_part

            mkfs.fat /dev/$xda*1                #1 efi
            mkfs.ext4 -F $ext4_opts /dev/$xda*2 #2 os
        elif is_xda_gt_2t; then
            # bios > 2t
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' ext4 1MiB 2MiB \
                mkpart '" "' ext4 2MiB 100% \
                set 1 bios_grub on
            update_part

            echo                                #1 bios_boot
            mkfs.ext4 -F $ext4_opts /dev/$xda*2 #2 os
        else
            # bios
            parted /dev/$xda -s -- \
                mklabel msdos \
                mkpart primary ext4 1MiB 100% \
                set 1 boot on
            update_part

            mkfs.ext4 -F $ext4_opts /dev/$xda*1 #1 os
        fi
    else
        # 安装红帽系或ubuntu
        # 对于红帽系是临时分区表，安装时除了 installer 分区，其他分区会重建为默认的大小
        # 对于ubuntu是最终分区表，因为 ubuntu 的安装器不能调整个别分区，只能重建整个分区表
        # installer 2g分区用fat格式刚好塞得下ubuntu-22.04.3 iso，而ext4塞不下或者需要改参数
        if [ "$distro" = ubuntu ]; then
            if ! size_bytes=$(get_http_file_size "$iso"); then
                # 默认值，假设 iso 3g
                size_bytes=$((3 * 1024 * 1024 * 1024))
            fi
            installer_part_size="$(get_part_size_mb_for_file_size_b $size_bytes)MiB"
        else
            # redhat
            installer_part_size=2GiB
        fi

        # centos 7 无法加载alpine格式化的ext4
        # 要关闭这个属性
        ext4_opts="-O ^metadata_csum"
        apk add dosfstools

        if is_efi; then
            # efi
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' fat32 1MiB 1025MiB \
                mkpart '" "' ext4 1025MiB -$installer_part_size \
                mkpart '" "' ext4 -$installer_part_size 100% \
                set 1 boot on
            update_part

            mkfs.fat -n efi /dev/$xda*1                      #1 efi
            mkfs.ext4 -F -L os /dev/$xda*2                   #2 os
            mkfs.ext4 -F -L installer $ext4_opts /dev/$xda*3 #2 installer
        elif is_xda_gt_2t; then
            # bios > 2t
            parted /dev/$xda -s -- \
                mklabel gpt \
                mkpart '" "' ext4 1MiB 2MiB \
                mkpart '" "' ext4 2MiB -$installer_part_size \
                mkpart '" "' ext4 -$installer_part_size 100% \
                set 1 bios_grub on
            update_part

            echo                                             #1 bios_boot
            mkfs.ext4 -F -L os /dev/$xda*2                   #2 os
            mkfs.ext4 -F -L installer $ext4_opts /dev/$xda*3 #3 installer
        else
            # bios
            parted /dev/$xda -s -- \
                mklabel msdos \
                mkpart primary ext4 1MiB -$installer_part_size \
                mkpart primary ext4 -$installer_part_size 100% \
                set 1 boot on
            update_part

            mkfs.ext4 -F -L os /dev/$xda*1                   #1 os
            mkfs.ext4 -F -L installer $ext4_opts /dev/$xda*2 #2 installer
        fi
        update_part
    fi

    update_part

    # alpine 删除分区工具，防止 256M 小机爆内存
    # setup-disk /dev/sda 会保留格式化工具，我们也保留
    if [ "$distro" = alpine ]; then
        apk del parted
    fi
}

umount_pseudo_fs() {
    os_dir=$(realpath "$1")

    dirs="/proc /sys /dev /run"
    regex=$(echo "$dirs" | sed 's, ,|,g')
    if mounts=$(mount | grep -Ew "on $os_dir($regex)" | awk '{print $3}' | tac); then
        for mount in $mounts; do
            echo "umount $mount"
            umount $mount
        done
    fi
}

mount_pseudo_fs() {
    os_dir=$1

    mkdir -p $os_dir/proc/ $os_dir/sys/ $os_dir/dev/ $os_dir/run/

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
    recognize_static6=${2:-true}
    recognize_ipv6_types=${3:-true}

    info "Create Cloud-init network config"

    # 防止文件未创建
    mkdir -p "$(dirname "$ci_file")"
    touch "$ci_file"

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
           .network.config[$config_id].mac_address=(\"$mac_addr\" | . style=\"single\")
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
            # https://github.com/canonical/cloud-init/commit/1b8030e0c7fd6fbff7e38ad1e3e6266ae50c83a5
            for cur in $(get_current_dns 4); do
                yq -i ".network.config[$config_id].subnets[$subnet_id].dns_nameservers += [\"$cur\"]" $ci_file
            done
            subnet_id=$((subnet_id + 1))
        fi

        # ipv6
        # slaac:  ipv6_slaac
        # └─enable_other_flag: ipv6_dhcpv6-stateless
        # dhcpv6: ipv6_dhcpv6-stateful

        # ipv6
        if is_slaac; then
            if $recognize_ipv6_types; then
                if is_enable_other_flag; then
                    type=ipv6_dhcpv6-stateless
                else
                    type=ipv6_slaac
                fi
            else
                type=dhcp6
            fi
            yq -i ".network.config[$config_id].subnets[$subnet_id] = {\"type\": \"$type\"}" $ci_file

        elif is_dhcpv6; then
            if $recognize_ipv6_types; then
                type=ipv6_dhcpv6-stateful
            else
                type=dhcp6
            fi
            yq -i ".network.config[$config_id].subnets[$subnet_id] = {\"type\": \"$type\"}" $ci_file

        elif is_staticv6; then
            get_netconf_to ipv6_addr
            get_netconf_to ipv6_gateway
            if $recognize_static6; then
                type_ipv6_static=static6
            else
                type_ipv6_static=static
            fi
            yq -i ".network.config[$config_id].subnets[$subnet_id] = {
                    \"type\": \"$type_ipv6_static\",
                    \"address\": \"$ipv6_addr\",
                    \"gateway\": \"$ipv6_gateway\" }
                    " $ci_file
        fi
        # 无法设置 autoconf = false ?
        if should_disable_accept_ra; then
            yq -i ".network.config[$config_id].accept-ra = false" $ci_file
        fi

        # 有 ipv6 但需设置 dns 的情况
        if is_need_manual_set_dnsv6; then
            need_set_dns6=true
            for cur in $(get_current_dns 6); do
                yq -i ".network.config[$config_id].subnets[$subnet_id].dns_nameservers += [\"$cur\"]" $ci_file
            done
        fi

        config_id=$((config_id + 1))
    done

    if $need_set_dns4 || $need_set_dns6; then
        yq -i ".network.config[$config_id].type=\"nameserver\"" $ci_file
        if $need_set_dns4; then
            for cur in $(get_current_dns 4); do
                yq -i ".network.config[$config_id].address += [\"$cur\"]" $ci_file
            done
        fi
        if $need_set_dns6; then
            for cur in $(get_current_dns 6); do
                yq -i ".network.config[$config_id].address += [\"$cur\"]" $ci_file
            done
        fi
        # 如果 network.config[$config_id] 没有 address，则删除，避免低版本 cloud-init 报错
        yq -i "del(.network.config[$config_id] | select(has(\"address\") | not))" $ci_file
    fi

    apk del "$(get_yq_name)"

    # 查看文件
    info "Cloud-init network config"
    cat -n $ci_file >&2
}

# 实测没用，生成的 machine-id 是固定的
# 而且 lightsail centos 9 模板 machine-id 也是相同的，显然相同 id 不是个问题
clear_machine_id() {
    os_dir=$1

    # https://www.freedesktop.org/software/systemd/man/latest/machine-id.html
    # gentoo 不会自动创建该文件
    echo uninitialized >$os_dir/etc/machine-id

    # https://build.opensuse.org/projects/Virtualization:Appliances:Images:openSUSE-Leap-15.5/packages/kiwi-templates-Minimal/files/config.sh?expand=1
    rm -f $os_dir/var/lib/systemd/random-seed
}

# 注意 anolis 7 有这个文件，可能干扰我们的配置?
# /etc/cloud/cloud.cfg.d/aliyun_cloud.cfg -> /sys/firmware/qemu_fw_cfg/by_name/etc/cloud-init/vendor-data/raw
download_cloud_init_config() {
    os_dir=$1
    recognize_static6=$2
    recognize_ipv6_types=$3

    ci_file=$os_dir/etc/cloud/cloud.cfg.d/99_fallback.cfg
    download $confhome/cloud-init.yaml $ci_file
    # 删除注释行，除了第一行
    sed -i '1!{/^[[:space:]]*#/d}' $ci_file

    # 修改密码
    # 不能用 sed 替换，因为含有特殊字符
    content=$(cat $ci_file)
    echo "${content//@PASSWORD@/$(get_password_linux_sha512)}" >$ci_file

    # 修改 ssh 端口
    if is_need_change_ssh_port; then
        sed -i "s/@SSH_PORT@/$ssh_port/g" $ci_file
    else
        sed -i "/@SSH_PORT@/d" $ci_file
    fi

    # swapfile
    # 如果分区表中已经有swapfile就跳过，例如arch
    if ! grep -w swap $os_dir/etc/fstab; then
        cat <<EOF >>$ci_file
swap:
  filename: /swapfile
  size: auto
EOF
    fi

    create_cloud_init_network_config "$ci_file" "$recognize_static6" "$recognize_ipv6_types"
}

get_image_state() {
    local os_dir=$1
    local image_state=

    # 如果 dd 镜像精简了 State.ini，则从注册表获取
    if state_ini=$(find_file_ignore_case $os_dir/Windows/Setup/State/State.ini); then
        image_state=$(grep -i '^ImageState=' $state_ini | cut -d= -f2 | tr -d '\r')
    fi
    if [ -z "$image_state" ]; then
        apk add hivex
        hive=$(find_file_ignore_case $os_dir/Windows/System32/config/SOFTWARE)
        image_state=$(hivexget $hive '\Microsoft\Windows\CurrentVersion\Setup\State' ImageState)
        apk del hivex
    fi

    if [ -n "$image_state" ]; then
        echo "$image_state"
    else
        error_and_exit "Cannot get ImageState."
    fi
}

modify_windows() {
    os_dir=$1
    info "Modify Windows"

    # https://learn.microsoft.com/windows-hardware/manufacture/desktop/windows-setup-states
    # https://learn.microsoft.com/troubleshoot/azure/virtual-machines/reset-local-password-without-agent
    # https://learn.microsoft.com/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup

    # 判断用 SetupComplete 还是组策略
    image_state=$(get_image_state "$os_dir")
    echo "ImageState: $image_state"

    if [ "$image_state" = IMAGE_STATE_COMPLETE ]; then
        use_gpo=true
    else
        use_gpo=false
    fi

    # bat 列表
    bats=

    # 1. rdp 端口
    if is_need_change_rdp_port; then
        create_win_change_rdp_port_script $os_dir/windows-change-rdp-port.bat "$rdp_port"
        bats="$bats windows-change-rdp-port.bat"
    fi

    # 2. 允许 ping
    if is_allow_ping; then
        download $confhome/windows-allow-ping.bat $os_dir/windows-allow-ping.bat
        bats="$bats windows-allow-ping.bat"
    fi

    # 3. 合并分区
    # 可能 unattend.xml 已经设置了ExtendOSPartition，不过运行resize没副作用
    download $confhome/windows-resize.bat $os_dir/windows-resize.bat
    bats="$bats windows-resize.bat"

    # 4. 网络设置
    for ethx in $(get_eths); do
        create_win_set_netconf_script $os_dir/windows-set-netconf-$ethx.bat
        bats="$bats windows-set-netconf-$ethx.bat"
    done

    # 5 frp
    if [ -s /configs/frpc.toml ]; then
        # 好像 win7 无法运行 frpc，暂时不管
        windows_arch=$(get_windows_arch_from_windows_drive "$os_dir" | to_lower)
        if [ "$windows_arch" = amd64 ] || [ "$windows_arch" = arm64 ]; then
            mkdir -p "$os_dir/frpc/"
            url=$(get_frpc_url windows "$nt_ver")
            download "$url" $os_dir/frpc/frpc.zip
            # -j 去除文件夹
            # -C 筛选文件时不区分大小写，但 busybox zip 不支持
            unzip -o -j "$os_dir/frpc/frpc.zip" '*/frpc.exe' -d "$os_dir/frpc/"
            rm -f "$os_dir/frpc/frpc.zip"
            cp -f /configs/frpc.toml "$os_dir/frpc/frpc.toml"
            download "$confhome/windows-frpc.xml" "$os_dir/frpc/frpc.xml"
            download "$confhome/windows-frpc.bat" "$os_dir/frpc/frpc.bat"
            bats="$bats frpc\frpc.bat"
        else
            warn "$windows_arch Not Support frpc"
        fi
    fi

    if $use_gpo; then
        # 使用组策略
        scripts_ini=$(get_path_in_correct_case $os_dir/Windows/System32/GroupPolicy/Machine/Scripts/scripts.ini)
        mkdir -p "$(dirname $scripts_ini)"
        gpt_ini=$(get_path_in_correct_case $os_dir/Windows/System32/GroupPolicy/gpt.ini)

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
        setup_complete=$(get_path_in_correct_case $os_dir/Windows/Setup/Scripts/SetupComplete.cmd)
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

        # 查看最终内容
        cat -n $setup_complete
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

keep_now_resolv_conf() {
    os_dir=$1
    rm -f $os_dir/etc/resolv.conf.orig
}

# 抄 https://github.com/alpinelinux/alpine-conf/blob/3.18.1/setup-disk.in#L421
get_alpine_firmware_pkgs() {
    # 需要有 modloop，不然 modinfo 会报错
    ensure_service_started modloop >&2

    # 如果不在单独的文件夹，则用 linux-firmware-other
    # 如果在单独的文件夹，则用 linux-firmware-xxx
    # 如果不需要 firmware，则用 linux-firmware-none
    firmware_pkgs=$(
        cd /sys/module && modinfo -F firmware -- * 2>/dev/null |
            awk -F/ '{print $1 == $0 ? "linux-firmware-other" : "linux-firmware-"$1}' |
            sort -u
    )

    # 使用 command 因为自己覆盖了 apk 添加了 >&2
    retry 5 command apk search --quiet --exact ${firmware_pkgs:-linux-firmware-none}
}

get_ucode_firmware_pkgs() {
    is_virt && return

    case "$distro" in
    centos | almalinux | rocky | oracle | redhat | anolis | opencloudos | openeuler) os=elol ;;
    *) os=$distro ;;
    esac

    case "$os-$(get_cpu_vendor)" in
    # alpine 的 linux-firmware 以文件夹进行拆分
    # setup-alpine 会自动安装需要的 firmware（modloop 没挂载则无效）
    # https://github.com/alpinelinux/alpine-conf/blob/3.18.1/setup-disk.in#L421
    alpine-intel) echo intel-ucode ;;
    alpine-amd) echo amd-ucode ;;
    alpine-*) ;;

    debian-intel) echo firmware-linux intel-microcode ;;
    debian-amd) echo firmware-linux amd64-microcode ;;
    debian-*) echo firmware-linux ;;

    ubuntu-intel) echo linux-firmware intel-microcode ;;
    ubuntu-amd) echo linux-firmware amd64-microcode ;;
    ubuntu-*) echo linux-firmware ;;

    # 无法同时安装 kernel-firmware kernel-firmware-intel
    opensuse-intel) echo kernel-firmware ucode-intel ;;
    opensuse-amd) echo kernel-firmware ucode-amd ;;
    opensuse-*) echo kernel-firmware ;;

    arch-intel) echo linux-firmware intel-ucode ;;
    arch-amd) echo linux-firmware amd-ucode ;;
    arch-*) echo linux-firmware ;;

    gentoo-intel) echo linux-firmware intel-microcode ;;
    gentoo-amd) echo linux-firmware ;;
    gentoo-*) echo linux-firmware ;;

    nixos-intel) echo linux-firmware microcodeIntel ;;
    nixos-amd) echo linux-firmware microcodeAmd ;;
    nixos-*) echo linux-firmware ;;

    fedora-intel) echo linux-firmware microcode_ctl ;;
    fedora-amd) echo linux-firmware amd-ucode-firmware microcode_ctl ;;
    fedora-*) echo linux-firmware microcode_ctl ;;

    elol-intel) echo linux-firmware microcode_ctl ;;
    elol-amd) echo linux-firmware microcode_ctl ;;
    elol-*) echo linux-firmware microcode_ctl ;;
    esac
}

chroot_systemctl_disable() {
    os_dir=$1
    shift

    for unit in "$@"; do
        # 如果传进来的是x(没有.) 则改成 x.service
        if ! [[ "$unit" = "*.*" ]]; then
            unit=$i.service
        fi

        # debian 10 返回值始终是 0
        if ! chroot $os_dir systemctl list-unit-files "$unit" 2>&1 | grep -Eq '^0 unit'; then
            chroot $os_dir systemctl disable "$unit"
        fi
    done
}

remove_cloud_init() {
    os_dir=$1

    if ! is_have_cmd_on_disk $os_dir cloud-init; then
        return
    fi

    info "Remove Cloud-Init"

    # 两种方法都可以
    if false && [ -d $os_dir/etc/cloud ]; then
        touch $os_dir/etc/cloud/cloud-init.disabled
    fi

    # systemctl is-enabled cloud-init-hotplugd.service 状态是 static
    # disable 会出现一堆提示信息，也无法 disable
    for unit in $(
        chroot $os_dir systemctl list-unit-files |
            grep -E '^(cloud-init-.*|cloud-config|cloud-final)\.(service|socket)' | grep enabled | awk '{print $1}'
    ); do
        # 服务不存在时会报错
        if chroot $os_dir systemctl -q is-enabled "$unit"; then
            chroot $os_dir systemctl disable "$unit"
        fi
    done

    for pkg_mgr in dnf yum zypper apt-get; do
        if is_have_cmd_on_disk $os_dir $pkg_mgr; then
            case $pkg_mgr in
            dnf | yum)
                chroot $os_dir $pkg_mgr remove -y cloud-init
                rm -f $os_dir/etc/cloud/cloud.cfg.rpmsave
                ;;
            zypper)
                # 加上 -u 才会删除依赖
                chroot $os_dir zypper remove -y -u cloud-init
                ;;
            apt-get)
                # ubuntu 25.04 开始有 cloud-init-base
                chroot_apt_remove $os_dir cloud-init cloud-init-base
                chroot_apt_autoremove $os_dir
                ;;
            esac
            break
        fi
    done
}

disable_jeos_firstboot() {
    os_dir=$1
    info "Disable JeOS Firstboot"

    # 两种方法都可以
    # https://github.com/openSUSE/jeos-firstboot?tab=readme-ov-file#usage

    rm -rf $os_dir/var/lib/YaST2/reconfig_system

    for name in jeos-firstboot jeos-firstboot-snapshot; do
        # 服务不存在时会报错
        chroot $os_dir systemctl disable "$name.service" 2>/dev/null || true
    done
}

create_network_manager_config() {
    source_cfg=$1
    os_dir=$2
    info "Create Network-Manager config"

    # 可以直接用 alpine 的 cloud-init 生成 Network Manager 配置
    apk add cloud-init
    cloud-init devel net-convert -p "$source_cfg" -k yaml -d /out -D alpine -O network-manager

    # 文档明确写了 ipv6.method=dhcp 无法获取网关
    # https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html#:~:text=false/no/off-,ipv6,-.method
    sed -i -e '/^may-fail=/d' -e 's/^method=dhcp/method=auto/' \
        /out/etc/NetworkManager/system-connections/cloud-init-eth*.nmconnection

    # 删除 # Generated by cloud-init. Changes will be lost.
    # 删除 org.freedesktop.NetworkManager.origin=cloud-init
    # 并删除头部的空行
    sed -i \
        -e '/^# Generated by cloud-init/d' \
        -e '/^org\.freedesktop\.NetworkManager\.origin=cloud-init/d' \
        /out/etc/NetworkManager/system-connections/cloud-init-eth*.nmconnection
    del_head_empty_lines_inplace /out/etc/NetworkManager/system-connections/cloud-init-eth*.nmconnection

    cp /out/etc/NetworkManager/system-connections/cloud-init-eth*.nmconnection \
        $os_dir/etc/NetworkManager/system-connections/

    # 清理
    rm -rf /out
    apk del cloud-init

    # 最终显示文件
    for file in "$os_dir"/etc/NetworkManager/system-connections/cloud-init-eth*.nmconnection; do
        cat -n "$file" >&2
    done
}

modify_linux() {
    os_dir=$1
    info "Modify Linux"

    find_and_mount() {
        mount_point=$1
        mount_dev=$(awk "\$2==\"$mount_point\" {print \$1}" $os_dir/etc/fstab)
        if [ -n "$mount_dev" ]; then
            mount $mount_dev $os_dir$mount_point
        fi
    }

    # 修复 onlink 网关
    add_onlink_script_if_need() {
        for ethx in $(get_eths); do
            if is_staticv4 || is_staticv6; then
                fix_sh=cloud-init-fix-onlink.sh
                download "$confhome/$fix_sh" "$os_dir/$fix_sh"
                insert_into_file "$ci_file" after '^runcmd:' <<EOF
  - bash "/$fix_sh" && rm -f "/$fix_sh"
EOF
                break
            fi
        done
    }

    # 部分镜像有默认配置，例如 centos
    del_exist_sysconfig_NetworkManager_config $os_dir

    # 仅 fedora (el/ol/国产fork 用的是复制文件方法)
    # 1. 禁用 selinux kdump
    # 2. 添加微码+固件
    if [ -f $os_dir/etc/redhat-release ]; then
        # 防止删除 cloud-init / 安装 firmware 时不够内存
        create_swap_if_ram_less_than 2048 $os_dir/swapfile

        find_and_mount /boot
        find_and_mount /boot/efi
        mount_pseudo_fs $os_dir
        cp_resolv_conf $os_dir

        # 可以直接用 alpine 的 cloud-init 生成 Network Manager 配置
        create_cloud_init_network_config /net.cfg
        create_network_manager_config /net.cfg "$os_dir"
        rm /net.cfg

        remove_cloud_init $os_dir

        disable_selinux $os_dir
        disable_kdump $os_dir

        if fw_pkgs=$(get_ucode_firmware_pkgs) && [ -n "$fw_pkgs" ]; then
            is_have_cmd_on_disk $os_dir dnf && mgr=dnf || mgr=yum
            chroot $os_dir $mgr install -y $fw_pkgs
        fi

        restore_resolv_conf $os_dir
    fi

    # debian
    # 1. EOL 换源
    # 2. 修复网络问题
    # 3. 添加微码+固件
    # 注意 ubuntu 也有 /etc/debian_version
    if [ "$distro" = debian ]; then
        # 修复 onlink 网关
        # add_onlink_script_if_need

        mount_pseudo_fs $os_dir
        cp_resolv_conf $os_dir
        find_and_mount /boot
        find_and_mount /boot/efi

        remove_cloud_init $os_dir

        # 获取当前开启的 Components, 后面要用
        if [ -f $os_dir/etc/apt/sources.list.d/debian.sources ]; then
            comps=$(grep ^Components: $os_dir/etc/apt/sources.list.d/debian.sources | head -1 | cut -d' ' -f2-)
        else
            comps=$(grep '^deb ' $os_dir/etc/apt/sources.list | head -1 | cut -d' ' -f4-)
        fi

        # ELTS/CN 源处理
        if is_elts; then
            # ELTS
            wget https://deb.freexian.com/extended-lts/archive-key.gpg \
                -O $os_dir/etc/apt/trusted.gpg.d/freexian-archive-extended-lts.gpg

            codename=$(grep '^VERSION_CODENAME=' $os_dir/etc/os-release | cut -d= -f2)
            # shellcheck disable=SC2154
            if [ -f $os_dir/etc/apt/sources.list.d/debian.sources ]; then
                cat <<EOF >$os_dir/etc/apt/sources.list.d/debian.sources
Types: deb
URIs: http://$deb_mirror
Suites: $codename
Components: $comps
Signed-By: /etc/apt/trusted.gpg.d/freexian-archive-extended-lts.gpg
EOF
            else
                echo "deb http://$deb_mirror $codename $comps" >$os_dir/etc/apt/sources.list
            fi
        else
            # non-ELTS
            if is_in_china; then
                # 不处理 security 源 security.debian.org/debian-security 和 /etc/apt/mirrors/debian-security.list
                for file in $os_dir/etc/apt/mirrors/debian.list $os_dir/etc/apt/sources.list; do
                    if [ -f "$file" ]; then
                        sed -i "s|deb\.debian\.org/debian|$deb_mirror|" "$file"
                    fi
                done
            fi
        fi

        # 标记所有内核为自动安装
        pkgs=$(chroot $os_dir apt-mark showmanual linux-image* linux-headers*)
        chroot $os_dir apt-mark auto $pkgs

        # 安装合适的内核
        kernel_package=$kernel
        # shellcheck disable=SC2046
        # 检测机器是否能用 cloud 内核
        if [[ "$kernel_package" = 'linux-image-cloud-*' ]] &&
            ! sh /can_use_cloud_kernel.sh "$xda" $(get_eths); then
            kernel_package=$(echo "$kernel_package" | sed 's/-cloud//')
        fi
        # 如果镜像自带内核跟最佳内核是同一种且有更新
        # 则 apt install 只会进行更新，不会将包设置成 manual
        # 需要再运行 apt install 才会将包设置成 manual
        chroot_apt_install $os_dir "$kernel_package"
        chroot_apt_install $os_dir "$kernel_package"

        # 使用 autoremove 删除非最佳内核
        chroot_apt_autoremove $os_dir

        # 微码+固件
        if fw_pkgs=$(get_ucode_firmware_pkgs) && [ -n "$fw_pkgs" ]; then
            #  debian 10 11 的 iucode-tool 在 contrib 里面
            #  debian 12 的 iucode-tool 在 main 里面
            [ "$releasever" -ge 12 ] &&
                comps_to_add=non-free-firmware ||
                comps_to_add="contrib non-free"

            if [ -f $os_dir/etc/apt/sources.list.d/debian.sources ]; then
                file=$os_dir/etc/apt/sources.list.d/debian.sources
                search='^[# ]*Components:'
            else
                file=$os_dir/etc/apt/sources.list
                search='^[# ]*deb'
            fi

            for c in $comps_to_add; do
                if ! echo "$comps" | grep -wq "$c"; then
                    sed -Ei "/$search/s/$/ $c/" $file
                fi
            done

            chroot_apt_install $os_dir $fw_pkgs
        fi

        # genericcloud 删除以下文件开机时才会显示 grub 菜单
        # https://salsa.debian.org/cloud-team/debian-cloud-images/-/tree/master/config_space/bookworm/files/etc/default/grub.d
        rm -f $os_dir/etc/default/grub.d/10_cloud.cfg
        rm -f $os_dir/etc/default/grub.d/15_timeout.cfg
        chroot $os_dir update-grub

        if true; then
            # 如果使用 nocloud 镜像
            chroot_apt_install $os_dir openssh-server
        else
            # 如果使用 genericcloud 镜像

            # 还原默认配置并创建 key
            # cat $os_dir/usr/share/openssh/sshd_config $os_dir/etc/ssh/sshd_config
            # chroot $os_dir ssh-keygen -A
            rm -rf $os_dir/etc/ssh/sshd_config
            UCF_FORCE_CONFFMISS=1 chroot $os_dir dpkg-reconfigure openssh-server
        fi

        # 镜像自带的网络管理器
        # debian 11 ifupdown
        # debian 12 netplan + networkd + resolved
        # ifupdown dhcp 不支持 24位掩码+不规则网关?

        # 强制使用 netplan
        if false && is_have_cmd_on_disk $os_dir netplan; then
            chroot_apt_install $os_dir netplan.io
            # 服务不存在时会报错
            chroot $os_dir systemctl disable networking resolvconf 2>/dev/null || true
            chroot $os_dir systemctl enable systemd-networkd systemd-resolved
            rm_resolv_conf $os_dir
            ln -sf ../run/systemd/resolve/stub-resolv.conf $os_dir/etc/resolv.conf
            if [ -f "$os_dir/etc/cloud/cloud.cfg.d/99_fallback.cfg" ]; then
                insert_into_file $os_dir/etc/cloud/cloud.cfg.d/99_fallback.cfg after '#cloud-config' <<EOF
system_info:
  network:
    renderers: [netplan]
    activators: [netplan]
EOF
            fi
        fi

        create_ifupdown_config $os_dir/etc/network/interfaces

        # ifupdown 不支持 rdnss
        # 但 iso 安装不会安装 rdnssd，而是在安装时读取 rdnss 并写入 resolv.conf
        if false; then
            chroot_apt_install $os_dir rdnssd
        fi

        # debian 10 11 云镜像安装了 resolvconf
        # debian 12 云镜像安装了 netplan systemd-resolved
        # 云镜像用了 cloud-init 自动配置网络，用户是无感的，因此官方云镜像可以随便选择网络管理器
        # 但我们的系统安装后用户可能有手动配置网络的需求，因此用回 iso 安装时的网络管理器 ifupdown

        # 服务不存在时会报错
        chroot $os_dir systemctl disable resolvconf systemd-networkd systemd-resolved 2>/dev/null || true

        chroot_apt_install $os_dir ifupdown
        chroot_apt_remove $os_dir resolvconf netplan.io systemd-resolved
        chroot_apt_autoremove $os_dir
        chroot $os_dir systemctl enable networking

        # 静态时 networking 服务不会根据 /etc/network/interfaces 更新 resolv.conf
        # 动态时使用了 isc-dhcp-client 支持自动更新 resolv.conf
        # 另外 debian iso 不会安装 rdnssd
        keep_now_resolv_conf $os_dir
    fi

    # opensuse
    # 1. kernel-default-base 缺少 nvme 驱动，换成 kernel-default
    # 2. 添加微码+固件
    # https://documentation.suse.com/smart/virtualization-cloud/html/minimal-vm/index.html
    if grep -q opensuse $os_dir/etc/os-release; then
        create_swap_if_ram_less_than 1024 $os_dir/swapfile
        mount_pseudo_fs $os_dir
        cp_resolv_conf $os_dir
        find_and_mount /boot
        find_and_mount /boot/efi

        disable_jeos_firstboot $os_dir

        # 16.0 需要安装 openssh
        if ! chroot $os_dir rpm -qi openssh-server; then
            chroot $os_dir zypper install -y openssh-server
        fi

        # 禁用 selinux
        disable_selinux $os_dir

        # opensuse leap 15.6 用 wicked
        # opensuse leap 16.0 / tumbleweed 用 NetworkManager
        if chroot $os_dir rpm -qi wicked; then
            # sysconfig ifcfg
            create_cloud_init_network_config $os_dir/net.cfg
            chroot $os_dir cloud-init devel net-convert \
                -p /net.cfg -k yaml -d out -D opensuse -O sysconfig

            # 删除
            # Created by cloud-init on instance boot automatically, do not edit.
            #
            sed -i '/^#/d' "$os_dir/out/etc/sysconfig/network/ifcfg-eth"*

            for ethx in $(get_eths); do
                # 1. 修复甲骨文云重启后 ipv6 丢失
                # https://github.com/openSUSE/wicked/issues/1058
                # 还要注意 wicked dhcpv6 获取到的 ipv6 是 /64，其他 DHCPv6 程序获取到的是 /128
                echo DHCLIENT6_USE_LAST_LEASE=no >>$os_dir/out/etc/sysconfig/network/ifcfg-$ethx

                # 2. 修复 onlink 网关
                for prefix in '' 'default '; do
                    if is_staticv4; then
                        get_netconf_to ipv4_gateway
                        echo "${prefix}${ipv4_gateway} - -" >>$os_dir/out/etc/sysconfig/network/ifroute-$ethx
                    fi
                    if is_staticv6; then
                        get_netconf_to ipv6_gateway
                        echo "${prefix}${ipv6_gateway} - -" >>$os_dir/out/etc/sysconfig/network/ifroute-$ethx
                    fi
                done
            done

            # 复制配置
            for file in \
                "$os_dir/out/etc/sysconfig/network/ifcfg-eth"* \
                "$os_dir/out/etc/sysconfig/network/ifroute-eth"*; do
                # 动态 ip 没有 ifroute-eth*
                if [ -f $file ]; then
                    cp $file $os_dir/etc/sysconfig/network/
                fi
            done

            # 清理
            rm -rf $os_dir/net.cfg $os_dir/out

        else
            # 如果使用 cloud-init 则需要 touch NetworkManager.conf
            # 更新到 cloud-init 24.1 后删除
            # touch $os_dir/etc/NetworkManager/NetworkManager.conf

            # 可以直接用 alpine 的 cloud-init 生成 Network Manager 配置
            create_cloud_init_network_config /net.cfg
            create_network_manager_config /net.cfg "$os_dir"
            rm /net.cfg
        fi

        # 选择新内核
        # 只有 leap 有 kernel-azure
        if grep -iq leap $os_dir/etc/os-release && [ "$(get_cloud_vendor)" = azure ]; then
            target_kernel='kernel-azure'
        else
            target_kernel='kernel-default'
        fi

        # rpm -qi 不支持通配符
        installed_kernel=$(chroot $os_dir rpm -qa 'kernel-*' --qf '%{NAME}\n' | grep -v firmware)
        if ! [ "$(echo "$installed_kernel" | wc -l)" -eq 1 ]; then
            error_and_exit "Unexpected kernel installed: $installed_kernel"
        fi

        # 15.6 / tumbleweed 自带的是 kernel-default-base
        # 16.0 自带的是 kernel-default
        # 不能同时装 kernel-default-base 和 kernel-default

        if ! [ "$installed_kernel" = "$target_kernel" ]; then
            chroot $os_dir zypper remove -y -u $installed_kernel

            # x86 必须设置一个密码，否则报错，arm 没有这个问题
            # Failed to get root password hash
            # Failed to import /etc/uefi/certs/76B6A6A0.crt
            # warning: %post(kernel-default-5.14.21-150500.55.83.1.x86_64) scriptlet failed, exit status 255
            if grep -q '^root:[:!*]' $os_dir/etc/shadow; then
                echo "root:$(mkpasswd '')" | chroot $os_dir chpasswd -e
                chroot $os_dir zypper install -y $target_kernel
                chroot $os_dir passwd -d root
            else
                chroot $os_dir zypper install -y $target_kernel
            fi
        fi

        # 固件+微码
        if fw_pkgs=$(get_ucode_firmware_pkgs) && [ -n "$fw_pkgs" ]; then
            chroot $os_dir zypper install -y $fw_pkgs
        fi

        # 最后才删除 cloud-init
        # 因为生成 sysconfig 网络配置要用目标系统的 cloud-init
        remove_cloud_init $os_dir

        restore_resolv_conf $os_dir
    fi

    # arch 云镜像
    if false && [ -f $os_dir/etc/arch-release ]; then
        # 修复 onlink 网关
        add_onlink_script_if_need

        # 同步证书
        cp_resolv_conf $os_dir
        mount_pseudo_fs $os_dir
        chroot $os_dir pacman-key --init
        chroot $os_dir pacman-key --populate
        rm_resolv_conf $os_dir
    fi

    # gentoo 云镜像
    if false && [ -f $os_dir/etc/gentoo-release ]; then
        # 挂载伪文件系统
        mount_pseudo_fs $os_dir
        cp_resolv_conf $os_dir

        # 在这里修改密码，而不是用cloud-init，因为我们的默认密码太弱
        is_password_plaintext && sed -i 's/enforce=everyone/enforce=none/' $os_dir/etc/security/passwdqc.conf
        change_root_password $os_dir
        is_password_plaintext && sed -i 's/enforce=none/enforce=everyone/' $os_dir/etc/security/passwdqc.conf

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

    basic_init $os_dir

    # 应该在这里是否运行了 basic_init 和创建了网络配置文件
    # 如果没有，则使用 cloud-init

    # 查看 cloud-init 最终配置
    if [ -f "$ci_file" ]; then
        cat -n "$ci_file"
    fi

    # 删除 swap
    swapoff -a
    rm -f $os_dir/swapfile
}

modify_os_on_disk() {
    only_process=$1
    info "Modify disk if is $only_process"

    update_part

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
                # shellcheck disable=SC1090
                # find_file_ignore_case 也在这个文件里面
                . <(wget -O- $confhome/windows-driver-utils.sh)
                if ntoskrnl_exe=$(find_file_ignore_case /os/Windows/System32/ntoskrnl.exe 2>/dev/null); then
                    # 其他地方会用到
                    is_windows() { true; }
                    # 重新挂载为读写、忽略大小写
                    umount /os
                    if ! { mount -t ntfs3 -o nocase,rw /dev/$part /os &&
                        mount | grep -w 'on /os type' | grep -wq rw; }; then
                        # 显示警告
                        warn "Can't normally mount windows partition /dev/$part as rw."
                        dmesg | grep -F "ntfs3($part):" || true
                        # 有可能 fallback 挂载成 ro, 因此先取消挂载
                        if mount | grep -wq 'on /os type'; then
                            umount /os
                        fi
                        # 尝试修复并强制挂载
                        apk add ntfs-3g-progs
                        ntfsfix /dev/$part
                        apk del ntfs-3g-progs
                        mount -t ntfs3 -o nocase,rw,force /dev/$part /os
                    fi
                    # 获取版本号，其他地方会用到
                    get_windows_version_from_dll "$ntoskrnl_exe"
                    modify_windows /os
                    return
                fi
            fi
            umount /os
        fi
    done
    error_and_exit "Can't find os partition."
}

get_need_swap_size() {
    need_ram=$1
    phy_ram=$(get_approximate_ram_size)

    if [ $need_ram -gt $phy_ram ]; then
        echo $((need_ram - phy_ram))
    else
        echo 0
    fi
}

create_swap_if_ram_less_than() {
    need_ram=$1
    swapfile=$2

    swapsize=$(get_need_swap_size $need_ram)
    if [ $swapsize -gt 0 ]; then
        create_swap $swapsize $swapfile
    fi
}

create_swap() {
    swapsize=$1
    swapfile=$2

    if ! grep $swapfile /proc/swaps; then
        # 用兼容 btrfs 的方式创建 swapfile
        truncate -s 0 $swapfile
        # 如果分区不支持 chattr +C 会显示错误但返回值是 0
        chattr +C $swapfile 2>/dev/null
        fallocate -l ${swapsize}M $swapfile
        chmod 0600 $swapfile
        mkswap $swapfile
        swapon $swapfile
    fi
}

set_ssh_keys_and_del_password() {
    os_dir=$1
    info 'set ssh keys'

    # 添加公钥
    (
        umask 077
        mkdir -p $os_dir/root/.ssh
        cat /configs/ssh_keys >$os_dir/root/.ssh/authorized_keys
    )

    # 删除密码
    chroot $os_dir passwd -d root
}

# 除了 alpine 都会用到
change_ssh_conf() {
    os_dir=$1
    key=$2
    value=$3
    sub_conf=$4

    if line="^$key .*" && grep -Exq "$line" $os_dir/etc/ssh/sshd_config; then
        # 如果 sshd_config 存在此 key（非注释状态），则替换
        sed -Ei "s/$line/$key $value/" $os_dir/etc/ssh/sshd_config
    elif {
        # arch 没有 /etc/ssh/sshd_config.d/ 文件夹
        # opensuse tumbleweed 没有 /etc/ssh/sshd_config
        #                       有 /etc/ssh/sshd_config.d/ 文件夹
        #                       有 /usr/etc/ssh/sshd_config
        grep -q 'Include.*/etc/ssh/sshd_config.d' $os_dir/etc/ssh/sshd_config ||
            grep -q '^Include.*/etc/ssh/sshd_config.d/' $os_dir/usr/etc/ssh/sshd_config
    } 2>/dev/null; then
        mkdir -p $os_dir/etc/ssh/sshd_config.d/
        echo "$key $value" >"$os_dir/etc/ssh/sshd_config.d/$sub_conf"
    else
        # 如果 sshd_config 存在此 key (无论是否已注释)，则替换，包括删除注释
        # 否则追加
        line="^#?$key .*"
        if grep -Exq "$line" $os_dir/etc/ssh/sshd_config; then
            sed -Ei "s/$line/$key $value/" $os_dir/etc/ssh/sshd_config
        else
            echo "$key $value" >>$os_dir/etc/ssh/sshd_config
        fi
    fi
}

allow_password_login() {
    os_dir=$1
    change_ssh_conf "$os_dir" PasswordAuthentication yes 01-PasswordAuthentication.conf
}

allow_root_password_login() {
    os_dir=$1

    change_ssh_conf "$os_dir" PermitRootLogin yes 01-permitrootlogin.conf
}

change_ssh_port() {
    os_dir=$1
    ssh_port=$2

    change_ssh_conf "$os_dir" Port "$ssh_port" 01-change-ssh-port.conf
}

change_root_password() {
    os_dir=$1

    info 'change root password'

    if is_password_plaintext; then
        pam_d=$os_dir/etc/pam.d

        [ -f $pam_d/chpasswd ] && has_pamd_chpasswd=true || has_pamd_chpasswd=false

        if $has_pamd_chpasswd; then
            cp $pam_d/chpasswd $pam_d/chpasswd.orig

            # cat /etc/pam.d/chpasswd
            # @include common-password

            # cat /etc/pam.d/chpasswd
            # #%PAM-1.0
            # auth       include      system-auth
            # account    include      system-auth
            # password   substack     system-auth
            # -password   optional    pam_gnome_keyring.so use_authtok
            # password   substack     postlogin

            # 通过 /etc/pam.d/chpasswd 找到 /etc/pam.d/system-auth 或者 /etc/pam.d/system-auth
            # 再找到有 password 和 pam_unix.so 的行，并删除 use_authtok，写入 /etc/pam.d/chpasswd
            files=$(grep -E '^(password|@include)' $pam_d/chpasswd | awk '{print $NF}' | sort -u)
            for file in $files; do
                if [ -f "$pam_d/$file" ] && line=$(grep ^password "$pam_d/$file" | grep -F pam_unix.so); then
                    echo "$line" | sed 's/use_authtok//' >$pam_d/chpasswd
                    break
                fi
            done
        fi

        # 分两行写，不然遇到错误不会终止
        plaintext=$(get_password_plaintext)
        echo "root:$plaintext" | chroot $os_dir chpasswd

        if $has_pamd_chpasswd; then
            mv $pam_d/chpasswd.orig $pam_d/chpasswd
        fi
    else
        echo "root:$(get_password_linux_sha512)" | chroot $os_dir chpasswd -e
    fi
}

disable_selinux() {
    os_dir=$1

    # https://access.redhat.com/solutions/3176
    # centos7 也建议将 selinux 开关写在 cmdline
    # grep selinux=0 /usr/lib/dracut/modules.d/98selinux/selinux-loadpolicy.sh
    #     warn "To disable selinux, add selinux=0 to the kernel command line."
    if [ -f $os_dir/etc/selinux/config ]; then
        sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' $os_dir/etc/selinux/config
    fi

    # opensuse 没有安装 grubby
    if is_have_cmd_on_disk $os_dir grubby; then
        # grubby 只处理 GRUB_CMDLINE_LINUX，不会处理 GRUB_CMDLINE_LINUX_DEFAULT
        # rocky 的 GRUB_CMDLINE_LINUX_DEFAULT 有 crashkernel=auto
        chroot $os_dir grubby --update-kernel ALL --args selinux=0

        # el7 上面那条 grubby 命令不能设置 /etc/default/grub
        sed -i 's/selinux=1/selinux=0/' $os_dir/etc/default/grub
    else
        # 有可能没有 selinux 参数，但现在的镜像没有这个问题
        # sed -Ei 's/[[:space:]]?(security|selinux|enforcing)=[^ ]*//g' $os_dir/etc/default/grub
        sed -i 's/selinux=1/selinux=0/' $os_dir/etc/default/grub

        # 如果需要用 snapshot 可以用 transactional-update grub.cfg
        chroot $os_dir grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
}

disable_kdump() {
    os_dir=$1

    # grubby 只处理 GRUB_CMDLINE_LINUX，不会处理 GRUB_CMDLINE_LINUX_DEFAULT
    # rocky 的 GRUB_CMDLINE_LINUX_DEFAULT 有 crashkernel=auto

    # 新安装的内核依然有 crashkernel，好像是 bug
    # https://forums.rockylinux.org/t/how-do-i-remove-crashkernel-from-cmdline/13346
    # 验证过程
    # yum remove --oldinstallonly   # 删除旧内核
    # rm -rf /boot/loader/entries/* # 删除启动条目
    # yum reinstall kernel-core     # 重新安装新内核
    # cat /boot/loader/entries/*    # 依然有 crashkernel=1G-4G:192M,4G-64G:256M,64G-:512M

    chroot $os_dir grubby --update-kernel ALL --args crashkernel=no
    # el7 上面那条 grubby 命令不能设置 /etc/default/grub
    sed -i 's/crashkernel=[^ "]*/crashkernel=no/' $os_dir/etc/default/grub
    if chroot $os_dir systemctl -q is-enabled kdump; then
        chroot $os_dir systemctl disable kdump
    fi
}

download_qcow() {
    apk add qemu-img
    info "Download qcow2 image"

    mkdir -p /installer
    mount /dev/disk/by-label/installer /installer

    qcow_file=/installer/cloud_image.qcow2
    if [ -n "$img_type_warp" ]; then
        # 边下载边解压，单线程下载
        # 用官方 wget ，带进度条
        apk add wget
        wget $img -O- | pipe_extract >$qcow_file
    else
        # 多线程下载
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

get_part_size_mb_for_file_size_b() {
    local file_b=$1
    local file_mb=$((file_b / 1024 / 1024))

    # ext4 默认参数下
    #  分区大小   可用大小   利用率
    #  100 MiB      86 MiB   86.0%
    #  200 MiB     177 MiB   88.5%
    #  500 MiB     454 MiB   90.8%
    #  512 MiB     476 MiB   92.9%
    # 1024 MiB     957 MiB   93.4%
    # 2000 MiB    1914 MiB   95.7%
    # 2048 MiB    1929 MiB   94.1% 这里反而下降了
    # 5120 MiB    4938 MiB   96.4%

    # 文件系统大约占用 5% 空间

    # 假设 1929M 的文件，计算得到需要创建 2031M 的分区
    # 但是实测 2048M 的分区才能存放 1929M 的文件
    # 因此预留不足 150M 时补够 150M
    local reserve_mb=$((file_mb * 100 / 95 - file_mb))
    if [ $reserve_mb -lt 150 ]; then
        reserve_mb=150
    fi

    part_mb=$((file_mb + reserve_mb))
    echo "File size:      $file_mb MiB" >&2
    echo "Part size need: $part_mb MiB" >&2
    echo $part_mb
}

get_cloud_image_part_size() {
    # 7
    # https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-2211.qcow2c 400m

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
    # https://rhel-9.4-x86_64-kvm.qcow2 900m

    # 10
    # https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2 900m

    # https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/cloud/nocloud_alpine-3.19.1-x86_64-uefi-cloudinit-r0.qcow2 200m
    # https://kali.download/cloud-images/current/kali-linux-2024.1-cloud-genericcloud-amd64.tar.xz 200m
    # https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2 300m
    # https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.aarch64-Cloud.qcow2 300m
    # https://mirror.fcix.net/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2 400m
    # https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2 500m
    # https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 500m
    # https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img 500m
    # https://gentoo.osuosl.org/experimental/amd64/openstack/gentoo-openstack-amd64-systemd-latest.qcow2 800m

    # openeuler 是 .qcow2.xz，要解压后才知道 qcow2 大小
    if [ "$distro" = openeuler ]; then
        # openeuler 20.03 3g
        if [ "$releasever" = 20.03 ]; then
            echo 3GiB
        else
            echo 2GiB
        fi
    elif size_bytes=$(get_http_file_size "$img"); then
        # 缩小 btrfs 需要写 qcow2 ，实测写入后只多了 1M，因此不用特殊处理
        echo "$(get_part_size_mb_for_file_size_b $size_bytes)MiB"
    else
        # 如果没获取到文件大小
        echo "Could not get cloud image size in http response." >&2
        echo 2GiB
    fi
}

chroot_dnf() {
    if is_have_cmd_on_disk /os/ dnf; then
        chroot /os/ dnf -y "$@"
    else
        chroot /os/ yum -y "$@"
    fi
}

chroot_apt_update() {
    os_dir=$1

    current_hash=$(cat $os_dir/etc/apt/sources.list $os_dir/etc/apt/sources.list.d/*.sources 2>/dev/null | md5sum)
    if ! [ "$saved_hash" = "$current_hash" ]; then
        chroot $os_dir apt-get update
        saved_hash="$current_hash"
    fi
}

chroot_apt_install() {
    os_dir=$1
    shift

    chroot_apt_update $os_dir
    DEBIAN_FRONTEND=noninteractive chroot $os_dir apt-get install -y "$@"
}

chroot_apt_remove() {
    os_dir=$1
    shift

    # minimal 镜像 删除 grub-pc 时会安装 grub-efi-amd64
    # 因此需要先更新索引
    chroot_apt_update $os_dir

    # 不能用 apt remove --purge -y xxx yyy
    # 因为如果索引里没有其中一个，会报错，另一个也不会删除
    local pkgs=
    for pkg in "$@"; do
        # apt list 会提示 WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
        # 但又不能用 apt-get list
        if chroot $os_dir apt list --installed "$pkg" | grep -q installed; then
            pkgs="$pkgs $pkg"
        fi
    done

    # 删除 resolvconf 时会弹出建议重启，因此添加 noninteractive
    DEBIAN_FRONTEND=noninteractive chroot $os_dir apt-get remove --purge --allow-remove-essential -y $pkgs
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
    DEBIAN_FRONTEND=noninteractive chroot $os_dir apt-get autoremove --purge -y
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

is_el7_family() {
    is_have_cmd_on_disk "$1" yum &&
        ! is_have_cmd_on_disk "$1" dnf
}

del_exist_sysconfig_NetworkManager_config() {
    os_dir=$1

    # 删除云镜像自带的 dhcp 配置，防止歧义
    rm -rf $os_dir/etc/NetworkManager/system-connections/*.nmconnection
    rm -rf $os_dir/etc/sysconfig/network-scripts/ifcfg-*

    # 1. 修复 cloud-init 添加了 IPV*_FAILURE_FATAL / may-fail=false
    #    甲骨文 dhcpv6 获取不到 IP 将视为 fatal，原有的 ipv4 地址也会被删除
    # 2. 修复 dhcpv6 下，ifcfg 添加了 IPV6_AUTOCONF=no 导致无法获取网关
    # 3. 修复 dhcpv6 下，NM method=dhcp 导致无法获取网关
    if false; then
        ci_file=$os_dir/etc/cloud/cloud.cfg.d/99_fallback.cfg

        insert_into_file $ci_file after '^runcmd:' <<EOF
  - sed -i '/^IPV[46]_FAILURE_FATAL=/d' /etc/sysconfig/network-scripts/ifcfg-* || true
  - sed -i '/^may-fail=/d' /etc/NetworkManager/system-connections/*.nmconnection || true
  - for f in /etc/sysconfig/network-scripts/ifcfg-*; do grep -q '^DHCPV6C=yes' "\$f" && sed -i '/^IPV6_AUTOCONF=no/d' "\$f"; done
  - sed -i 's/^method=dhcp/method=auto/' /etc/NetworkManager/system-connections/*.nmconnection || true
  - systemctl is-enabled NetworkManager && systemctl restart NetworkManager || true
EOF
    fi
}

install_fnos() {
    info "Install fnos"
    os_dir=/os

    # 官方安装调用流程
    # /etc/init.d/run_install.sh > trim-install > trim-grub

    # 挂载 /os
    mkdir -p /os
    mount /dev/$xda*2 /os

    # 下载并挂载 iso
    mkdir -p /os/installer /iso
    download "$iso" /os/installer/fnos.iso
    mount -o ro /os/installer/fnos.iso /iso

    # 解压 initrd
    apk add cpio
    initrd_dir=/os/installer/initrd_dir
    mkdir -p $initrd_dir
    (
        cd $initrd_dir
        zcat /iso/install.amd/initrd.gz | cpio -idm
    )
    apk del cpio

    # 获取挂载参数
    fstab_line_os=$(strings $initrd_dir/trim-install | grep -m1 '^UUID=%s / ')
    fstab_line_efi=$(strings $initrd_dir/trim-install | grep -m1 '^UUID=%s /boot/efi ')
    fstab_line_swapfile=$(strings $initrd_dir/trim-install | grep -m1 '^/swapfile none swap ')

    # 删除 initrd
    rm -rf $initrd_dir

    # 复制 trimfs.tgz 并删除 ISO 以获得更多空间
    echo "moving trimfs.tgz..."
    cp /iso/trimfs.tgz /os/installer
    umount /iso
    rm /os/installer/fnos.iso

    # 挂载 /os/boot/efi
    if is_efi; then
        mkdir -p /os/boot/efi
        mount -o "$(echo "$fstab_line_efi" | awk '{print $4}')" /dev/$xda*1 /os/boot/efi
    fi

    # 复制系统
    info "Extract fnos"
    apk add tar gzip pv
    pv -f /os/installer/trimfs.tgz | tar zxp --numeric-owner --xattrs-include='*.*' -C /os
    apk del tar gzip pv

    # 删除 installer (trimfs.tgz)
    rm -rf /os/installer

    # 挂载 proc sys dev
    mount_pseudo_fs /os

    # 更新 initrd
    # chroot $os_dir update-initramfs -u

    # 更改密码
    if is_need_set_ssh_keys; then
        set_ssh_keys_and_del_password $os_dir
    else
        change_root_password $os_dir
    fi

    # ssh root 登录，测试用
    if false; then
        allow_root_password_login $os_dir
        chroot $os_dir systemctl enable ssh
    fi

    # grub
    if is_efi; then
        chroot $os_dir grub-install --efi-directory=/boot/efi
        chroot $os_dir grub-install --efi-directory=/boot/efi --removable
    else
        chroot $os_dir grub-install /dev/$xda
    fi

    # grub tty
    ttys_cmdline=$(get_ttys console=)
    echo GRUB_CMDLINE_LINUX=\"\$GRUB_CMDLINE_LINUX $ttys_cmdline\" \
        >>$os_dir/etc/default/grub.d/tty.cfg
    chroot $os_dir update-grub

    # fstab
    {
        # /
        uuid=$(lsblk /dev/$xda*2 -no UUID)
        echo "$fstab_line_os" | sed "s/%s/$uuid/"

        # 官方安装器即使 swapfile 设为 0 也会有这行
        echo "$fstab_line_swapfile" | sed "s/%s/$uuid/"

        # /boot/efi
        if is_efi; then
            uuid=$(lsblk /dev/$xda*1 -no UUID)
            echo "$fstab_line_efi" | sed "s/%s/$uuid/"
        fi
    } >$os_dir/etc/fstab

    # 网卡配置
    create_cloud_init_network_config /net.cfg
    create_network_manager_config /net.cfg $os_dir
    rm /net.cfg

    # 修正网卡名
    add_fix_eth_name_systemd_service $os_dir

    # frpc
    add_frpc_systemd_service_if_need $os_dir
}

install_qcow_by_copy() {
    info "Install qcow2 by copy"

    modify_el_ol() {
        info "Modify el ol"
        os_dir=/os

        # resolv.conf
        cp_resolv_conf /os

        # 部分镜像有默认配置，例如 centos
        del_exist_sysconfig_NetworkManager_config /os

        # 删除镜像的默认账户，防止使用默认账户密码登录 ssh
        del_default_user /os

        # selinux kdump
        disable_selinux /os
        disable_kdump /os

        # el7 删除 machine-id 后不会自动重建
        clear_machine_id /os

        # el7 forks 特殊处理
        if is_el7_family /os; then
            # centos 7 eol 换源
            if [ -f /os/etc/yum.repos.d/CentOS-Base.repo ]; then
                # 保持默认的 http 因为自带的 ssl 证书可能过期
                if is_in_china; then
                    mirror=mirror.nju.edu.cn/centos-vault
                else
                    mirror=vault.centos.org
                fi
                sed -Ei -e 's,(mirrorlist=),#\1,' \
                    -e "s,#(baseurl=http://)mirror.centos.org,\1$mirror," /os/etc/yum.repos.d/CentOS-Base.repo
            fi

            # el7 yum 可能会使用 ipv6，即使没有 ipv6 网络
            if [ "$(cat /dev/netconf/eth*/ipv6_has_internet | sort -u)" = 0 ]; then
                echo 'ip_resolve=4' >>/os/etc/yum.conf
            fi

            # el7 安装 NetworkManager
            # anolis 7 镜像自带 NetworkManager
            if ! [ -f /os/usr/lib/systemd/system/NetworkManager.service ]; then
                chroot_dnf install NetworkManager
            fi
            # 服务不存在时会报错
            chroot /os systemctl disable network 2>/dev/null || true
            chroot /os systemctl enable NetworkManager
        fi

        # firmware + microcode
        if fw_pkgs=$(get_ucode_firmware_pkgs) && [ -n "$fw_pkgs" ]; then
            chroot_dnf install $fw_pkgs
        fi

        # fstab 删除多余分区
        # almalinux/rocky 镜像有 boot 分区
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

        # openeuler arm 镜像 grub.cfg 在 /os/grub.cfg，可能给外部的 grub 读取，我们用不到
        # centos7 有 grub1 的配置
        rm -rf /os/grub.cfg /os/boot/grub/grub.conf /os/boot/grub/menu.lst

        # 安装引导
        if is_efi; then
            # 只有centos 和 oracle x86_64 镜像没有efi，其他系统镜像已经从efi分区复制了文件
            # openeuler 自带 grub2-efi-ia32，此时安装 grub2-efi 提示已经安装了 grub2-efi-ia32，不会继续安装 grub2-efi-x64

            # 假设极端情况，qcow2 制作时，安装 grub2-efi-x64 时没有挂载 efi 分区，那么 efi 文件会在系统分区下
            # 但我们复制系统分区时挂载了 /boot/efi，因此 efi 文件会正确地复制到 efi 分区
            # 因此无需判断 qcow2 的 efi 是否是独立分区

            # rhel 镜像没有源，直接 yum install 安装可能会报错
            # 因此如果已经安装了要用的包就不再运行 yum install
            need_install=false
            need_remove_grub_conflict_files=false

            [ "$(uname -m)" = x86_64 ] && arch=x64 || arch=aa64
            if ! chroot $os_dir rpm -qi grub2-efi-$arch; then
                need_install=true
                need_remove_grub_conflict_files=true
            elif ! chroot $os_dir rpm -qi shim-$arch || ! chroot $os_dir rpm -qi efibootmgr; then
                need_install=true
            fi

            if $need_install; then
                if $need_remove_grub_conflict_files; then
                    remove_grub_conflict_files
                fi
                chroot_dnf install efibootmgr grub2-efi-$arch shim-$arch
            fi
            # openeuler arm 25.09 云镜像里面的 grubaa64.efi 是用于 mbr 分区表，$root 是 hd0,msdos1
            # 因此要重新下载 $root 是 hd0,gpt1 的 grubaa64.efi
            if $need_reinstall_grub_efi; then
                chroot_dnf reinstall grub2-efi-$arch
            fi
        else
            # bios
            remove_grub_conflict_files
            chroot /os/ grub2-install /dev/$xda
        fi

        # blscfg 启动项
        # rocky/almalinux镜像是独立的boot分区，但我们不是
        # 因此要添加boot目录
        if ls /os/boot/loader/entries/*.conf 2>/dev/null &&
            ! grep -q 'initrd /boot/' /os/boot/loader/entries/*.conf; then

            sed -i -E 's,((linux|initrd) /),\1boot/,g' /os/boot/loader/entries/*.conf
        fi

        # grub-efi-x64 包里面有 /etc/grub2-efi.cfg
        # 指向 /boot/efi/EFI/xxx/grub.cfg 或 /boot/grub2/grub.cfg
        # 指向哪里哪里就是 grub2-mkconfig 应该生成文件的位置
        # grubby 也是靠 /etc/grub2-efi.cfg 定位 grub.cfg 的位置
        # openeuler 24.03 x64 aa64 指向的文件不同
        if is_efi; then
            grub_o_cfg=$(chroot /os readlink -f /etc/grub2-efi.cfg)
        else
            grub_o_cfg=/boot/grub2/grub.cfg
        fi

        # efi 分区 grub.cfg
        # https://github.com/rhinstaller/anaconda/blob/346b932a26a19b339e9073c049b08bdef7f166c3/pyanaconda/modules/storage/bootloader/efi.py#L198
        # https://github.com/rhinstaller/anaconda/commit/15c3b2044367d375db6739e8b8f419ef3e17cae7
        if is_efi && ! echo "$grub_o_cfg" | grep -q '/boot/efi/EFI'; then
            # oracle linux 文件夹是 redhat
            # shellcheck disable=SC2010
            distro_efi=$(cd /os/boot/efi/EFI/ && ls -d -- * | grep -Eiv BOOT)
            cat <<EOF >/os/boot/efi/EFI/$distro_efi/grub.cfg
search --no-floppy --fs-uuid --set=dev $os_part_uuid
set prefix=(\$dev)/boot/grub2
export \$prefix
configfile \$prefix/grub.cfg
EOF
        fi

        # 主 grub.cfg
        if ls /os/boot/loader/entries/*.conf >/dev/null 2>&1 &&
            chroot /os/ grub2-mkconfig --help | grep -q update-bls-cmdline; then
            chroot /os/ grub2-mkconfig -o "$grub_o_cfg" --update-bls-cmdline
        else
            chroot /os/ grub2-mkconfig -o "$grub_o_cfg"
        fi

        # 网络配置
        # el7/8 sysconfig
        # el9 network-manager
        if [ -f $os_dir/etc/sysconfig/network-scripts/ifup-eth ]; then
            # sysconfig
            info 'sysconfig'

            # anolis/openeuler/opencloudos 可能要安装 cloud-init
            # opencloudos 无法使用 chroot $os_dir command -v xxx
            # chroot: failed to run command ‘command’: No such file or directory
            # 注意还要禁用 cloud-init 服务
            if ! is_have_cmd_on_disk $os_dir cloud-init; then
                chroot_dnf install cloud-init
            fi

            # cloud-init 路径
            # /usr/lib/python2.7/site-packages/cloudinit/net/
            # /usr/lib/python3/dist-packages/cloudinit/net/
            # /usr/lib/python3.9/site-packages/cloudinit/net/

            # el7 不认识 static6，但可改成 static，作用相同
            recognize_static6=true
            if ls $os_dir/usr/lib/python*/*-packages/cloudinit/net/sysconfig.py 2>/dev/null &&
                ! grep -q static6 $os_dir/usr/lib/python*/*-packages/cloudinit/net/sysconfig.py; then
                recognize_static6=false
            fi

            # cloud-init 20.1 才支持以下配置
            # https://cloudinit.readthedocs.io/en/20.4/topics/network-config-format-v1.html#subnet-ip
            # https://cloudinit.readthedocs.io/en/21.1/topics/network-config-format-v1.html#subnet-ip
            # ipv6_dhcpv6-stateful: Configure this interface with dhcp6
            # ipv6_dhcpv6-stateless: Configure this interface with SLAAC and DHCP
            # ipv6_slaac: Configure address with SLAAC

            # el7 最新 cloud-init 版本
            # centos 7         19.4-7.0.5.el7_9.6  backport 了 ipv6_xxx
            # openeuler 20.03  19.4-15.oe2003sp4   backport 了 ipv6_xxx
            # anolis 7         19.1.17-1.0.1.an7   没有更新到 centos7 相同版本,也没 backport ipv6_xxx，坑

            # 最好还修改 ifcfg-eth* 的 IPV6_AUTOCONF
            # 但实测 anolis7 cloud-init dhcp6 不会生成 IPV6_AUTOCONF，因此暂时不管
            # https://www.redhat.com/zh/blog/configuring-ipv6-rhel-7-8
            recognize_ipv6_types=true
            if ls -d $os_dir/usr/lib/python*/*-packages/cloudinit/net/ 2>/dev/null &&
                ! grep -qr ipv6_slaac $os_dir/usr/lib/python*/*-packages/cloudinit/net/; then
                recognize_ipv6_types=false
            fi

            # 生成 cloud-init 网络配置
            create_cloud_init_network_config $os_dir/net.cfg "$recognize_static6" "$recognize_ipv6_types"

            # 转换成目标系统的网络配置
            chroot $os_dir cloud-init devel net-convert \
                -p /net.cfg -k yaml -d out -D rhel -O sysconfig
            cp $os_dir/out/etc/sysconfig/network-scripts/ifcfg-eth* $os_dir/etc/sysconfig/network-scripts/

            # 清理
            rm -rf $os_dir/net.cfg $os_dir/out

            # 删除 # Created by cloud-init on instance boot automatically, do not edit.
            # 修正网络配置问题并显示文件
            sed -i -e '/^IPV[46]_FAILURE_FATAL=/d' -e '/^#/d' $os_dir/etc/sysconfig/network-scripts/ifcfg-*
            for file in "$os_dir/etc/sysconfig/network-scripts/ifcfg-"*; do
                if grep -q '^DHCPV6C=yes' "$file"; then
                    sed -i '/^IPV6_AUTOCONF=no/d' "$file"
                fi
                cat -n "$file"
            done
        else
            # Network Manager
            info 'Network Manager'

            create_cloud_init_network_config /net.cfg
            create_network_manager_config /net.cfg "$os_dir"

            # 清理
            rm /net.cfg
        fi

        # 不删除可能网络管理器不会写入dns
        rm_resolv_conf /os
    }

    modify_ubuntu() {
        os_dir=/os
        info "Modify Ubuntu"

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
                    sed -i 's/archive.ubuntu.com/mirror.nju.edu.cn/' $file # x64
                    sed -i 's/ports.ubuntu.com/mirror.nju.edu.cn/' $file   # arm
                fi
            done
        fi

        # 16.04 arm64 镜像没有 grub 引导文件
        if is_efi && ! [ -d $os_dir/boot/efi/EFI/ubuntu ]; then
            chroot_apt_install $os_dir efibootmgr shim "grub-efi-$(get_axx64)"
            # 创建 ubuntu 文件夹和 grubaa64.efi
            DEBIAN_FRONTEND=noninteractive chroot $os_dir dpkg-reconfigure "grub-efi-$(get_axx64)"

            cat <<EOF >"$os_dir/boot/efi/EFI/ubuntu/grub.cfg"
search.fs_uuid $os_part_uuid root
set prefix=(\$root)'/boot/grub'
configfile \$prefix/grub.cfg
EOF
        fi

        # 避免 do-release-upgrade 时自动执行 dpkg-reconfigure grub-xx 但是 efi/biosgrub 分区不存在而导致报错
        # shellcheck disable=SC2046
        chroot_apt_remove $os_dir $(is_efi && echo 'grub-pc' || echo 'grub-efi*' 'shim*')
        chroot_apt_autoremove $os_dir

        # 安装 mbr
        if ! is_efi; then
            if false; then
                # debconf-show grub-pc
                # 每次开机硬盘名字可能不一样，但是 debian netboot 安装后也是设置了 grub-pc/install_devices
                echo grub-pc grub-pc/install_devices multiselect /dev/$xda | chroot $os_dir debconf-set-selections # 22.04
                echo grub-pc grub-pc/cloud_style_installation boolean true | chroot $os_dir debconf-set-selections # 24.04
                chroot $os_dir dpkg-reconfigure -f noninteractive grub-pc
            else
                chroot $os_dir grub-install /dev/$xda
            fi
        fi

        # 自带内核：
        # 常规版本             generic
        # minimal 20.04/22.04 kvm      # 后台 vnc 无显示
        # minimal 24.04       virtual

        # debian cloud 内核不支持 ahci，ubuntu virtual 支持

        # 标记所有内核为自动安装
        # 注意排除 linux-base
        # 返回值始终为 0
        pkgs=$(chroot $os_dir apt-mark showmanual \
            linux-generic linux-virtual linux-kvm \
            linux-image* linux-headers*)
        chroot $os_dir apt-mark auto $pkgs

        # 安装最佳内核
        flavor=$(get_ubuntu_kernel_flavor)
        echo "Use kernel flavor: $flavor"
        # 如果镜像自带内核跟最佳内核是同一种且有更新
        # 则 apt install 只会进行更新，不会将包设置成 manual
        # 需要再运行 apt install 才会将包设置成 manual
        chroot_apt_install $os_dir "linux-image-$flavor"
        chroot_apt_install $os_dir "linux-image-$flavor"

        # 使用 autoremove 删除多余内核
        chroot_apt_autoremove $os_dir

        # 安装固件+微码
        if fw_pkgs=$(get_ucode_firmware_pkgs) && [ -n "$fw_pkgs" ]; then
            chroot_apt_install $os_dir $fw_pkgs
        fi

        # 网络配置
        # 18.04+ netplan
        if is_have_cmd_on_disk $os_dir netplan; then
            # 避免删除 cloud-init 后，minimal 镜像的 netplan.io 被 autoremove
            chroot $os_dir apt-mark manual netplan.io

            # 生成 cloud-init 网络配置
            create_cloud_init_network_config $os_dir/net.cfg

            # ubuntu 18.04 cloud-init 版本 23.1.2，因此不用处理 onlink

            # 如果不是输出到 / 则不会生成 50-cloud-init.yaml
            # 注意比较多了什么东西
            if false; then
                chroot $os_dir cloud-init devel net-convert \
                    -p /net.cfg -k yaml -d /out -D ubuntu -O netplan
                sed -Ei "/^[[:space:]]+set-name:/d" $os_dir/out/etc/netplan/50-cloud-init.yaml
                cp $os_dir/out/etc/netplan/50-cloud-init.yaml $os_dir/etc/netplan/

                # 清理
                rm -rf $os_dir/net.cfg $os_dir/out
            else
                chroot $os_dir cloud-init devel net-convert \
                    -p /net.cfg -k yaml -d / -D ubuntu -O netplan
                sed -Ei "/^[[:space:]]+set-name:/d" $os_dir/etc/netplan/50-cloud-init.yaml

                # 清理
                rm -rf $os_dir/net.cfg
            fi
        else
            # 避免删除 cloud-init 后 ifupdown 被 autoremove
            chroot $os_dir apt-mark manual ifupdown

            # 16.04 镜像用 ifupdown/networking 管理网络
            # 要安装 resolveconf，不然 /etc/resolv.conf 为空
            chroot_apt_install $os_dir resolvconf
            ln -sf /run/resolvconf/resolv.conf $os_dir/etc/resolv.conf.orig

            create_ifupdown_config $os_dir/etc/network/interfaces
        fi

        # 自带的 60-cloudimg-settings.conf 禁止了 PasswordAuthentication
        file=$os_dir/etc/ssh/sshd_config.d/60-cloudimg-settings.conf
        if [ -f $file ]; then
            sed -i '/^PasswordAuthentication/d' $file
            if [ -z "$(cat $file)" ]; then
                rm -f $file
            fi
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

    efi_mount_opts=$(
        case "$distro" in
        ubuntu) echo "umask=0077" ;;
        *) echo "defaults,uid=0,gid=0,umask=077,shortname=winnt" ;;
        esac
    )

    # yum/apt 安装软件时需要的内存总大小
    need_ram=$(
        case "$distro" in
        ubuntu) echo 1024 ;;
        *) echo 2048 ;;
        esac
    )

    connect_qcow

    # 镜像分区格式
    # centos/rocky/almalinux/rhel: xfs
    # oracle x86_64:          lvm + xfs
    # oracle aarch64 cloud:   xfs
    # alibaba cloud linux 3:  ext4

    is_lvm_image=false
    if lsblk -f /dev/nbd0p* | grep LVM2_member; then
        is_lvm_image=true
        apk add lvm2
        lvscan
        vg=$(pvs | grep /dev/nbd0p | awk '{print $2}')
        lvchange -ay "$vg"
    fi

    mount_nouuid() {
        part_fstype=
        for arg in "$@"; do
            case "$arg" in
            /dev/*)
                part_fstype=$(lsblk -no FSTYPE "$arg")
                break
                ;;
            esac
        done

        case "$part_fstype" in
        xfs) mount -o nouuid "$@" ;;
        *) mount "$@" ;;
        esac
    }

    # 可以直接选择最后一个分区为系统分区?
    # almalinux9 boot 分区的类型不是规定的 uuid
    # openeuler boot 分区是 vfat 格式
    # openeuler arm 25.09 是 mbr 分区表, efi boot 是同一个分区，vfat 格式

    info "qcow2 Partitions check"

    # 检测分区表类型
    partition_table_format=$(get_partition_table_format /dev/nbd0)
    need_reinstall_grub_efi=false
    if is_efi && [ "$partition_table_format" = "msdos" ]; then
        need_reinstall_grub_efi=true
    fi

    # 通过检测文件判断是什么分区
    os_part='' boot_part='' efi_part=''
    mkdir -p /nbd-test
    for part in $(lsblk /dev/nbd0p* --sort SIZE -no NAME,FSTYPE |
        grep -E ' (ext4|xfs|fat|vfat)$' | awk '{print $1}' | tac); do
        mapper_part=$part
        if $is_lvm_image && [ -e /dev/mapper/$part ]; then
            mapper_part=mapper/$part
        fi

        if mount_nouuid -o ro /dev/$mapper_part /nbd-test; then
            if { ls /nbd-test/etc/os-release || ls /nbd-test/*/etc/os-release; } 2>/dev/null; then
                os_part=$mapper_part
            fi
            # shellcheck disable=SC2010
            # 当 boot 作为独立分区时，vmlinuz 等文件在根目录
            # 当 boot 不是独立分区时，vmlinuz 等文件在 /boot 目录
            if ls /nbd-test/ /nbd-test/boot/ 2>/dev/null | grep -Ei '^(vmlinuz|initrd|initramfs)'; then
                boot_part=$mapper_part
            fi
            # mbr + efi 引导 ，分区表没有 esp guid
            # 因此需要用 efi 文件判断是否 efi 分区
            # efi 文件可能在 efi 目录的子目录，子目录层数不定
            if find /nbd-test/ -type f -ipath '/nbd-test/EFI/*.efi' 2>/dev/null | grep .; then
                efi_part=$mapper_part
            fi
            umount /nbd-test
        fi
    done

    info "qcow2 Partitions"
    lsblk -f /dev/nbd0 -o +PARTTYPE
    # 显示 OS/EFI/Boot 文件在哪个分区
    echo "---"
    echo "Table:     $partition_table_format"
    echo "Part OS:   $os_part"
    echo "Part EFI:  $efi_part"
    echo "Part Boot: $boot_part"
    echo "---"

    # 分区寻找方式
    # 系统/分区          cmdline:root  fstab:efi
    # rocky             LABEL=rocky   LABEL=EFI
    # ubuntu            PARTUUID      LABEL=UEFI
    # 其他el/ol         UUID           UUID

    IFS=, read -r os_part_uuid os_part_label os_part_fstype \
        < <(lsblk /dev/$os_part -rno UUID,LABEL,FSTYPE | tr ' ' ,)

    if [ -n "$efi_part" ]; then
        IFS=, read -r efi_part_uuid efi_part_label \
            < <(lsblk /dev/$efi_part -rno UUID,LABEL | tr ' ' ,)
    fi

    mkdir -p /nbd /nbd-boot /nbd-efi

    # 使用目标系统的格式化程序
    # centos8 如果用alpine格式化xfs，grub2-mkconfig和grub2里面都无法识别xfs分区
    mount_nouuid /dev/$os_part /nbd/
    mount_pseudo_fs /nbd/
    case "$os_part_fstype" in
    ext4) chroot /nbd mkfs.ext4 -F -L "$os_part_label" -U "$os_part_uuid" /dev/$xda*2 ;;
    xfs) chroot /nbd mkfs.xfs -f -L "$os_part_label" -m uuid=$os_part_uuid /dev/$xda*2 ;;
    esac
    umount -R /nbd/

    # TODO: ubuntu 镜像缺少 mkfs.fat/vfat/dosfstools? initrd 不需要检查fs完整性？

    # 创建并挂载 /os
    mkdir -p /os
    mount -o noatime /dev/$xda*2 /os/

    # 如果是 efi 则创建 /os/boot/efi
    # 如果镜像有 efi 分区也创建 /os/boot/efi，用于复制 efi 分区的文件
    if is_efi || [ -n "$efi_part" ]; then
        mkdir -p /os/boot/efi/

        # 挂载 /os/boot/efi
        # 预先挂载 /os/boot/efi 因为可能 boot 和 efi 在同一个分区（openeuler 24.03 arm）
        # 复制 boot 时可以会复制 efi 的文件
        if is_efi; then
            mount -o $efi_mount_opts /dev/$xda*1 /os/boot/efi/
        fi
    fi

    # 复制系统分区
    echo Copying os partition...
    mount_nouuid -o ro /dev/$os_part /nbd/
    cp -a /nbd/* /os/
    umount /nbd/

    # 复制独立的boot分区，如果有
    if [ -n "$boot_part" ] && ! [ "$boot_part" = "$os_part" ]; then
        echo Copying boot partition...
        mount_nouuid -o ro /dev/$boot_part /nbd-boot/
        cp -a /nbd-boot/* /os/boot/
        umount /nbd-boot/
    fi

    # 复制独立的efi分区，如果有
    # 如果 efi 和 boot 是同一个分区，则复制 boot 分区时已经复制了 efi 分区的文件
    if [ -n "$efi_part" ] && ! [ "$efi_part" = "$os_part" ] && ! [ "$efi_part" = "$boot_part" ]; then
        echo Copying efi partition...
        mount -o ro /dev/$efi_part /nbd-efi/
        cp -a /nbd-efi/* /os/boot/efi/
        umount /nbd-efi/
    fi

    # 断开 qcow 并删除 qemu-img
    info "Disconnecting qcow2"
    if is_have_cmd vgchange; then
        vgchange -an
        apk del lvm2
    fi
    disconnect_qcow
    apk del qemu-img

    # 取消挂载硬盘
    info "Unmounting disk"
    if is_efi; then
        umount /os/boot/efi/
    fi
    umount /os/
    umount /installer/

    # 如果镜像有独立的efi分区（包括efi+boot在同一个分区），复制其uuid
    # 如果有相同uuid的fat分区，则无法挂载
    # 所以要先复制efi分区，断开nbd再复制uuid
    # 复制uuid前要取消挂载硬盘 efi 分区
    if is_efi && [ -n "$efi_part_uuid" ] && ! [ "$efi_part" = "$os_part" ]; then
        info "Copy efi partition uuid"
        apk add mtools
        mlabel -N "$(echo $efi_part_uuid | sed 's/-//')" -i /dev/$xda*1 ::$efi_part_label
        apk del mtools
        update_part
    fi

    # 删除 installer 分区并扩容
    info "Delete installer partition"
    apk add parted
    parted /dev/$xda -s -- rm 3
    update_part
    resize_after_install_cloud_image

    # 重新挂载 /os /boot/efi
    info "Re-mount disk"
    mount -o noatime /dev/$xda*2 /os/
    if is_efi; then
        mount -o $efi_mount_opts /dev/$xda*1 /os/boot/efi/
    fi

    # 创建 swap
    create_swap_if_ram_less_than $need_ram /os/swapfile

    # 挂载伪文件系统
    mount_pseudo_fs /os/

    case "$distro" in
    ubuntu) modify_ubuntu ;;
    *) modify_el_ol ;;
    esac

    # 基本配置
    basic_init /os

    # 最后才删除 cloud-init
    # 因为生成 netplan/sysconfig 网络配置要用目标系统的 cloud-init
    remove_cloud_init /os

    # 删除 swapfile
    swapoff -a
    rm -f /os/swapfile
}

get_partition_table_format() {
    apk add parted
    parted "$1" -s print | grep 'Partition Table:' | awk '{print $NF}'
}

dd_qcow() {
    info "DD qcow2"

    if true; then
        connect_qcow

        partition_table_format=$(get_partition_table_format /dev/nbd0)
        orig_nbd_virtual_size=$(get_disk_size /dev/nbd0)

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
    rm -f /first-1M

    # gpt 分区表开头记录了备份分区表的位置
    # 如果 qcow2 虚拟容量 大于 实际硬盘容量
    # 备份分区表的位置 将超出实际硬盘容量的大小
    # partprobe 会报错
    # Error: Invalid argument during seek for read on /dev/vda
    # parted 也无法正常工作
    # 需要提前修复分区表

    # 目前只有这个例子，因为其他 qcow2 虚拟容量最多 5g，是设定支持的容量
    # openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2 容量是 25g
    # 缩小 btrfs 分区后 dd 到 10g 的机器上
    # 备份分区表的位置是 25g
    # 需要修复到 10g 的位置上
    # 否则 partprobe parted 都无法正常工作

    # 仅这种情况才用 sgdisk 修复
    if [ "$partition_table_format" = gpt ] &&
        [ "$orig_nbd_virtual_size" -gt "$(get_disk_size /dev/$xda)" ]; then
        fix_gpt_backup_partition_table_by_sgdisk
    fi
    update_part
}

fix_gpt_backup_partition_table_by_sgdisk() {
    # 当备份分区表超出实际硬盘容量时，只能用 sgdisk 修复分区表
    # 应用场景：镜像大小超出硬盘实际硬盘，但缩小分区后不超出实际硬盘容量，可以顺利 DD
    # 例子 openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2

    # parted 无法修复
    # parted /dev/$xda -f -s print

    # fdisk/sfdisk 显示主分区表损坏
    # echo write | sfdisk /dev/$xda
    # GPT PMBR size mismatch (50331647 != 20971519) will be corrected by write.
    # The primary GPT table is corrupt, but the backup appears OK, so that will be used.

    # 除此之外的场景应该用 parted 来修复

    apk add sgdisk

    # 两种方法都可以，但都不会修复备份分区表的 GUID
    # 此时 sgdisk -v /dev/vda 会提示主副分区表 guid 不相同
    # localhost:~# sgdisk -v /dev/$xda
    # Problem: main header's disk GUID (A24485F3-2C02-43BD-BF4E-F52E42B00DEA) doesn't
    # match the backup GPT header's disk GUID (ADAF57BC-B4F5-4E04-BCBA-BDDCD796C388)
    # You should use the 'b' or 'd' option on the recovery & transformation menu to
    # select one or the other header.
    if false; then
        sgdisk --backup /gpt-partition-table /dev/$xda
        sgdisk --load-backup /gpt-partition-table /dev/$xda
    else
        sgdisk --move-second-header /dev/$xda
    fi

    # 因此需要运行一次设置 guid
    if new_guid=$(sgdisk -v /dev/$xda | grep GUID | head -1 | grep -Eo '[0-9A-F-]{36}'); then
        sgdisk --disk-guid $new_guid /dev/$xda
    fi

    update_part

    apk del sgdisk
}

# 适用于 DD 后修复 gpt 备份分区表
fix_gpt_backup_partition_table_by_parted() {
    apk add parted
    parted /dev/$xda -f -s print
    update_part
}

resize_after_install_cloud_image() {
    # 提前扩容
    # 1 修复 vultr 512m debian 11 generic/genericcloud 首次启动 kernel panic
    # 2 防止 gentoo 云镜像 websync 时空间不足
    info "Resize after dd"
    lsblk -f /dev/$xda

    # 打印分区表，并自动修复备份分区表
    fix_gpt_backup_partition_table_by_parted

    disk_size=$(get_disk_size /dev/$xda)
    disk_end=$((disk_size - 1))

    # 不能漏掉最后的 _ ，否则第6部分都划到给 last_part_fs
    IFS=: read -r last_part_num _ last_part_end _ last_part_fs _ \
        < <(parted -msf /dev/$xda 'unit b print' | tail -1)
    last_part_end=$(echo $last_part_end | sed 's/B//')

    if [ $((disk_end - last_part_end)) -ge 0 ]; then
        printf "yes" | parted /dev/$xda resizepart $last_part_num 100% ---pretend-input-tty
        update_part

        mkdir -p /os

        # lvm ?
        # 用 cloud-utils-growpart？
        case "$last_part_fs" in
        ext4)
            # debian ci
            apk add e2fsprogs-extra
            e2fsck -p -f /dev/$xda*$last_part_num
            resize2fs /dev/$xda*$last_part_num
            apk del e2fsprogs-extra
            ;;
        xfs)
            # opensuse ci
            apk add xfsprogs-extra
            mount /dev/$xda*$last_part_num /os
            xfs_growfs /dev/$xda*$last_part_num
            umount /os
            apk del xfsprogs-extra
            ;;
        btrfs)
            # fedora ci
            apk add btrfs-progs
            mount /dev/$xda*$last_part_num /os
            btrfs filesystem resize max /os
            umount /os
            apk del btrfs-progs
            ;;
        ntfs)
            # windows dd
            apk add ntfs-3g-progs
            echo y | ntfsresize /dev/$xda*$last_part_num
            ntfsfix -d /dev/$xda*$last_part_num
            apk del ntfs-3g-progs
            ;;
        esac
        update_part
        parted /dev/$xda -s print
    fi
}

mount_part_basic_layout() {
    os_dir=$1
    efi_dir=$2

    if is_efi || is_xda_gt_2t; then
        os_part_num=2
    else
        os_part_num=1
    fi

    # 挂载系统分区
    mkdir -p $os_dir
    mount -t ext4 /dev/${xda}*${os_part_num} $os_dir

    # 挂载 efi 分区
    if is_efi; then
        mkdir -p $efi_dir
        mount -t vfat -o umask=077 /dev/${xda}*1 $efi_dir
    fi
}

mount_part_for_iso_installer() {
    info "Mount part for iso installer"

    if [ "$distro" = windows ]; then
        mount_args="-t ntfs3 -o nocase"
    else
        mount_args=
    fi

    # 挂载主分区
    mkdir -p /os
    mount $mount_args /dev/disk/by-label/os /os

    # 挂载其他分区
    if is_efi; then
        mkdir -p /os/boot/efi
        mount /dev/disk/by-label/efi /os/boot/efi
    fi
    mkdir -p /os/installer
    mount $mount_args /dev/disk/by-label/installer /os/installer
}

get_dns_list_for_win() {
    if dns_list=$(get_current_dns $1); then
        i=0
        for dns in $dns_list; do
            i=$((i + 1))
            echo "set ipv${1}_dns$i=$dns"
        done
    fi
}

create_win_set_netconf_script() {
    target=$1
    info "Create win netconf script"

    if is_staticv4 || is_staticv6 || is_need_manual_set_dnsv6; then
        get_netconf_to mac_addr
        echo "set mac_addr=$mac_addr" >$target

        # 生成静态 ipv4 配置
        if is_staticv4; then
            get_netconf_to ipv4_addr
            get_netconf_to ipv4_gateway
            cat <<EOF >>$target
set ipv4_addr=$ipv4_addr
set ipv4_gateway=$ipv4_gateway
$(get_dns_list_for_win 4)
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
        if is_need_manual_set_dnsv6; then
            cat <<EOF >>$target
$(get_dns_list_for_win 6)
EOF
        fi

        cat -n $target
    fi

    # 脚本还有关闭ipv6隐私id的功能，所以不能省略
    # 合并脚本
    wget $confhome/windows-set-netconf.bat -O- >>$target
    unix2dos $target
}

create_win_change_rdp_port_script() {
    target=$1
    rdp_port=$2

    info "Create win change rdp port script"

    echo "set RdpPort=$rdp_port" >$target
    wget $confhome/windows-change-rdp-port.bat -O- >>$target
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
    elif [ "$build_ver" -ge 6001 ]; then
        echo 2008
    else
        error_and_exit "Unknown Build Version: $build_ver"
    fi
}

is_nt_ver_ge() {
    local orig sorted
    orig=$(printf '%s\n' "$1" "$nt_ver")
    sorted=$(echo "$orig" | sort -V)
    [ "$orig" = "$sorted" ]
}

get_cloud_vendor() {
    # busybox blkid 不显示 sr0 的 UUID
    apk add lsblk

    # http://git.annexia.org/?p=virt-what.git;a=blob;f=virt-what.in;hb=HEAD
    # virt-what 可识别厂商 aws google_cloud alibaba_cloud alibaba_cloud-ebm
    if is_dmi_contains "Amazon EC2" || is_virt_contains aws; then
        echo aws
    elif is_dmi_contains "Google Compute Engine" || is_dmi_contains "GoogleCloud" || is_virt_contains google_cloud; then
        echo gcp
    elif is_dmi_contains "OracleCloud"; then
        echo oracle
    elif is_dmi_contains "7783-7084-3265-9085-8269-3286-77"; then
        echo azure
    elif lsblk -o UUID,LABEL | grep -i 9796-932E | grep -iq config-2; then
        echo ibm
    elif is_dmi_contains 'Huawei Cloud'; then
        echo huawei
    elif is_dmi_contains 'Alibaba Cloud'; then
        echo aliyun
    elif is_dmi_contains 'Tencent Cloud'; then
        echo qcloud
    fi
}

get_filesize_mb() {
    du -m "$1" | awk '{print $1}'
}

is_absolute_path() {
    # 检查路径是否以/开头
    # 注意语法和 bash 不同
    [[ "$1" = "/*" ]]
}

# 注意使用方法是 list=$(list_add "$list" "$item_to_add")
list_add() {
    local list=$1
    local item_to_add=$2
    if [ -n "$list" ]; then
        echo "$list"
    fi
    echo "$item_to_add"
}

is_list_has() {
    local list=$1
    local item=$2
    echo "$list" | grep -qFx "$item"
}

# hivexget 是 shell 脚本，开头是 #!/bin/bash
# 但 alpine 没安装 bash，直接运行 hivexget 会报错
hivexget() {
    ash "$(which hivexget)" "$@"
}

get_windows_type_from_windows_drive() {
    local os_dir=$1

    apk add hivex
    software_hive=$(find_file_ignore_case $os_dir/Windows/System32/config/SOFTWARE)
    system_hive=$(find_file_ignore_case $os_dir/Windows/System32/config/SYSTEM)
    installation_type=$(hivexget $software_hive '\Microsoft\Windows NT\CurrentVersion' InstallationType || true)
    product_type=$(hivexget $system_hive '\ControlSet001\Control\ProductOptions' ProductType || true)
    apk del hivex

    # 根据 win11 multi-session 的情况
    # InstallationType 比 ProductType 准确

    # Vista wim 和注册表都没有 InstallationType
    case "$installation_type" in
    Client | Embedded) echo client ;;
    Server | 'Server Core') echo server ;;
    *) case "$product_type" in
        WinNT) echo client ;;
        ServerNT) echo server ;;
        *) error_and_exit "Unknown Windows Type" ;;
        esac ;;
    esac
}

get_windows_arch_from_windows_drive() {
    local os_dir=$1

    apk add hivex
    hive=$(find_file_ignore_case $os_dir/Windows/System32/config/SYSTEM)
    # 没有 CurrentControlSet
    hivexget $hive 'ControlSet001\Control\Session Manager\Environment' PROCESSOR_ARCHITECTURE
    apk del hivex
}

install_windows() {
    get_wim_prop() {
        wim=$1
        property=$2

        wiminfo "$wim" | grep -i "^$property:" | cut -d: -f2- | trim
    }

    get_image_prop() {
        wim=$1
        index=$2
        property=$3

        wiminfo "$wim" "$index" | grep -i "^$property:" | cut -d: -f2- | trim
    }

    info "Process windows iso"
    mkdir -p /iso /wim

    # find_file_ignore_case 也在这个文件里面
    # shellcheck disable=SC1090
    . <(wget -O- $confhome/windows-driver-utils.sh)

    apk add wimlib

    download $iso /os/windows.iso
    mount -o ro /os/windows.iso /iso

    sources_boot_wim=$(
        cd /iso
        find_file_ignore_case sources/boot.wim 2>/dev/null ||
            error_and_exit "can't find boot.wim"
    )

    # 一般镜像是 install.wim
    # en_server_install_disc_windows_home_server_2011_x64_dvd_658487.iso 是 Install.wim
    source_install_wim=$(
        cd /iso
        { find_file_ignore_case sources/install.wim ||
            find_file_ignore_case sources/install.esd; } 2>/dev/null ||
            error_and_exit "can't find install.wim or install.esd"
    )

    # 防止用了不兼容架构的 iso
    boot_index=$(get_wim_prop "/iso/$sources_boot_wim" 'Boot Index')
    arch_wim=$(get_image_prop "/iso/$sources_boot_wim" "$boot_index" 'Architecture' | to_lower)
    if ! {
        { [ "$(uname -m)" = "x86_64" ] && [ "$arch_wim" = x86_64 ]; } ||
            { [ "$(uname -m)" = "x86_64" ] && [ "$arch_wim" = x86 ]; } ||
            { [ "$(uname -m)" = "aarch64" ] && [ "$arch_wim" = arm64 ]; }
    }; then
        error_and_exit "The machine is $(uname -m), but the iso is $arch_wim."
    fi

    # efi 机器不能安装 32 位 windows
    if is_efi && [ "$arch_wim" = x86 ]; then
        error_and_exit "EFI machine can't install 32-bit Windows."
    fi

    iso_install_wim=/iso/$source_install_wim
    install_wim=/os/installer/$source_install_wim

    # 匹配映像版本
    # 需要整行匹配，因为要区分 Windows 10 Pro 和 Windows 10 Pro for Workstations
    image_count=$(wiminfo $iso_install_wim | grep "^Image Count:" | cut -d: -f2 | trim)
    all_image_names=$(wiminfo $iso_install_wim | grep ^Name: | sed 's/^Name: *//')
    info "Images Count: $image_count"
    echo "$all_image_names"
    echo

    if [ "$image_count" = 1 ]; then
        # 只有一个版本就用那个版本
        image_name=$all_image_names
        image_index=1
    else
        while true; do
            # 匹配成功
            # 改成正确的大小写
            if matched_image_name=$(echo "$all_image_names" | grep -ix "$image_name"); then
                image_name=$matched_image_name
                image_index=$(wiminfo "$iso_install_wim" "$image_name" | grep 'Index:' | awk '{print $NF}')
                break
            fi

            # 匹配失败
            file=/image-name
            error "Invalid image name: $image_name"
            echo "Choose a correct image name by one of follow command in ssh to continue:"
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

    get_selected_image_prop() {
        get_image_prop "$iso_install_wim" "$image_index" "$1"
    }

    # 多会话的信息来自注册表，因为没有官方 iso

    # Installation Type:
    # https://github.com/search?q=InstallationType+Client+Embedded+Server+Core&type=code
    # - Client      (普通 windows)
    # - Server      (windows server 带桌面体验)
    # - Server Core (windows server 不带桌面体验)
    # - Embedded    (WES7 / Thin PC)
    # - Client      (windows 10/11 enterprise 多会话)

    # Product Type:
    # https://cloud.tencent.com/developer/article/2465206
    # https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-multisession-faq#why-does-my-application-report-windows-enterprise-multi-session-as-a-server-operating-system
    # - WinNT    (普通 windows)
    # - ServerNT (windows server 带桌面体验)
    # - ServerNT (windows server 不带桌面体验)
    # - WinNT    (WES7 / Thin PC)
    # - ServerNT (windows 10/11 enterprise 多会话)

    # Product Suite:
    # https://www.geoffchappell.com/studies/windows/km/ntoskrnl/api/ex/exinit/productsuite.htm
    # - Terminal Server (普通 windows)
    # - Enterprise      (windows server 2025 带桌面体验)
    # - Enterprise      (windows server 2025 不带桌面体验)
    # - Terminal Server (windows server 2012 R2 评估板 带桌面体验，注册表也是这个值)
    # - Terminal Server (windows server 2022 R2 评估板 不带桌面体验，注册表也是这个值)
    # - Terminal Server (WES7 / Thin PC)
    # - ?               (windows 10/11 enterprise 多会话)

    # 用内核版本号筛选驱动
    # 使得可以安装 Hyper-V Server / Azure Stack HCI 等 Windows Server 变种
    # 7601.24214.180801-1700.win7sp1_ldr_escrow_CLIENT_ULTIMATE_x64FRE_en-us.iso wim 没有 Installation Type
    # Vista wim 和 注册表 都没有 InstallationType
    if false; then
        nt_ver=$(get_selected_image_prop "Major Version").$(get_selected_image_prop "Minor Version")
        build_ver=$(get_selected_image_prop "Build")
        installation_type=$(get_selected_image_prop "Installation Type")
    fi

    # 挂载 install.wim，检查
    # 1. 是否自带 sac 组件
    # 2. 是否自带 nvme 驱动
    # 3. 是否支持 sha256
    # 4. Installation Type
    wimmount "$iso_install_wim" "$image_index" /wim/
    ntoskrnl_exe=$(find_file_ignore_case /wim/Windows/System32/ntoskrnl.exe)
    get_windows_version_from_dll "$ntoskrnl_exe"
    windows_type=$(get_windows_type_from_windows_drive /wim)
    {
        find_file_ignore_case /wim/Windows/System32/sacsess.exe && has_sac=true || has_sac=false
        find_file_ignore_case /wim/Windows/INF/stornvme.inf && has_stornvme=true || has_stornvme=false
    } >/dev/null 2>&1
    wimunmount /wim/

    # https://www.hummingheads.co.jp/press/info-certificates.html
    # https://support.microsoft.com/kb/KB3033929
    # https://support.microsoft.com/kb/KB4474419
    # Windows Vista SP2 ldr_escrow   6.0.6003 + KB4474419
    # Windows 7     SP1              6.1.7601 + KB3033929
    support_sha256=false
    if is_nt_ver_ge 6.2 ||
        { [ "$nt_ver" = 6.1 ] && [ "$build_ver" -ge 7601 ] && [ "$rev_ver" -ge 18741 ]; } ||
        { [ "$nt_ver" = 6.0 ] && [ "$build_ver" -ge 6003 ] && [ "$rev_ver" -ge 20555 ]; }; then
        support_sha256=true
    fi

    product_ver=$(
        case "$windows_type" in
        client) get_client_name_by_build_ver "$build_ver" ;;
        server) get_server_name_by_build_ver "$build_ver" ;;
        esac
    )

    info "Selected image info"
    echo "Image Name: $image_name"
    echo "Product Version: $product_ver"
    echo "Windows Type: $windows_type"
    echo "NT Version: $nt_ver"
    echo "Build Version: $build_ver"
    echo "-------------------------"
    echo "Has SAC: $has_sac"
    echo "Has StorNVMe: $has_stornvme"
    echo "Support SHA256: $support_sha256"
    echo

    # 复制 boot.wim 到 /os，用于临时编辑
    if [ -n "$boot_wim" ]; then
        # 自定义 boot.wim 链接
        download "$boot_wim" /os/boot.wim
    else
        cp /iso/$sources_boot_wim /os/boot.wim
    fi

    # efi 启动目录为 efi 分区
    # bios 启动目录为 os 分区
    if is_efi; then
        boot_dir=/os/boot/efi
    else
        boot_dir=/os
    fi

    # 复制启动相关的文件
    # efi 额外复制efi目录
    echo 'Copying boot files...'
    cp -r "$(get_path_in_correct_case /iso/boot)"* $boot_dir
    if is_efi; then
        echo 'Copying efi files...'
        cp -r "$(get_path_in_correct_case /iso/efi)" $boot_dir
    fi

    # 复制iso全部文件(除了boot.wim)到installer分区
    echo 'Copying installer files...'
    if false; then
        # 还需忽略大小写
        rsync -rv \
            --exclude=/sources/boot.wim \
            --exclude=/sources/install.wim \
            --exclude=/sources/install.esd \
            /iso/* /os/installer/
    else
        (
            cd /iso
            find . -type f \
                -not -iname boot.wim \
                -not -iname install.wim \
                -not -iname install.esd \
                -exec cp -r --parents {} /os/installer/ \;
        )
    fi

    # 优化 install.wim
    # 优点: 可以节省 200M~600M 空间，用来创建虚拟内存
    #       （意义不大，因为已经删除了 boot.wim 用来创建虚拟内存，vista 除外）
    # 缺点: 如果 install.wim 只有一个镜像，则只能缩小 10M+
    if false; then
        time wimexport --threads "$(get_build_threads 512)" "$iso_install_wim" "$image_index" "$install_wim"
        info "install.wim size"
        echo "Original:  $(get_filesize_mb "$iso_install_wim")"
        echo "Optimized: $(get_filesize_mb "$install_wim")"
        echo
    else
        cp "$iso_install_wim" "$install_wim"
    fi

    # win11 要求 1GHz 2核（1核超线程也行）
    # 用注册表无法绕过
    # https://github.com/pbatard/rufus/issues/1990
    # https://learn.microsoft.com/windows/iot/iot-enterprise/Hardware/System_Requirements
    if [ "$product_ver" = "11" ] && [ "$(nproc)" -le 1 ]; then
        wiminfo "$install_wim" "$image_index" --image-property WINDOWS/INSTALLATIONTYPE=Server
    fi

    # 变量名     使用场景
    # arch_uname arch命令 / uname -m                      x86_64   aarch64
    # arch_wim   wiminfo                             x86  x86_64   ARM64
    # arch       virtio iso / unattend.xml / .inf    x86  amd64    arm64
    # arch_xdd   virtio msi / xen驱动                x86   x64
    # arch_dd    华为云驱动                           32    64

    # 将 wim 的 arch 转为驱动和应答文件的 arch
    case "$arch_wim" in
    x86)
        arch=x86
        arch_xdd=x86
        arch_dd=32
        ;;
    x86_64)
        arch=amd64
        arch_xdd=x64
        arch_dd=64
        ;;
    arm64)
        arch=arm64
        arch_xdd= # xen 没有 arm64 驱动，# virtio 也没有 arm64 msi
        arch_dd=  # 华为云没有 arm64 驱动
        ;;
    esac

    # win7 drvload 可以加载 sha256 签名的驱动
    # 但系统安装完重启报错 windows cannot verify the digital signature for this file
    # 需要按 F8 禁用驱动签名

    add_drivers() {
        info "Add drivers"

        drv=/os/drivers
        mkdir -p "$drv" # 驱动下载临时文件夹

        # 这里有坑
        # $(get_cloud_vendor) 调用了 cache_dmi_and_virt
        # 但是 $(get_cloud_vendor) 运行在 subshell 里面
        # subshell 运行结束后里面的变量就消失了
        # 因此先运行 cache_dmi_and_virt
        cache_dmi_and_virt
        vendor="$(get_cloud_vendor)"

        # virtio
        if is_virt_contains virtio; then
            if [ "$vendor" = aliyun ] && is_nt_ver_ge 6.1 && [ "$arch_wim" = x86_64 ]; then
                add_driver_aliyun_virtio
            elif [ "$vendor" = qcloud ] && is_nt_ver_ge 6.1 && [ "$arch_wim" = x86_64 ]; then
                add_driver_qcloud_virtio
            # 未测试是否需要专用驱动
            elif false && [ "$vendor" = huawei ] && is_nt_ver_ge 6.0 && { [ "$arch_wim" = x86 ] || [ "$arch_wim" = x86_64 ]; }; then
                add_driver_huawei_virtio

            # gcp 官方驱动不全，需要用公版补全
            # 官方 windows server 模板没有 viorng 设备，但 linux 模板有
            elif [ "$vendor" = gcp ] && is_nt_ver_ge 6.1 && [ "$arch_wim" = x86 ] && $support_sha256; then
                add_driver_gcp_virtio
                add_driver_generic_virtio \( -iname viorng.inf -or -iname pvpanic.inf \)

            elif [ "$vendor" = gcp ] && is_nt_ver_ge 6.1 && [ "$arch_wim" = x86_64 ] && $support_sha256; then
                add_driver_gcp_virtio
                add_driver_generic_virtio -iname viorng.inf

            elif [ "$vendor" = gcp ] && [ "$nt_ver" = 6.1 ] && [ "$arch_wim" = x86_64 ] && ! $support_sha256; then
                add_driver_gcp_virtio_win6_1_sha1_x64
                add_driver_generic_virtio \( -iname viorng.inf -or -iname balloon.inf \)

            else
                # 兜底
                add_driver_generic_virtio
            fi
        fi

        # xen
        if is_virt_contains xen; then
            # generic_xen 兜底，但未签名，暂停使用
            if is_nt_ver_ge 6.1 && [ "$arch_wim" = x86_64 ]; then
                add_driver_aws_xen
            elif is_nt_ver_ge 6.0 && { [ "$arch_wim" = x86 ] || [ "$arch_wim" = x86_64 ]; }; then
                add_driver_citrix_xen
            fi
        fi

        # vmd
        # RST v17 不支持 vmd
        # RST v18 inf 要求 15063 或以上
        # RST v19 inf 要求 15063 或以上
        # RST v20 inf 要求 19041 或以上
        if [ -d /sys/module/vmd ] && [ "$build_ver" -ge 15063 ] && [ "$arch_wim" = x86_64 ]; then
            add_driver_vmd
        fi

        # 厂商驱动
        case "$vendor" in
        aws)
            if is_nt_ver_ge 6.1 && { [ "$arch_wim" = x86_64 ] || [ "$arch_wim" = arm64 ]; }; then
                add_driver_aws
            fi
            ;;
        azure)
            # inf 不限版本，未测试
            if [ "$arch_wim" = x86 ] || [ "$arch_wim" = x86_64 ]; then
                add_driver_azure
            fi
            ;;
        gcp)
            # inf 不限版本，6.0 能装但用不了
            # x86 x86_64 arm64 都有
            add_driver_gcp
            ;;
        esac

        # intel 网卡驱动
        # 官网没有提供 vista/2008 驱动
        # win7 驱动 inf/ndis 不支持 vista/2008
        if is_nt_ver_ge 6.1 && { [ "$arch_wim" = x86 ] || [ "$arch_wim" = x86_64 ]; } &&
            grep -iq 8086 /sys/class/net/e*/device/vendor; then
            add_driver_intel_nic
        fi

        # 自定义驱动
        add_driver_custom
    }

    add_driver_intel_nic() {
        info "Add drivers: Intel NIC"

        arch_intel=$(
            case "$arch_wim" in
            x86) echo 32 ;;
            x86_64) echo x64 ;;
            esac
        )

        file=$(
            case "$product_ver" in
            '7' | '2008 r2') $support_sha256 &&
                # 25.0 比 24.5 只更新了 ProSet 软件，驱动相同
                echo 18713/eng/prowin${arch_intel}legacy.exe || # 25.0 有部分文件是 sha256 签名
                echo 29323/eng/prowin${arch_intel}legacy.exe ;; # 24.3 sha1 签名
            # 之前有 Intel® Network Adapter Driver for Windows 8* - Final Release ，版本 22.7.1
            # 但已被删除，原因不明
            # https://web.archive.org/web/20250501043104/https://www.intel.com/content/www/us/en/download/16765/intel-network-adapter-driver-for-windows-8-final-release.html
            # 27.8 有 NDIS63 文件夹，意味着支持 Windows 8
            # 27.8 相比 22.7.1，可能有些老设备不支持了，但我们不管了
            '8' | '8.1') echo 764813/Wired_driver_27.8_${arch_intel}.zip ;;
            '2012' | '2012 r2') echo 772074/Wired_driver_28.0_${arch_intel}.zip ;;
            *) case "${arch_intel}" in
                32) echo 849483/Wired_driver_30.0.1_${arch_intel}.zip ;;
                x64) echo 864508/Wired_driver_30.4_${arch_intel}.zip ;;
                esac ;;
            esac
        )

        # 注意 intel 禁止了 aria2 下载
        download https://downloadmirror.intel.com/$file $drv/intel.zip

        # inf 可能是 UTF-16 LE？因此用 rg 搜索
        # 用 busybox unzip 解压 win10 驱动时，路径和文件名会粘在一起
        # 但解压 28.0 驱动时，依然会出现这个问题
        # 因此需要 convert_backslashes
        apk add unzip ripgrep

        # https://superuser.com/questions/1382839/zip-files-expand-with-backslashes-on-linux-no-subdirectories
        convert_backslashes() {
            for file in "$1"/*\\*; do
                if [ -f "$file" ]; then
                    target="${file//\\//}"
                    mkdir -p "${target%/*}"
                    mv -v "$file" "$target"
                fi
            done
        }

        # win7 驱动是 .exe 解压不会报错
        # win10 驱动是 .zip 解压反而会报错，目测 zip 文件有问题
        # 在 windows 下解压 win8 的驱动会提示 checksum 错误
        unzip -o -d $drv/intel/ $drv/intel.zip || true
        convert_backslashes $drv/intel

        is_have_inf_in_intel_dir() {
            find $drv/intel -ipath "*/*.inf" | grep . >/dev/null
        }

        # Wired_driver_28.0_x64.zip 需要二次解压
        if ! is_have_inf_in_intel_dir; then
            unzip -o -d $drv/intel/ $drv/intel/Wired_driver_*.exe || true
            convert_backslashes $drv/intel
        fi

        # 由于上面使用了 || true，因此确认下解压后是否有 inf 文件
        if ! is_have_inf_in_intel_dir; then
            error_and_exit "No .inf file found in intel driver package"
        fi

        # Vista RTM 版本号是 6000    NDIS 6.0
        # 2008  RTM 版本号是 6001    NDIS 6.1

        # 找出驱动文件夹对应的最低系统版本
        # 1. 驱动可能限制 windows client/server，但我们不区分
        #    如果装不了也没关系。如果能装但不加载，用户也可以在硬件管理器强制加载驱动
        # 2. 官网写着 win10 驱动要求 RS5 1809，但是驱动包里有 NDIS65 文件夹，也就是支持 10240
        # 3. 有可能 NDIS65 文件夹实际要求 NDIS 6.51？但是先不管
        # https://learn.microsoft.com/en-us/windows-hardware/drivers/network/overview-of-ndis-versions
        min_support_map=$(cat <<EOF |
6000  NDIS60
6001  NDIS61
7600  NDIS62
9200  NDIS63
9600  NDIS64
10240 NDIS65
14393 NDIS66
15063 NDIS67
16299 NDIS68
20348 WS2022
22000 W11
26100 WS2025
EOF
            case "$windows_type" in
            client) grep -E ' (NDIS|W)[0-9]' ;;
            server) grep -E ' (NDIS|WS)[0-9]' ;;
            esac)

        for ethx in $(get_eths); do
            sys_dir=$(get_sys_dir_for_eth $ethx)
            ven=$(cat $sys_dir/vendor | sed 's/^0x//')
            dev=$(cat $sys_dir/device | sed 's/^0x//')
            subsys=$(cat $sys_dir/subsystem_device $sys_dir/subsystem_vendor | sed 's/^0x//' | tr -d '\n')
            rev=$(cat $sys_dir/revision | sed 's/^0x//')

            info "intel nic"
            echo "Ethernet: $ethx"
            echo "Vendor: $ven"
            echo "Device: $dev"
            echo "Subsystem: $subsys"
            echo "Revision: $rev"

            compatible_ids="VEN_$ven&DEV_$dev&SUBSYS_$subsys&REV_$rev"
            compatible_ids="$compatible_ids|VEN_$ven&DEV_$dev&SUBSYS_$subsys"
            compatible_ids="$compatible_ids|VEN_$ven&DEV_$dev&REV_$rev"
            compatible_ids="$compatible_ids|VEN_$ven&DEV_$dev"

            while read -r min_ver ndis; do
                if [ "$build_ver" -ge "$min_ver" ]; then
                    # 只支持 PE?
                    # 有   intel\Release_30.0.zip\PROXGB\Win32\NDIS68\WinPE\*.inf
                    # 没有 intel\Release_30.0.zip\PROXGB\Win32\NDIS68\*.inf

                    # find 只要 $drv/intel 存在返回码就是 0
                    # rg 无需 -E
                    # 非 WinPE 优先
                    if infs=$(find $drv/intel -ipath "*/Win$arch_intel/$ndis/*.inf" -exec rg -iwl "$compatible_ids" {} \; | grep . ||
                        find $drv/intel -ipath "*/Win$arch_intel/$ndis/WinPE/*.inf" -exec rg -iwl "$compatible_ids" {} \; | grep .); then
                        for inf in $infs; do
                            cp_drivers $inf
                        done
                        break
                    fi
                fi
            done < <(echo "$min_support_map" | tac) # 倒序
        done

        apk del unzip ripgrep
    }

    # aws nitro
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/aws-nvme-drivers.html
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/enhanced-networking-ena.html
    add_driver_aws() {
        info "Add drivers: AWS"

        # 未打补丁的 win7 无法使用 sha256 签名的驱动
        nvme_ver=$(
            case "$nt_ver" in
            6.1) echo 1.3.2 ;; # sha1 签名
            6.2 | 6.3) echo 1.5.1 ;;
            *) echo Latest ;;
            esac
        )

        ena_ver=$(
            case "$nt_ver" in
            6.1) $support_sha256 && echo 2.2.3 || echo 2.1.4 ;;
            6.2 | 6.3) echo 2.6.0 ;;
            *) echo Latest ;;
            esac
        )

        [ "$arch_wim" = arm64 ] && arch_dir=/ARM64 || arch_dir=

        download "$(get_aws_repo)/NVMe$arch_dir/$nvme_ver/AWSNVMe.zip" $drv/AWSNVMe.zip
        download "$(get_aws_repo)/ENA$arch_dir/$ena_ver/AwsEnaNetworkDriver.zip" $drv/AwsEnaNetworkDriver.zip

        unzip -o -d $drv/aws/ $drv/AWSNVMe.zip
        unzip -o -d $drv/aws/ $drv/AwsEnaNetworkDriver.zip

        cp_drivers $drv/aws
    }

    # citrix xen
    add_driver_citrix_xen() {
        info "Add drivers: Citrix Xen"

        apk add 7zip
        download https://s3.amazonaws.com/ec2-downloads-windows/Drivers/Citrix-Win_PV.zip $drv/Citrix-Win_PV.zip
        unzip -o -d $drv $drv/Citrix-Win_PV.zip
        case "$arch_wim" in
        x86) override=s ;;    # skip
        x86_64) override=a ;; # always
        esac
        # 排除 $PLUGINSDIR $TEMP
        exclude='$*'
        7z x $drv/Citrix_xensetup.exe -o$drv/xen/ -ao$override -x!$exclude

        cp_drivers $drv/xen
    }

    # aws xen
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/xen-drivers-overview.html
    add_driver_aws_xen() {
        info "Add drivers: AWS Xen"

        apk add msitools

        # 8.4.3 的 xenbus 挑创建实例时的初始系统
        # 初始系统为 windows 的实例支持 8.4.3
        # 初始系统为 linux 的实例不支持 8.4.3

        # 初始系统为 linux + 安装 8.4.3
        # 如果用 msi 安装，则不会启用 xenbus，结果是能启动但无法上网
        # 如果通过 inf 安装，则会启用 xenbus，结果是无法启动

        apk add lscpu
        hypervisor_vendor=$(lscpu | grep 'Hypervisor vendor:' | awk '{print $3}')
        apk del lscpu

        aws_pv_ver=$(
            case "$nt_ver" in
            6.1) $support_sha256 && echo 8.3.5 || echo 8.3.2 ;;
            6.2 | 6.3)
                case "$hypervisor_vendor" in
                Microsoft) echo 8.4.3 ;; # 实例初始系统为 Windows，能使用 8.4.3
                Xen) echo 8.3.5 ;;       # 实例初始系统为 Linux，不能使用 8.4.3
                esac
                ;;
            *) echo Latest ;;
            esac
        )

        url=$(
            case "$aws_pv_ver" in
            8.3.2) echo https://web.archive.org/web/20221016194548/https://s3.amazonaws.com/ec2-windows-drivers-downloads/AWSPV/$aws_pv_ver/AWSPVDriver.zip ;; # win7 sha1
            *) echo "$(get_aws_repo)/AWSPV/$aws_pv_ver/AWSPVDriver.zip" ;;
            esac
        )

        download "$url" $drv/AWSPVDriver.zip

        unzip -o -d $drv $drv/AWSPVDriver.zip
        mkdir -p $drv/xen/
        msiextract $drv/AWSPVDriverSetup.msi -C $drv/xen/

        cp_drivers $drv/xen/.Drivers
    }

    # citrix xen
    # https://pvupdates.vmd.citrix.com/updates.json 7.2.0.1555
    # https://pvupdates.vmd.citrix.com/updates.v9.json 9.3.3.125
    # https://pvupdates.vmd.citrix.com/autoupdate.v1.json 9.3.3.125
    # https://pvupdates.vmd.citrix.com/autoupdate.v2.json 9.4.0.146
    # https://support.citrix.com/s/article/CTX235403-updates-to-xenserver-vm-tools-for-windows-for-xenserver-and-citrix-hypervisor

    # 最高版本
    # 2012 r2   9.3.1
    # 2012      9.3.0
    # 2008 (r2) 7.2.0.1555

    # 9.3.1
    # https://downloads.xenserver.com/vm-tools-windows/9.3.1/managementagentx64.msi
    # http://downloadns.citrix.com.edgesuite.net/17461/managementagentx64.msi

    # 7.2.0.1555
    # http://downloadns.citrix.com.edgesuite.net/14656/managementagentx64.msi
    # http://downloadns.citrix.com.edgesuite.net/14655/managementagentx86.msi

    # xen
    # 没签名，暂时用aws的驱动代替
    # https://lore.kernel.org/xen-devel/E1qKMmq-00035B-SS@xenbits.xenproject.org/
    # https://xenbits.xenproject.org/pvdrivers/win/
    # 在 aws t2 上测试，安装 xenbus 会蓝屏，装了其他7个驱动后，能进系统但没网络
    # 但 aws 应该用aws官方xen驱动，所以测试仅供参考
    add_driver_generic_xen() {
        info "Add drivers: Generic Xen"

        parts='xenbus xencons xenhid xeniface xennet xenvbd xenvif xenvkbd'
        mkdir -p $drv/xen/
        for part in $parts; do
            download https://xenbits.xenproject.org/pvdrivers/win/$part.tar $drv/$part.tar
            tar -xf $drv/$part.tar -C $drv/xen/
        done

        cp_drivers $drv/xen -ipath "*/$arch_xdd/*"
    }

    # virtio
    # https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/
    add_driver_generic_virtio() {
        info "Add drivers: Generic virtio"

        # 要区分 win10 / win11 驱动，虽然他们的 NT 版本号都是 10.0，但驱动文件有区别
        # https://github.com/virtio-win/kvm-guest-drivers-windows/commit/9af43da9e16e2d4bf4ea4663cdc4f29275fff48f
        # vista >>> 2k8
        # 10 >>> w10
        # 2012 r2 >>> 2k12R2
        virtio_sys=$(
            case "$(echo "$product_ver" | to_lower)" in
            'vista') echo 2k8 ;; # 没有 vista 文件夹
            *)
                case "$windows_type" in
                client) echo "w$product_ver" ;;
                server) echo "$product_ver" | sed -E -e 's/ //' -e 's/^200?/2k/' -e 's/r2/R2/' ;;
                esac
                ;;
            esac
        )

        # win7-drivers 分支 win7 文件夹只有一次提交，也就是 173 全家桶
        # 1. 2020.1.24 https://github.com/virtio-win/virtio-win-pkg-scripts/tree/win7-drivers/data/old-drivers/Win7

        # master 分支 win7 文件夹有 3 次提交，从古到今
        # https://github.com/virtio-win/virtio-win-pkg-scripts/commits/master/data/old-drivers/Win7
        # 1. 2020/6/4  sha256，176 全家桶，相当于没发布的 176 iso
        # 2. 2020/8/10 将部分文件降到 17400，相当于 189~215 iso
        # 3. 2022/4/14 将部分文件降级，相当于 217~最新版 iso

        # 可改成直接从 github commit 下载 win7 173(sha1) 176(sha256) 全家桶？
        # 国内可使用 jsdelivr 加速 github

        # 2k12
        # https://github.com/virtio-win/virtio-win-pkg-scripts/issues/61
        # 217 ~ 271    2k12 证书有问题，红帽的 virtio-win-1.9.45 没问题

        # win7
        # https://fedorapeople.org/groups/virt/virtio-win/repo/stable/
        # https://github.com/virtio-win/virtio-win-pkg-scripts/issues/40
        # 171-1     sha1   稳定版
        # 173-9     sha1   对应上面的 win7-drivers 分支，最后一次编译 win7 + sha1，但不是稳定版?
        # 176       sha256 对应上面的 master-1  最后一次编译 win7，从这次开始是 sha256，此次不提供 iso，编译的文件在之后的 iso 可以找到
        # 185 ~ 187 sha256 正常工作，win7 文件来自 176
        # 189 ~ 215 sha1   对应上面的 master-2  气球版本 17400，vultr 死机
        # 217 ~ 271 sha1   对应上面的 master-3  甲骨文 vioscsi 因硬件 ID 不同用不了，红帽的 virtio-win-1.9.45 也是

        # 甲骨文 vioscsi 硬件 ID 是 PCI\VEN_1AF4&DEV_1004&SUBSYS_0008108E&REV_00
        # SUBSYS 的厂商 ID 是甲骨文

        # virtio-win-0.1.173-9
        # %VirtioScsi.DeviceDesc% = scsi_inst, PCI\VEN_1AF4&DEV_1004&SUBSYS_00081AF4&REV_00, PCI\VEN_1AF4&DEV_1004
        # %VirtioScsi.DeviceDesc% = scsi_inst, PCI\VEN_1AF4&DEV_1048&SUBSYS_11001AF4&REV_01, PCI\VEN_1AF4&DEV_1048

        # stable-virtio
        # %RHELScsi.DeviceDesc% = rhelscsi_inst, PCI\VEN_1AF4&DEV_1004&SUBSYS_00081AF4&REV_00
        # %RHELScsi.DeviceDesc% = rhelscsi_inst, PCI\VEN_1AF4&DEV_1048&SUBSYS_11001AF4&REV_01

        case "$nt_ver" in
        6.0 | 6.1) $support_sha256 &&
            dir=archive-virtio/virtio-win-0.1.187-1 ||
            dir=archive-virtio/virtio-win-0.1.173-9 ;;        # vista|w7|2k8|2k8R2
        6.2 | 6.3) dir=archive-virtio/virtio-win-0.1.215-2 ;; # w8|w8.1|2k12|2k12R2
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

            # vista 如果安装气动驱动，会报错 windows could not configure one or more system components
            # 2008 安装的气球驱动不能用，需要到硬件管理器重新安装设备才能用，无需更新驱动
            if [ "$product_ver" = vista ]; then
                cp_drivers $drv/virtio -ipath "*/$virtio_sys/$arch/*" "$@" -not -ipath "*/balloon/*"
            else
                cp_drivers $drv/virtio -ipath "*/$virtio_sys/$arch/*" "$@"
            fi
        else
            # coreutils 的 cp mv rm 才有 -v 参数
            apk add 7zip file coreutils
            download $baseurl/$dir/virtio-win-gt-$arch_xdd.msi $drv/virtio.msi
            match="FILE_*_${virtio_sys}_${arch}*"
            7z x $drv/virtio.msi -o$drv/virtio -i!$match -y -bb1

            # 为没有后缀名的文件添加后缀名
            (
                cd $drv/virtio
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
            cp_drivers $drv/virtio "$@"
        fi
    }

    add_driver_qcloud_virtio() {
        info "Add drivers: QCloud virtio"

        # 测试版?
        # https://mirrors.tencent.com/install/cts/windows/Drivers.zip

        apk add 7zip
        download https://mirrors.tencent.com/install/windows/virtio_64_1.0.9.exe $drv/virtio.exe
        exclude='$*' # 排除 $PLUGINSDIR
        override=u   # A(u)to rename all
        7z x $drv/virtio.exe -o$drv/qcloud/ -ao$override -x!$exclude

        # balloon     6.2
        # balloon_1   6.1

        # netkvm      10.0
        # netkvm_1    6.1
        # netkvm_2    6.3

        # viostor     10.0
        # viostor_1   6.1
        # viostor_2   6.2

        drivers=$(
            case "$nt_ver" in
            6.1) echo balloon_1 netkvm_1 viostor_1 ;; # sha1
            6.2) echo balloon netkvm_1 viostor_2 ;;
            6.3) echo balloon netkvm_2 viostor_2 ;;
            *) echo balloon netkvm viostor ;;
            esac
        )

        for old_name in $drivers; do
            part=${old_name%%_*}
            if ! [ "$old_name" = "$part" ]; then
                find $drv/qcloud/$part -type f -iname "$old_name.*" | while read -r file; do
                    ext="${file##*.}"
                    mv -v "$file" "$drv/qcloud/$part/$part.$ext"
                done
            fi
            cp_drivers $drv/qcloud/$part/$part.inf
        done
    }

    add_driver_huawei_virtio() {
        info "Add drivers: Huawei virtio"

        huawei_sys=$(
            case "$(echo "$product_ver" | to_lower)" in
            vista) echo Vista2008 ;;
            7) echo 7 ;;
            8) [ "$arch_wim" = x86 ] && echo 7 || echo 2012 ;;      # 没有 win8 32/64
            8.1) [ "$arch_wim" = x86 ] && echo 7 || echo 2012_R2 ;; # 没有 win8.1 32/64
            10 | 11) echo 10 ;;
            2008) echo Vista2008 ;;
            '2008 r2') echo 2008_R2 ;;
            2012) [ "$arch_wim" = x86 ] && echo 2008_R2 || echo 2012 ;; # 没有 2012 32
            '2012 r2') echo 2012_R2 ;;
            2016 | 2019 | 202*) echo 2016 ;;
            esac
        )

        download https://ecs-instance-driver.obs.cn-north-1.myhuaweicloud.com/vmtools-windows.zip $drv/vmtools-windows.zip
        unzip -o -d $drv $drv/vmtools-windows.zip
        mkdir -p $drv/huawei
        mount -o ro $drv/vmtools-windows.iso $drv/huawei

        cp_drivers $drv/huawei -ipath "*/upgrade/windows ${huawei_sys}_${arch_dd}/drivers/*"
    }

    add_driver_aliyun_virtio() {
        info "Add drivers: Aliyun virtio"

        aliyun_sys=$(
            case "$nt_ver" in
            6.1) echo 2008R2 ;;
            6.2 | 6.3) echo 2012R2 ;; # 实际上是 2012 的驱动
            *) echo 2016 ;;
            esac
        )

        subdir=
        if [ "$nt_ver" = 6.1 ] && ! $support_sha256; then
            subdir=58017/ # sha1
        fi

        region=cn-hangzhou

        download https://windows-driver-$region.oss-$region.aliyuncs.com/virtio/${subdir}AliyunVirtio_WIN$aliyun_sys.zip \
            $drv/AliyunVirtio.zip
        unzip -o -d $drv $drv/AliyunVirtio.zip

        apk add innoextract
        innoextract -d $drv/aliyun/ $drv/AliyunVirtio_*_WIN${aliyun_sys}_$arch_xdd.exe
        apk del innoextract

        cp_drivers $drv/aliyun -ipath "*/C$/Program Files/AliyunVirtio/*/drivers/*"
    }

    # gcp virtio win7 x64 sha1
    # 缺 balloon viorng
    add_driver_gcp_virtio_win6_1_sha1_x64() {
        info "Add drivers: GCP virtio win6.1 sha1 x64"

        # 用到 nvme 时才下载 nvme 驱动
        # 因为 win7 可以通过更新获得 nvme 驱动
        # 而且谷歌推荐使用微软 nvme 驱动
        # (google-compute-engine-driver-nvme 2.0.0 更新内容是删除谷歌 nvme 驱动)
        mkdir -p $drv/gce/win6.1sha1
        for file in \
            WdfCoInstaller01009.dll WdfCoInstaller01011.dll \
            netkvm.inf netkvm.cat netkvm.sys netkvmco.dll \
            pvpanic.inf pvpanic.sys pvpanic.cat \
            vioscsi.inf vioscsi.sys vioscsi.cat \
            $([ -d /sys/module/nvme ] && ! $has_stornvme && echo nvme.inf nvme64.cat nvme.sys); do
            download https://storage.googleapis.com/gce-windows-drivers-public/win6.1sha1/$file $drv/gce/win6.1sha1/$file
        done
        cp_drivers $drv/gce/win6.1sha1
    }

    # gcp virtio win7+ sha256
    # x86 缺 viorng pvpanic
    # x64 缺 viorng
    # https://github.com/GoogleCloudPlatform/compute-image-tools/tree/master/daisy_workflows/image_build/windows
    # 官方是从 https://console.cloud.google.com/storage/browser/gce-windows-drivers-public 下载驱动，安装系统后再 googet 更新驱动
    # 我们一步到位从 googet 下载驱动
    add_driver_gcp_virtio() {
        info "Add drivers: GCP virtio"

        mkdir -p $drv/gce
        gce_repo=https://packages.cloud.google.com/yuck
        download $gce_repo/repos/google-compute-engine-stable/index $drv/gce/gce.json
        for part in balloon netkvm pvpanic vioscsi; do
            # gcp 提供的 pvpanic 没有 x86 驱动
            if [ "$part" = pvpanic ] && [ "$arch_wim" = x86 ]; then
                continue
            fi

            mkdir -p $drv/gce/$part
            link=$(grep -o "/pool/.*-google-compute-engine-driver-$part.*\.goo" $drv/gce/gce.json)
            wget $gce_repo$link -O- | tar xz -C $drv/gce/$part

            [ "$arch_wim" = x86 ] && suffix=-32 || suffix=
            cp_drivers $drv/gce/$part -ipath "*/win$nt_ver$suffix/*"
        done
    }

    # gcp
    # x86 x86_64 arm64 都有
    # win7 驱动是 sha256 签名
    add_driver_gcp() {
        info "Add drivers: GCP"

        # https://packages.cloud.google.com/yuck/repos/google-compute-engine-stable/index
        # https://packages.cloud.google.com/yuck/repos/google-compute-engine-driver-gvnic-gq-stable/index
        # 官方镜像的 gvnic 是从 gvnic-gq-stable 获取的，版本低一点，但更稳定?

        mkdir -p $drv/gce
        gce_repo=https://packages.cloud.google.com/yuck
        download $gce_repo/repos/google-compute-engine-stable/index $drv/gce/gce.json
        for part in gvnic gga; do
            # gvnic 没有 arm64
            if [ "$part" = gvnic ] && [ "$arch_wim" = arm64 ]; then
                continue
            fi

            mkdir -p $drv/gce/$part
            link=$(grep -o "/pool/.*-google-compute-engine-driver-$part.*\.goo" $drv/gce/gce.json)
            wget $gce_repo$link -O- | tar xz -C $drv/gce/$part

            # inf 不限版本
            # 但 win7 gvnic ndis 版本是 6.2，vista/2008 能装但用不了
            # https://github.com/GoogleCloudPlatform/compute-virtual-ethernet-windows/blob/cad1edf7a05465f4972a81f2c015952fd228b5e3/src/gvnic.vcxproj#L298
            if false; then
                for suffix in '' '-32'; do
                    if [ -d "$drv/gce/$part/win6.1$suffix" ]; then
                        cp -r "$drv/gce/$part/win6.1$suffix" "$drv/gce/$part/win6.0$suffix"
                    fi
                done
            fi

            case "$part" in
            gvnic)
                [ "$arch_wim" = x86 ] && suffix=-32 || suffix=
                cp_drivers $drv/gce/gvnic -ipath "*/win$nt_ver$suffix/*"
                ;;
            gga)
                cp_drivers $drv/gce/gga -ipath "*/win$nt_ver/*"
                ;;
            esac
        done
    }

    # azure
    # https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-windows
    add_driver_azure() {
        info "Add drivers: Azure"

        download https://aka.ms/manawindowsdrivers $drv/azure.zip
        unzip $drv/azure.zip -d $drv/azure/
        cp_drivers $drv/azure
    }

    add_driver_vmd() {
        # RST v20 不支持 11代 PCI\VEN_8086&DEV_9A0B
        is_gen11=false
        for d in /sys/bus/pci/devices/*; do
            vendor=$(cat "$d/vendor" 2>/dev/null)
            device=$(cat "$d/device" 2>/dev/null)
            if [ "$vendor" = "0x8086" ] && [ "$device" = "0x9a0b" ]; then
                is_gen11=true
                break
            fi
        done

        if ! $is_gen11 && [ "$build_ver" -ge 19041 ]; then
            url=https://downloadmirror.intel.com/865363/SetupRST.exe # RST v20
        elif [ "$build_ver" -ge 15063 ]; then
            url=https://downloadmirror.intel.com/849934/SetupRST.exe # RST v19
        else
            error_and_exit "can't find suitable vmd driver"
        fi

        # 注意 intel 禁止了 aria2 下载
        download $url $drv/SetupRST.exe
        apk add 7zip
        7z x $drv/SetupRST.exe -o$drv/SetupRST -i!.text
        7z x $drv/SetupRST/.text -o$drv/vmd
        apk del 7zip
        cp_drivers $drv/vmd
    }

    # 脚本自动检测驱动可能有问题
    # 假设是 win7 时代的网卡，官网没有 win10 驱动，系统也不自带
    # 但实际上 win10 可以用 win7 的驱动
    # 这种情况即使脚本自动下载 win10 的驱动包，也不会包含这个驱动
    # 应该下载 win7 的驱动
    # 因此只能交给用户自己添加驱动

    add_driver_custom() {
        if [ -d /custom_drivers/ ]; then
            cp_drivers custom /custom_drivers/
            # 复制后不删除，因为脚本可能再次运行
        fi
    }

    # 修改应答文件
    download $confhome/windows.xml /tmp/autounattend.xml
    locale=$(get_selected_image_prop 'Default Language')
    use_default_rdp_port=$(is_need_change_rdp_port && echo false || echo true)
    password_base64=$(get_password_windows_administrator_base64)
    # 7601.24214.180801-1700.win7sp1_ldr_escrow_CLIENT_ULTIMATE_x64FRE_en-us.iso Image Name 为空
    # 将 xml Image Name 的值设为空可以正常安装
    sed -i \
        -e "s|%arch%|$arch|" \
        -e "s|%image_name%|$image_name|" \
        -e "s|%locale%|$locale|" \
        -e "s|%administrator_password%|$password_base64|" \
        -e "s|%use_default_rdp_port%|$use_default_rdp_port|" \
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
    if [ "$product_ver" = vista ]; then
        # vista 无人值守安装需要密钥，密钥可与 edition 不一致
        # https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys
        # 从镜像获取默认密钥
        setup_cfg=$(get_path_in_correct_case /os/installer/sources/inf/setup.cfg)
        key=$(del_cr <"$setup_cfg" | grep -Eix 'Value=([A-Z0-9]{5}-){4}[A-Z0-9]{5}' | cut -d= -f2 | grep .)
        sed -i "s/%key%/$key/" /tmp/autounattend.xml
    else
        if [ -f "$(get_path_in_correct_case /os/installer/sources/ei.cfg)" ]; then
            # 镜像有 ei.cfg，删除 key 字段
            sed -i "/%key%/d" /tmp/autounattend.xml
        else
            # 镜像无 ei.cfg，填空白 key
            sed -i "s/%key%//" /tmp/autounattend.xml
        fi
    fi

    # 挂载 boot.wim
    info "mount boot.wim"
    wimmountrw /os/boot.wim "$boot_index" /wim/

    # 防止重复
    copyed_infs=
    cp_drivers() {
        if [ "$1" = custom ]; then
            shift
            dst=$(get_path_in_correct_case "/wim/custom_drivers")
        else
            dst=$(get_path_in_correct_case "/wim/drivers")
        fi

        src=$1
        shift

        # -not -iname "*.pdb" \
        # -not -iname "dpinst.exe" \

        # 这里需要在 while 里面变更 $copyed_infs，因此不能用 find | while
        while read -r inf; do
            if ! is_list_has "$copyed_infs" "$inf"; then
                parse_inf_and_cp_driever "$inf" "$dst" "$arch" false
                copyed_infs=$(list_add "$copyed_infs" "$inf")
            fi
        done < <(find $src -type f -iname "*.inf" "$@")
    }

    # 添加驱动
    add_drivers

    # win7 要添加 bootx64.efi 到 efi 目录
    if is_efi; then
        [ $arch = amd64 ] && boot_efi=bootx64.efi || boot_efi=bootaa64.efi

        local src dst
        dst=$(get_path_in_correct_case /os/boot/efi/EFI/boot/$boot_efi)
        if ! [ -f $dst ]; then
            mkdir -p "$(dirname $dst)"
            src=$(get_path_in_correct_case /wim/Windows/Boot/EFI/bootmgfw.efi)
            cp "$src" "$dst"
        fi
    fi

    # 复制应答文件
    # 移除注释，否则 windows-setup.bat 重新生成的 autounattend.xml 有问题
    wim_autounattend_xml=$(get_path_in_correct_case /wim/autounattend.xml)
    wim_windows_xml=$(get_path_in_correct_case /wim/windows.xml)
    wim_setup_exe=$(get_path_in_correct_case /wim/setup.exe)

    apk add xmlstarlet
    xmlstarlet ed -d '//comment()' /tmp/autounattend.xml >$wim_autounattend_xml
    unix2dos $wim_autounattend_xml
    info "autounattend.xml"
    # 查看最终文件，并屏蔽密码
    xmlstarlet ed -d '//*[name()="AdministratorPassword" or name()="Password"]' $wim_autounattend_xml | cat -n
    apk del xmlstarlet

    # 避免无参数运行 setup.exe 时自动安装
    mv $wim_autounattend_xml $wim_windows_xml

    # 复制安装脚本
    # https://slightlyovercomplicated.com/2016/11/07/windows-pe-startup-sequence-explained/
    # https://learn.microsoft.com/previous-versions/windows/it-pro/windows-vista/cc721977(v=ws.10)
    mv $wim_setup_exe $wim_setup_exe.disabled

    # 如果有重复的 Windows/System32 文件夹，会提示找不到 winload.exe 无法引导
    # win7 win10  boot.wim 是 Windows/System32，install.wim 是 Windows/System32
    # win2016     boot.wim 是 windows/system32，install.wim 是 Windows/System32
    # wimmount 无法挂载成忽略大小写

    startnet_cmd=$(get_path_in_correct_case /wim/Windows/System32/startnet.cmd)
    winpeshl_ini=$(get_path_in_correct_case /wim/Windows/System32/winpeshl.ini)

    download $confhome/windows-setup.bat $startnet_cmd
    # dism 手动释放镜像时用
    # sed -i "s|@image_name@|$image_name|" "$startnet.cmd"

    # shellcheck disable=SC2154
    if [ "$force_old_windows_setup" = 1 ]; then
        sed -i 's/ForceOldSetup=0/ForceOldSetup=1/i' $startnet_cmd
    fi

    # 有 SAC 组件时，启用 EMS
    if $has_sac; then
        sed -i 's/EnableEMS=0/EnableEMS=1/i' $startnet_cmd
    fi

    # 4kn EFI 分区最少要 260M
    # https://learn.microsoft.com/windows-hardware/manufacture/desktop/hard-drives-and-partitions
    if is_4kn /dev/$xda; then
        sed -i 's/is4kn=0/is4kn=1/i' $startnet_cmd
    fi

    # Windows Thin PC 有 Windows\System32\winpeshl.ini
    # [LaunchApps]
    # %SYSTEMDRIVE%\windows\system32\drvload.exe, %SYSTEMDRIVE%\windows\inf\sdbus.inf
    # %SYSTEMDRIVE%\setup.exe
    if [ -f "$winpeshl_ini" ]; then
        info "mod winpeshl.ini"
        # https://learn.microsoft.com/previous-versions/windows/it-pro/windows-vista/cc721977(v=ws.10)
        # 两种方法都可以，第一种是原版命令
        sed -i 's|setup.exe|windows\\system32\\cmd.exe, "/k %SYSTEMROOT%\\system32\\startnet.cmd"|i' "$winpeshl_ini"
        # sed -i 's|setup.exe|windows\\system32\\startnet.cmd|i' "$winpeshl_ini"
        cat -n "$winpeshl_ini"
    fi

    # 提交修改 boot.wim
    info "Unmount boot.wim"
    wimunmount --commit /wim/

    # 原地优化可以用以下命令之一
    # wimdelete /os/boot.wim 1
    # wimoptimize /os/boot.wim

    # 优化 boot.wim 并复制到正确的位置
    if is_nt_ver_ge 6.1; then
        # win7 或以上删除 boot.wim 镜像 1 不会报错
        # 因为 win7 winre 镜像在 install.wim Windows\System32\Recovery\winRE.wim
        images=$boot_index
    else
        # vista 删除 boot.wim 镜像 1 会报错
        # Windows cannot access the required file Drive:\Sources\Boot.wim.
        # Make sure all files required for installation are available and restart the installation.
        # Error code: 0x80070491
        # vista install.wim 没有 Windows\System32\Recovery\winRE.wim
        images=all
    fi
    mkdir -p "$(get_path_in_correct_case "$(dirname $boot_dir/$sources_boot_wim)")"
    wimexport --boot /os/boot.wim "$images" $boot_dir/$sources_boot_wim
    info "boot.wim size"
    echo "Original:      $(get_filesize_mb /iso/$sources_boot_wim)"
    echo "Added Drivers: $(get_filesize_mb /os/boot.wim)"
    echo "Optimized:     $(get_filesize_mb "$boot_dir/$sources_boot_wim")"
    echo

    # vista 安装时需要 boot.wim，原因见上面
    if [ "$nt_ver" = 6.0 ] &&
        ! [ -e /os/installer/$sources_boot_wim ]; then
        cp $boot_dir/$sources_boot_wim /os/installer/$sources_boot_wim
    fi

    # windows 7 没有 invoke-webrequest
    # installer分区盘符不一定是D盘
    # 所以复制 resize.bat 到 install.wim
    if true; then
        info "mount install.wim"
        wimmountrw $install_wim "$image_index" /wim/
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

        info "Unmount install.wim"
        wimunmount --commit /wim/
    fi

    # 添加引导
    if is_efi; then
        # 现在 add_default_efi_to_nvram() 添加 bootx64.efi 到最前面
        # 因此这里重复了
        if false; then
            apk add efibootmgr
            efibootmgr -c -L "Windows Installer" -d /dev/$xda -p1 -l "\\EFI\\boot\\$boot_efi"
        fi
    else
        # 或者用 ms-sys
        apk add grub-bios
        # efi 下，强制安装 mbr 引导，需要添加 --target i386-pc
        grub-install --target i386-pc --boot-directory=/os/boot /dev/$xda
        cat <<EOF >/os/boot/grub/grub.cfg
            set timeout=5
            menuentry "reinstall" {
                search --no-floppy --label --set=root os
                ntldr /bootmgr
            }
EOF
    fi
}

# 添加 netboot.efi 备用
download_netboot_xyz_efi() {
    dir=$1
    info "download netboot.xyz.efi"

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

sync_time() {
    if false; then
        # arm要手动从硬件同步时间，避免访问https出错
        # do 机器第二次运行会报错
        hwclock -s || true
    fi

    # ntp 时间差太多会无法同步？
    # http 时间可能不准确，毕竟不是专门的时间服务器
    #      也有可能没有 date header?
    method=http

    case "$method" in
    ntp)
        if is_in_china; then
            ntp_server=ntp.aliyun.com
        else
            ntp_server=pool.ntp.org
        fi
        # -d[d]   Verbose
        # -n      Run in foreground
        # -q      Quit after clock is set
        # -p      PEER
        ntpd -d -n -q -p "$ntp_server"
        ;;
    http)
        url="$(grep -m1 ^http /etc/apk/repositories)/$(uname -m)/APKINDEX.tar.gz"
        # 可能有多行，取第一行
        date_header=$(wget -S --no-check-certificate --spider "$url" 2>&1 | grep -m1 '^  Date:')
        # gnu date 不支持 -D
        busybox date -u -D "  Date: %a, %d %b %Y %H:%M:%S GMT" -s "$date_header"
        ;;
    esac

    # 重启时 alpine 会自动写入到硬件时钟，因此这里跳过
    # hwclock -w
}

is_ubuntu_lts() {
    IFS=. read -r major minor < <(echo "$releasever")
    [ $((major % 2)) = 0 ] && [ $minor = 04 ]
}

get_ubuntu_kernel_flavor() {
    # 20.04/22.04 kvm 内核 vnc 没显示
    # 24.04 kvm = virtual
    # linux-image-virtual = linux-image-6.x-generic
    # linux-image-generic = linux-image-6.x-generic + amd64-microcode + intel-microcode + linux-firmware + linux-modules-extra-generic

    # TODO: ISO virtual-hwe-24.04 不安装 linux-image-extra-virtual-hwe-24.04 不然会花屏

    # https://github.com/systemd/systemd/blob/main/src/basic/virt.c
    # https://github.com/canonical/cloud-init/blob/main/tools/ds-identify
    # http://git.annexia.org/?p=virt-what.git;a=blob;f=virt-what.in;hb=HEAD
    if [ "$releasever" = 16.04 ]; then
        if is_virt; then
            echo virtual-hwe-$releasever
        else
            echo generic-hwe-$releasever
        fi
    else
        # 这里有坑
        # $(get_cloud_vendor) 调用了 cache_dmi_and_virt
        # 但是 $(get_cloud_vendor) 运行在 subshell 里面
        # subshell 运行结束后里面的变量就消失了
        # 因此先运行 cache_dmi_and_virt
        cache_dmi_and_virt
        vendor="$(get_cloud_vendor)"
        case "$vendor" in
        aws | gcp | oracle | azure | ibm) echo $vendor ;;
        *)
            is_ubuntu_lts && suffix=-hwe-$releasever || suffix=
            if is_virt; then
                echo virtual$suffix
            else
                echo generic$suffix
            fi
            ;;
        esac
    fi
}

install_redhat_ubuntu() {
    info "Download iso installer"

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
        if [[ "$var" = "extra_main_disk=*" ]]; then
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
        mkdir -p /iso
        mount -o ro /os/installer/ubuntu.iso /iso

        # 内核风味
        kernel=$(get_ubuntu_kernel_flavor)

        # 要安装的版本
        # https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#id
        # 20.04 不能选择 minimal ，也没有 install-sources.yaml
        source_id=
        if [ -f /iso/casper/install-sources.yaml ]; then
            ids=$(grep id: /iso/casper/install-sources.yaml | awk '{print $2}')
            if [ "$(echo "$ids" | wc -l)" = 1 ]; then
                source_id=$ids
            else
                [ "$minimal" = 1 ] && v= || v=-v
                source_id=$(echo "$ids" | grep $v '\-minimal')

                if [ "$(echo "$source_id" | wc -l)" -gt 1 ]; then
                    error_and_exit "find multi source id."
                fi
            fi
        fi

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
            linux (loop)/casper/vmlinuz iso-scan/filename=/ubuntu.iso autoinstall noprompt noeject cloud-config-url=$ks $extra_cmdline extra_kernel=$kernel extra_source_id=$source_id --- $console_cmdline
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

trans() {
    info "start trans"

    mod_motd

    # 先检查 modloop 是否正常
    # 防止格式化硬盘后，缺少 ext4 模块导致 mount 失败
    # https://github.com/bin456789/reinstall/issues/136
    ensure_service_started modloop

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
        setup_web_if_enough_ram
        # util-linux 包含 lsblk
        # util-linux 可自动探测 mount 格式
        apk add util-linux
    fi

    # dd qemu 切换成云镜像模式，暂时没用到
    # shellcheck disable=SC2154
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
            centos | almalinux | rocky | oracle | redhat | anolis | opencloudos | openeuler)
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
        raw)
            # 暂时没用到 raw 格式的云镜像
            dd_raw_with_extract
            resize_after_install_cloud_image
            modify_os_on_disk linux
            ;;
        esac
    elif [ "$distro" = "dd" ]; then
        case "$img_type" in
        raw)
            dd_raw_with_extract
            if false; then
                # linux 扩容后无法轻易缩小，例如 xfs
                # windows 扩容在 windows 下完成
                resize_after_install_cloud_image
            fi
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
        arch | gentoo | aosc)
            create_part
            install_arch_gentoo_aosc
            ;;
        nixos)
            create_part
            install_nixos
            ;;
        fnos)
            create_part
            install_fnos
            ;;
        *)
            create_part
            mount_part_for_iso_installer
            case "$distro" in
            centos | almalinux | rocky | fedora | ubuntu | redhat) install_redhat_ubuntu ;;
            windows) install_windows ;;
            esac
            ;;
        esac
    fi

    # 需要用到 lsblk efibootmgr ，只要 1M 左右容量
    # 因此 alpine 不单独处理
    if is_efi; then
        del_invalid_efi_entry
        add_default_efi_to_nvram
    fi

    info 'done'
    # 让 web 输出全部内容
    sleep 5
}

# 脚本入口
# debian initrd 会寻找 main
# 并调用本文件的 create_ifupdown_config 方法
: main

# 复制脚本
# 用于打印错误或者再次运行
# 路径相同则不用复制
# 重点：要在删除脚本之前复制
if ! [ "$(readlink -f "$0")" = /trans.sh ]; then
    cp -f "$0" /trans.sh
fi
trap 'trap_err $LINENO $?' ERR

# 删除本脚本，不然会被复制到新系统
rm -f /etc/local.d/trans.start
rm -f /etc/runlevels/default/local

# 提取变量
extract_env_from_cmdline

# 带参数运行部分
# 重新下载并 exec 运行新脚本
if [ "$1" = "update" ]; then
    info 'update script'
    # shellcheck disable=SC2154
    wget -O /trans.sh "$confhome/trans.sh"
    chmod +x /trans.sh
    exec /trans.sh
elif [ "$1" = "alpine" ]; then
    info 'switch to alpine'
    distro=alpine
    # 后面的步骤很多都会用到这个，例如分区布局
    cloud_image=0
elif [ -n "$1" ]; then
    error_and_exit "unknown option $1"
fi

# 无参数运行部分
# 允许 ramdisk 使用所有内存，默认是 50%
mount / -o remount,size=100%

# 同步时间
# 1. 可以防止访问 https 出错
# 2. 可以防止 https://github.com/bin456789/reinstall/issues/223
#    E: Release file for http://security.ubuntu.com/ubuntu/dists/noble-security/InRelease is not valid yet (invalid for another 5h 37min 18s).
#    Updates for this repository will not be applied.
# 3. 不能直接读取 rtc，因为默认情况 windows rtc 是本地时间，linux rtc 是 utc 时间
# 4. 允许同步失败，因为不是关键步骤
sync_time || true

# 安装 ssh 并更改端口
apk add openssh
if is_need_change_ssh_port; then
    change_ssh_port / $ssh_port
fi

# 设置密码，添加开机启动 + 开启 ssh 服务
if is_need_set_ssh_keys; then
    set_ssh_keys_and_del_password /
    printf '\n' | setup-sshd
else
    change_root_password /
    printf '\nyes' | setup-sshd
fi

# 设置 frpc
# 并防止重复运行
if [ -s /configs/frpc.toml ] && ! pidof frpc >/dev/null; then
    info 'run frpc'
    add_community_repo
    apk add frp
    while true; do
        frpc -c /configs/frpc.toml || true
        sleep 5
    done &
fi

# shellcheck disable=SC2154
if [ "$hold" = 1 ]; then
    if is_run_from_locald; then
        info "hold"
        exit
    fi
fi

# 正式运行重装
# shellcheck disable=SC2046,SC2194
case 1 in
1)
    # ChatGPT 说这种性能最高
    exec > >(exec tee $(get_ttys /dev/) /reinstall.log) 2>&1
    trans
    ;;
2)
    exec > >(tee $(get_ttys /dev/) /reinstall.log) 2>&1
    trans
    ;;
3)
    trans 2>&1 | tee $(get_ttys /dev/) /reinstall.log
    ;;
esac

if [ "$hold" = 2 ]; then
    info "hold 2"
    exit
fi

# swapoff -a
# umount ?
sync
reboot

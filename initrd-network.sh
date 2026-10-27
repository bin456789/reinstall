#!/bin/ash
# shellcheck shell=dash
# shellcheck disable=SC2034
# alpine/debian initrd 共用此脚本

# accept_ra 接收 RA + 自动配置网关
# autoconf  自动配置地址，依赖 accept_ra

mac_addr=$1
ipv4_addr=$2
ipv4_gateway=$3
ipv6_addr=$4
ipv6_gateway=$5
is_in_china=$6
ipv6_extra_addrs=$7

DHCP_TIMEOUT=15
DNS_FILE_TIMEOUT=5
TEST_TIMEOUT=10

# 检测是否有网络是通过检测这些 IP 的端口是否开放
# 因为 debian initrd 没有 nslookup
# 改成 generate_204？但检测网络时可能 resolv.conf 为空
# HTTP 80
# HTTPS/DOH 443
# DOT 853
if $is_in_china; then
    ipv4_dns1='223.5.5.5'
    ipv4_dns2='119.29.29.29' # 不开放 853
    ipv6_dns1='2400:3200::1'
    ipv6_dns2='2402:4e00::' # 不开放 853
else
    ipv4_dns1='1.1.1.1'
    ipv4_dns2='8.8.8.8' # 不开放 80
    ipv6_dns1='2606:4700:4700::1111'
    ipv6_dns2='2001:4860:4860::8888' # 不开放 80
fi

log() {
    log_with_uptime="[$(printf '%6s' "$(cut -d ' ' -f1 /proc/uptime)")] $*"
    echo "$log_with_uptime" >&2

    # 写入文件
    if [ -n "$ethx" ]; then
        mkdir -p "/dev/netconf/$ethx"
        echo "$log_with_uptime" >>"/dev/netconf/$ethx/logs"
    fi
}

# 找到主网卡
# debian 11 initrd 没有 xargs awk
# debian 12 initrd 没有 xargs
get_ethx() {
    # 过滤 azure vf (带 master ethx)
    # 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000\    link/ether 60:45:bd:21:8a:51 brd ff:ff:ff:ff:ff:ff
    # 3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP800> mtu 1500 qdisc mq master eth0 state UP qlen 1000\    link/ether 60:45:bd:21:8a:51 brd ff:ff:ff
    if false; then
        ip -o link | grep -i "$mac_addr" | grep -v master | awk '{print $2}' | cut -d: -f1 | grep .
    else
        ip -o link | grep -i "$mac_addr" | grep -v master | cut -d' ' -f2 | cut -d: -f1 | grep .
    fi
}

get_ipv4_gateway() {
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    ip -4 route show default dev "$ethx" | head -1 | cut -d ' ' -f3
}

get_ipv6_gateway() {
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    ip -6 route show default dev "$ethx" | head -1 | cut -d ' ' -f3
}

get_first_ipv4_addr() {
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    if false; then
        ip -4 -o addr show scope global dev "$ethx" | head -1 | awk '{print $4}'
    else
        ip -4 -o addr show scope global dev "$ethx" | head -1 | grep -o '[0-9\.]*/[0-9]*'
    fi
}

get_first_ipv4_gateway() {
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    if false; then
        ip -4 route show default dev "$ethx" | head -1 | awk '{print $3}'
    else
        ip -4 route show default dev "$ethx" | head -1 | cut -d' ' -f3
    fi
}

remove_netmask() {
    cut -d/ -f1
}

get_first_ipv6_addr() {
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    if false; then
        ip -6 -o addr show scope global dev "$ethx" | head -1 | awk '{print $4}'
    else
        ip -6 -o addr show scope global dev "$ethx" | head -1 | grep -o '[0-9a-f\:]*/[0-9]*'
    fi
}

get_first_ipv6_gateway() {
    # debian 11 initrd 没有 xargs awk
    # debian 12 initrd 没有 xargs
    if false; then
        ip -6 route show default dev "$ethx" | head -1 | awk '{print $3}'
    else
        ip -6 route show default dev "$ethx" | head -1 | cut -d' ' -f3
    fi
}

is_have_ipv4_addr() {
    ip -4 addr show scope global dev "$ethx" | grep -q inet
}

is_have_ipv6_addr() {
    ip -6 addr show scope global dev "$ethx" | grep -q inet6
}

is_have_ipv4_gateway() {
    ip -4 route show default dev "$ethx" | grep -q .
}

is_have_ipv6_gateway() {
    ip -6 route show default dev "$ethx" | grep -q .
}

is_have_ipv4() {
    is_have_ipv4_addr && is_have_ipv4_gateway
}

is_have_ipv6() {
    is_have_ipv6_addr && is_have_ipv6_gateway
}

is_have_ipv4_dns() {
    [ -f /etc/resolv.conf ] && grep -q '^nameserver .*\.' /etc/resolv.conf
}

is_have_ipv6_dns() {
    [ -f /etc/resolv.conf ] && grep -q '^nameserver .*:' /etc/resolv.conf
}

add_missing_ipv4_config() {
    if [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ]; then
        if ! is_have_ipv4_addr; then
            ip -4 addr add "$ipv4_addr" dev "$ethx"
        fi

        if ! is_have_ipv4_gateway; then
            # 如果 dhcp 无法设置onlink网关，那么在这里设置
            # debian 9 ipv6 不能识别 onlink，但 ipv4 能识别 onlink
            if true; then
                ip -4 route add "$ipv4_gateway" dev "$ethx"
                ip -4 route add default via "$ipv4_gateway" dev "$ethx"
            else
                ip -4 route add default via "$ipv4_gateway" dev "$ethx" onlink
            fi
        fi
    fi
}

add_missing_ipv6_config() {
    if [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ]; then
        if ! is_have_ipv6_addr; then
            ip -6 addr add "$ipv6_addr" dev "$ethx"
        fi

        if ! is_have_ipv6_gateway; then
            # 如果 dhcp 无法设置onlink网关，那么在这里设置
            # debian 9 ipv6 不能识别 onlink
            if true; then
                ip -6 route add "$ipv6_gateway" dev "$ethx"
                ip -6 route add default via "$ipv6_gateway" dev "$ethx"
            else
                ip -6 route add default via "$ipv6_gateway" dev "$ethx" onlink
            fi
        fi

        # 添加额外的 IPv6 地址（逗号分隔）
        # 在腾讯云上，dhcpv6 获取的 IPv6 不是旧系统的 IPv6，且不可用
        # 脚本添加旧系统的 IPv6 地址和额外的 IPv6 地址后，额外的 IPv6 地址在 ip -6 addr 第一位
        # get_first_ipv6_addr 获得的是额外的 IPv6 地址，也就是不可用的 IPv6 地址
        # 导致 ipv6 test_internet 失败
        # 因此暂时关闭 ipv6_extra_addrs
        if false && [ -n "$ipv6_extra_addrs" ]; then
            printf '%s\n' "$ipv6_extra_addrs" | tr ',' '\n' | while IFS= read -r addr; do
                if [ -n "$addr" ]; then
                    ip -6 addr add "$addr" dev "$ethx" 2>/dev/null || true
                fi
            done
        fi
    fi
}

is_need_test_ipv4() {
    mode=$1

    if [ "$mode" = ip ]; then
        is_have_ipv4 && ! $ipv4_has_internet
    else
        is_have_ipv4 && ! $ipv4_has_internet_with_dns
    fi
}

is_need_test_ipv6() {
    mode=$1

    if [ "$mode" = ip ]; then
        is_have_ipv6 && ! $ipv6_has_internet
    else
        is_have_ipv6 && { ! $ipv6_has_internet || ! $ipv6_has_internet_with_dns; }
    fi
}

# 测试方法：
# ping   有的机器禁止
# nc     测试 dot doh 端口是否开启
# wget   测试下载

# initrd 里面的软件版本，是否支持指定源IP/网卡
# 软件     nc  wget  nslookup
# debian9  ×    √   没有此软件
# alpine   √    ×      ×

test_by_wget() {
    src=$1
    dst=$2

    if echo "$dst" | grep -Eiq '^https?://'; then
        url="$dst"
    else
        # 输入的是 ip，检测 443 (doh)
        if echo "$dst" | grep -Fq ':'; then
            # ipv6 需要添加 []
            url="https://[$dst]"
        elif echo "$dst" | grep -Fq '.'; then
            # ipv4
            url="https://$dst"
        else
            # ip 没有 : 或者 .
            return 1
        fi
    fi

    # tcp 通了就算成功，不管 http 是不是 404
    # grep -m1 快速返回
    wget -T "$TEST_TIMEOUT" \
        --bind-address="$src" \
        --no-check-certificate \
        --max-redirect 0 \
        --tries 1 \
        -O /dev/null \
        "$url" 2>&1 | grep -iq -m1 connected
}

test_by_nc() {
    src=$1
    dst=$2

    if echo "$dst" | grep -Eiq '^https?://'; then
        # 取出 domain 或者 domain:port
        domain_colon_port=$(echo "$dst" | cut -d/ -f3)
        if echo "$domain_colon_port" | grep -Eq ':[0-9]+'; then
            host=$(echo "$domain_colon_port" | cut -d: -f1)
            port=$(echo "$domain_colon_port" | cut -d: -f2)
        else
            host=$domain_colon_port
            if echo "$dst" | grep -iq '^http://'; then
                port=80
            elif echo "$dst" | grep -iq '^https://'; then
                port=443
            fi
        fi

        # nc 的顺序是先解析 dns，再用指定 ip 连接
        # 因此即使指定了 ipv4 源 IP，也有时会尝试连接 ipv6 地址，导致连接失败
        # localhost:~# nc -z -v -s 10.0.0.208 www.qualcomm.cn 443
        # nc: www.qualcomm.cn ([2606:4700:440d::6812:2bdb]:443): Address family not supported by protocol
        # 因此先手动解析

        if echo "$src" | grep -Fq ':'; then
            type=AAAA
        else
            type=A
        fi

        if res=$(nslookup -type="$type" "$host" | grep -Ex 'Address: .+' | awk "{print \$2, \"$host\"}" | grep .); then
            echo "$res" >/tmp/hosts
        else
            return 1
        fi
    else
        # 输入的是 ip，检测 443 (doh)
        host=$dst
        port=443
    fi

    # tcp 通了就算成功
    set -- nc -z -v -w "$TEST_TIMEOUT" -s "$src" "$host" "$port"
    if [ -f /tmp/hosts ]; then
        if unshare -m sh -c "
            touch /etc/hosts &&
            mount --bind /tmp/hosts /etc/hosts &&
            $*
            "; then
            ret=0
        else
            ret=1
        fi
        rm -f /tmp/hosts
        return $ret
    else
        "$@"
    fi
}

is_debian_kali() {
    [ -f /etc/lsb-release ] && grep -Eiq 'Debian|Kali' /etc/lsb-release
}

test_internet_inner() {
    if is_debian_kali; then
        test_by_wget "$1" "$2"
    else
        test_by_nc "$1" "$2"
    fi
}

test_internet() {
    mode=$1

    # 两种检测模式
    # ip   = 检测 ip 是否有互联网连接
    # full = 检测 dns 是否正常 + 检测 ip

    if [ "$mode" = "ip" ]; then
        ipv4_dst1=$ipv4_dns1
        ipv4_dst2=$ipv4_dns2
        ipv6_dst1=$ipv6_dns1
        ipv6_dst2=$ipv6_dns2
    else
        # 这些都是用 cf cdn 且开通了国内 cdn 节点
        ipv4_dst1=https://www.qualcomm.cn/
        ipv4_dst2=https://www.autodesk.com.cn/
        ipv6_dst1=https://www.qualcomm.cn/
        ipv6_dst2=https://www.autodesk.com.cn/
    fi

    for i in $(seq 5); do
        log "Testing internet. Mode: $mode. Test $i... "
        if is_need_test_ipv4 "$mode" &&
            current_ipv4_addr="$(get_first_ipv4_addr | remove_netmask)" &&
            { test_internet_inner "$current_ipv4_addr" "$ipv4_dst1" ||
                test_internet_inner "$current_ipv4_addr" "$ipv4_dst2"; } >/dev/null 2>&1; then
            ipv4_has_internet=true
            if [ "$mode" = "full" ]; then
                ipv4_has_internet_with_dns=true
            fi
            log "IPv4 has internet. Mode: $mode"
        fi
        if is_need_test_ipv6 "$mode" &&
            current_ipv6_addr="$(get_first_ipv6_addr | remove_netmask)" &&
            { test_internet_inner "$current_ipv6_addr" "$ipv6_dst1" ||
                test_internet_inner "$current_ipv6_addr" "$ipv6_dst2"; } >/dev/null 2>&1; then
            ipv6_has_internet=true
            if [ "$mode" = "full" ]; then
                ipv6_has_internet_with_dns=true
            fi
            log "IPv6 has internet. Mode: $mode"
        fi
        if ! is_need_test_ipv4 "$mode" && ! is_need_test_ipv6 "$mode"; then
            break
        fi
        sleep 1
    done
}

flush_ipv4_dns() {
    sed -i "/\./d" /etc/resolv.conf
}

flush_ipv6_dns() {
    sed -i "/:/d" /etc/resolv.conf
}

should_add_ipv4_static_dns=false
should_add_ipv6_static_dns=false

add_ipv4_static_dns() {
    echo "nameserver $ipv4_dns1" >>/etc/resolv.conf
    echo "nameserver $ipv4_dns2" >>/etc/resolv.conf
}

add_ipv6_static_dns() {
    echo "nameserver $ipv6_dns1" >>/etc/resolv.conf
    echo "nameserver $ipv6_dns2" >>/etc/resolv.conf
}

flush_ipv4_config() {
    ip -4 addr flush scope global dev "$ethx"
    ip -4 route flush dev "$ethx"
    # DHCP 获取的 IP 不是重装前的 IP 时，一并删除 DHCP 获取的 DNS，以防 DNS 无效
    flush_ipv4_dns
}

should_disable_dhcpv4=false
should_disable_accept_ra=false
should_disable_autoconf=false

flush_ipv6_config() {
    if $should_disable_accept_ra; then
        echo 0 >"/proc/sys/net/ipv6/conf/$ethx/accept_ra"
    fi
    if $should_disable_autoconf; then
        echo 0 >"/proc/sys/net/ipv6/conf/$ethx/autoconf"
    fi
    ip -6 addr flush scope global dev "$ethx"
    ip -6 route flush dev "$ethx"
    # DHCP 获取的 IP 不是重装前的 IP 时，一并删除 DHCP 获取的 DNS，以防 DNS 无效
    flush_ipv6_dns
}

for i in $(seq 20); do
    if ethx=$(get_ethx); then
        break
    fi
    sleep 1
done

if [ -z "$ethx" ]; then
    log "Not found network card: $mac_addr"
    exit
fi

log "Configuring $ethx ($mac_addr)..."

# 不开启 lo 则 frp 无法连接 127.0.0.1 22
ip link set dev lo up

# 开启 ethx
ip link set dev "$ethx" up
sleep 1

# 开启 dhcpv4/v6
# debian / kali
if [ -f /usr/share/debconf/confmodule ]; then
    # shellcheck source=/dev/null
    . /usr/share/debconf/confmodule

    db_progress STEP 1

    # dhcpv4
    # 无需等待写入 dns，在 dhcpv6 等待
    db_progress INFO netcfg/dhcp_progress
    udhcpc -i "$ethx" -f -q -n || true
    db_progress STEP 1

    # slaac + dhcpv6
    db_progress INFO netcfg/slaac_wait_title
    # https://salsa.debian.org/installer-team/netcfg/-/blob/master/autoconfig.c#L148
    cat <<EOF >/var/lib/netcfg/dhcp6c.conf
interface $ethx {
    send ia-na 0;
    request domain-name-servers;
    request domain-name;
    script "/lib/netcfg/print-dhcp6c-info";
};

id-assoc na 0 {
};
EOF
    dhcp6c -c /var/lib/netcfg/dhcp6c.conf "$ethx" || true
    sleep $DHCP_TIMEOUT # 等待获取 ip 和写入 dns
    # kill-all-dhcp
    kill -9 "$(cat /var/run/dhcp6c.pid)" || true
    db_progress STEP 1

    # 静态 + 检测网络提示
    db_subst netcfg/link_detect_progress interface "$ethx"
    db_progress INFO netcfg/link_detect_progress
else
    # alpine
    # h3c 移动云电脑使用 udhcpc 会重复提示 sending select，因此添加 timeout 强制结束进程
    # dhcpcd 会配置租约时间，过期会移除 IP，但我们的没有在后台运行 dhcpcd ，因此用 udhcpc
    method=udhcpc

    case "$method" in
    udhcpc)
        timeout $DHCP_TIMEOUT udhcpc -i "$ethx" -f -q -n || true
        timeout $DHCP_TIMEOUT udhcpc6 -i "$ethx" -f -q -n || true
        sleep $DNS_FILE_TIMEOUT # 好像不用等待写入 dns，但是以防万一
        ;;
    dhcpcd)
        # https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/main/dhcpcd/dhcpcd.pre-install
        grep -q dhcpcd /etc/group || addgroup -S dhcpcd
        grep -q dhcpcd /etc/passwd || adduser -S -D -H \
            -h /var/lib/dhcpcd \
            -s /sbin/nologin \
            -G dhcpcd \
            -g dhcpcd \
            dhcpcd

        # --noipv4ll 禁止生成 169.254.x.x
        if false; then
            # 等待 DHCP 全过程
            timeout $DHCP_TIMEOUT \
                dhcpcd --persistent --noipv4ll --nobackground "$ethx"
        else
            # 等待 DNS
            dhcpcd --persistent --noipv4ll "$ethx" # 获取到 IP 后立即切换到后台
            sleep $DNS_FILE_TIMEOUT                # 需要等待写入 dns
            dhcpcd -x "$ethx"                      # 终止
        fi
        # autoconf 和 accept_ra 会被 dhcpcd 自动关闭，因此需要重新打开
        # 如果没重新打开，重新运行 dhcpcd 命令依然可以正常生成 slaac 地址和路由
        sysctl -w "net.ipv6.conf.$ethx.autoconf=1"
        sysctl -w "net.ipv6.conf.$ethx.accept_ra=1"
        ;;
    esac
fi

# 等待slaac
# 有ipv6地址就跳过，不管是slaac或者dhcpv6
# 因为会在trans里判断
# 这里等待5秒就够了，因为之前尝试获取dhcp6也用了一段时间
log "Waiting SLAAC..."
for i in $(seq 5 -1 0); do
    is_have_ipv6 && break
    sleep 1
done

# 记录是否有动态地址
# 由于还没设置静态ip，所以有条目表示有动态地址
is_have_ipv4_addr && dhcpv4=true || dhcpv4=false
is_have_ipv6_addr && dhcpv6_or_slaac=true || dhcpv6_or_slaac=false
is_have_ipv6_gateway && ra_has_gateway=true || ra_has_gateway=false

# 如果自动获取的 IP 不是重装前的，则改成静态，使用之前的 IP
# 只比较 IP，不比较掩码/网关，因为
# 1. 假设掩码/网关导致无法上网，后面也会检测到并改成静态
# 2. openSUSE wicked dhcpv6 是 64 位掩码，aws lightsail 模板上的也是，而其它 dhcpv6 软件都是 128 位掩码
if $dhcpv4 && [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ] &&
    ! [ "$(echo "$ipv4_addr" | cut -d/ -f1)" = "$(get_first_ipv4_addr | cut -d/ -f1)" ]; then
    log "IPv4 address obtained from DHCP is different from old system."
    should_disable_dhcpv4=true
    flush_ipv4_config
fi
if $dhcpv6_or_slaac && [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ] &&
    ! [ "$(echo "$ipv6_addr" | cut -d/ -f1)" = "$(get_first_ipv6_addr | cut -d/ -f1)" ]; then
    log "IPv6 address obtained from SLAAC/DHCPv6 is different from old system."
    should_disable_accept_ra=true
    should_disable_autoconf=true
    flush_ipv6_config
fi

# 设置静态地址，或者设置 debian 9 udhcpc 无法设置的网关
add_missing_ipv4_config
add_missing_ipv6_config

# 检查 ipv4/ipv6 是否连接联网
ipv4_has_internet=false
ipv6_has_internet=false
ipv4_has_internet_with_dns=false
ipv6_has_internet_with_dns=false
test_internet ip

# 如果无法上网，并且自动获取的 掩码/网关 不是重装前的，则改成静态
# ip_addr 包括 IP/掩码，所以可以用来判断掩码是否不同
# IP 不同的情况在前面已经改成静态了
if ! $ipv4_has_internet &&
    $dhcpv4 && [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ] &&
    ! { [ "$ipv4_addr" = "$(get_first_ipv4_addr)" ] && [ "$ipv4_gateway" = "$(get_first_ipv4_gateway)" ]; }; then
    log "IPv4 netmask/gateway obtained from DHCP is different from old system."
    should_disable_dhcpv4=true
    flush_ipv4_config
    add_missing_ipv4_config
    test_internet ip
fi
# 有可能是静态 IPv6 但能从 RA 获取到网关，因此加上 || $ra_has_gateway
if ! $ipv6_has_internet &&
    { $dhcpv6_or_slaac || $ra_has_gateway; } &&
    [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ] &&
    ! { [ "$ipv6_addr" = "$(get_first_ipv6_addr)" ] && [ "$ipv6_gateway" = "$(get_first_ipv6_gateway)" ]; }; then
    log "IPv6 netmask/gateway obtained from SLAAC/DHCPv6 is different from old system."
    should_disable_accept_ra=true
    should_disable_autoconf=true
    flush_ipv6_config
    add_missing_ipv6_config
    test_internet ip
fi

# 要删除不联网协议的ip，因为
# 1 甲骨文云管理面板添加ipv6地址然后取消
#   依然会分配ipv6地址，但ipv6没网络
#   此时alpine只会用ipv6下载apk，而不用会ipv4下载
# 2 有ipv4地址但没有ipv4网关的情况(vultr $2.5 ipv6 only)，aria2会用ipv4下载

# 假设 ipv4 ipv6 在不同网卡，ipv4 能上网但 ipv6 不能上网，这时也要删除 ipv6
# 不能用 ipv4_has_internet && ! ipv6_has_internet 判断，因为它判断的是同一个网卡
if ! $ipv4_has_internet; then
    if $dhcpv4; then
        should_disable_dhcpv4=true
    fi
    flush_ipv4_config
fi
if ! $ipv6_has_internet; then
    # 防止删除 IPv6 后再次通过 SLAAC 获得
    # 不用判断 || $ra_has_gateway ，因为没有 IPv6 地址但有 IPv6 网关时，不会出现下载问题
    if $dhcpv6_or_slaac; then
        should_disable_accept_ra=true
        should_disable_autoconf=true
    fi
    flush_ipv6_config
fi

# 模拟无法获取 DNS
# : >/etc/resolv.conf

# 模拟自动获取的 DNS 不能用
# echo 'nameserver 11.11.11.11' >/etc/resolv.conf

# 如果联网了，但没获取到默认 DNS，则添加我们的 DNS

# 有一种情况是，多网卡，且能上网的网卡先完成了这个脚本，不能上网的网卡后完成
# 无法上网的网卡通过 flush_ipv4_config 删除了不能上网的 IP 和 dns
# （理论上应该是删除无法上网的网卡 dhcp4 获取的 dns，但实际上无法区分）
if $ipv4_has_internet && ! is_have_ipv4_dns; then
    should_add_ipv4_static_dns=true
    log "IPv4 has internet. But no IPv4 DNS. Adding static DNS"
    add_ipv4_static_dns
fi
if $ipv6_has_internet && ! is_have_ipv6_dns; then
    should_add_ipv6_static_dns=true
    log "IPv6 has internet. But no IPv6 DNS. Adding static DNS"
    add_ipv6_static_dns
fi

# 测试完整的互联网连接，包括 DNS
test_internet full

# 需要覆盖自动 DNS 的情况
if $ipv4_has_internet && ! $ipv4_has_internet_with_dns && $dhcpv4; then
    should_add_ipv4_static_dns=true
    log "IPv4 has internet. But DNS failed. Overriding with static DNS"
    flush_ipv4_dns
    add_ipv4_static_dns

    # 再次测试完整的互联网连接
    test_internet full
fi
if $ipv6_has_internet && ! $ipv6_has_internet_with_dns && $dhcpv6_or_slaac; then
    should_add_ipv6_static_dns=true
    log "IPv6 has internet. But DNS failed. Overriding with static DNS"
    flush_ipv6_dns
    add_ipv6_static_dns

    # 再次测试完整的互联网连接
    test_internet full
fi

# TODO: 测试这个阶段的 slaac/dhcpv6 能不能自动获取 dns?

# 传参给 trans.start
mkdir -p "/dev/netconf/$ethx"

for conf in \
    is_in_china \
    dhcpv4 \
    dhcpv6_or_slaac \
    should_disable_dhcpv4 \
    should_disable_accept_ra \
    should_disable_autoconf \
    should_add_ipv4_static_dns \
    should_add_ipv6_static_dns \
    ipv4_has_internet \
    ipv6_has_internet; do
    { eval \$$conf && echo 1 || echo 0; } >"/dev/netconf/$ethx/$conf"
done

for conf in \
    ethx \
    mac_addr \
    ipv4_addr \
    ipv4_gateway \
    ipv6_addr \
    ipv6_gateway \
    ipv6_extra_addrs; do
    eval echo \"\$$conf\" >"/dev/netconf/$ethx/$conf"
done

# 模拟下载失败
# : >/etc/resolv.conf

# (cd /dev/netconf && grep -r . . >&2)

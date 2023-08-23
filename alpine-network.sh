#!/bin/ash
# shellcheck shell=dash

mac_addr=$1
ipv4_addr=$2
ipv4_gateway=$3
ipv6_addr=$4
ipv6_gateway=$5
is_in_china=$6

if $is_in_china; then
    ipv4_dns1='119.29.29.29'
    ipv4_dns2='223.5.5.5'
    ipv6_dns1='2402:4e00::'
    ipv6_dns2='2400:3200::1'
else
    ipv4_dns1='1.1.1.1'
    ipv4_dns2='8.8.8.8'
    ipv6_dns1='2606:4700:4700::1111'
    ipv6_dns2='2001:4860:4860::8888'
fi

get_ipv4_entry() {
    ip -4 addr show scope global dev eth0 | grep inet
}

get_ipv6_entry() {
    ip -6 addr show scope global dev eth0 | grep inet6
}

is_have_ipv4() {
    [ -n "$(get_ipv4_entry)" ]
}

is_have_ipv6() {
    [ -n "$(get_ipv6_entry)" ]
}

# 开启 eth0
ip link set dev eth0 up

# 检测是否有 dhcpv4
# 由于还没设置静态ip，所以有条目表示有 dhcpv4
get_ipv4_entry && dhcpv4=true || dhcpv4=false

# 检测是否有 dhcpv6
# dhcpv4 肯定是 /128
get_ipv6_entry | grep /128 && dhcpv6=true || dhcpv6=false

# 检测是否有 slaac
slaac=false
for i in $(seq 10 -1 0); do
    echo "waiting slaac for ${i}s"
    get_ipv6_entry | grep -v /128 && slaac=true && break
    sleep 1
done

# 设置静态地址
if ! is_have_ipv4 && [ -n "$ipv4_addr" ]; then
    ip -4 addr add $ipv4_addr dev eth0
    ip -4 route add default via $ipv4_gateway
fi
if ! is_have_ipv6 && [ -n "$ipv6_addr" ]; then
    ip -6 addr add $ipv6_addr dev eth0
    ip -6 route add default via $ipv6_gateway
fi

# 检查 ipv4/ipv6 是否连接联网
ipv4_has_internet=false
ipv6_has_internet=false
for i in $(seq 10); do
    is_have_ipv4 && ipv4_test_complete=false || ipv4_test_complete=true
    is_have_ipv6 && ipv6_test_complete=false || ipv6_test_complete=true

    if ! $ipv4_test_complete && nslookup www.qq.com $ipv4_dns1; then
        ipv4_has_internet=true
        ipv4_test_complete=true
    fi
    if ! $ipv6_test_complete && nslookup www.qq.com $ipv6_dns1; then
        ipv6_has_internet=true
        ipv6_test_complete=true
    fi

    if $ipv4_test_complete && $ipv6_test_complete; then
        break
    fi
    sleep 1
done

# 等待 udhcpc 创建 /etc/resolv.conf
# 好像只有 dhcpv4 会创建 resolv.conf
if { $dhcpv4 || $dhcpv6 || $slaac; } && [ ! -e /etc/resolv.conf ]; then
    echo "waiting for /etc/resolv.conf"
    sleep 5
fi

# 如果ipv4/ipv6不联网，则删除该协议的dns
if $ipv4_has_internet && ! $ipv6_has_internet; then
    sed -i '/^[[:blank:]]*nameserver[[:blank:]].*:/d' /etc/resolv.conf
elif ! $ipv4_has_internet && $ipv6_has_internet; then
    sed -i '/^[[:blank:]]*nameserver[[:blank:]].*\./d' /etc/resolv.conf
fi

# 如果联网了，但没获取到默认 DNS，则添加我们的 DNS
if $ipv4_has_internet && ! grep '\.' /etc/resolv.conf; then
    echo "nameserver $ipv4_dns1" >>/etc/resolv.conf
    echo "nameserver $ipv4_dns2" >>/etc/resolv.conf
fi
if $ipv6_has_internet && ! grep ':' /etc/resolv.conf; then
    echo "nameserver $ipv6_dns1" >>/etc/resolv.conf
    echo "nameserver $ipv6_dns2" >>/etc/resolv.conf
fi

# 传参给 trans.start
$dhcpv4 && echo 1 >/dev/dhcpv4 || echo 0 >/dev/dhcpv4
echo $ipv4_addr >/dev/ipv4_addr
echo $ipv4_gateway >/dev/ipv4_gateway
echo $ipv6_addr >/dev/ipv6_addr
echo $ipv6_gateway >/dev/ipv6_gateway

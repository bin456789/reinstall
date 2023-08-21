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

# 检测是否有 dhcpv4
has_ipv4=false
dhcpv4=false
ip -4 addr show scope global | grep inet && dhcpv4=true && has_ipv4=true

# 检测是否有 slaac
has_ipv6=false
slaac=false
for i in $(seq 10 -1 0); do
    echo waiting slaac for ${i}s
    ip -6 addr show scope global | grep inet6 && slaac=true && has_ipv6=true && break
    sleep 1
done

# 设置静态地址
# udhcpc不支持dhcpv6，所以如果网络是 dhcpv6，也先设置成静态
ip link set dev eth0 up
if ! $has_ipv4 && [ -n "$ipv4_addr" ]; then
    ip -4 addr add $ipv4_addr dev eth0
    ip -4 route add default via $ipv4_gateway
    has_ipv4=true
fi
if ! $has_ipv6 && [ -n "$ipv6_addr" ]; then
    ip -6 addr add $ipv6_addr dev eth0
    ip -6 route add default via $ipv6_gateway
    has_ipv6=true
fi

# 检查 ipv4/ipv6 是否连接联网
ipv4_has_internet=false
ipv6_has_internet=false
for i in $(seq 10); do
    $has_ipv4 && ipv4_test_complete=false || ipv4_test_complete=true
    $has_ipv6 && ipv6_test_complete=false || ipv6_test_complete=true

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
if { $dhcpv4 || $slaac; } && [ ! -e /etc/resolv.conf ]; then
    sleep 3
fi

# 如果ipv4/ipv6不联网，则删除该协议的dns
if $ipv4_has_internet && ! $ipv6_has_internet; then
    sed -i '/:/d' /etc/resolv.conf
elif ! $ipv4_has_internet && $ipv6_has_internet; then
    sed -i '/\./d' /etc/resolv.conf
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

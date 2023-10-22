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

is_have_ipv4() {
    ip -4 addr show scope global dev eth0 | grep -q inet
}

is_have_ipv6() {
    ip -6 addr show scope global dev eth0 | grep -q inet6
}

# 开启 eth0
ip link set dev eth0 up

# 等待slaac
# 有ipv6地址就跳过，不管是slaac或者dhcpv6
# 因为会在trans里判断
for i in $(seq 10 -1 0); do
    is_have_ipv6 && break
    echo "waiting slaac for ${i}s"
    sleep 1
done

# 记录是否有动态地址
# 由于还没设置静态ip，所以有条目表示有动态地址
is_have_ipv4 && dhcpv4=true || dhcpv4=false
is_have_ipv6 && dhcpv6_or_slaac=true || dhcpv6_or_slaac=false

# 设置静态地址
if ! is_have_ipv4 && [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ]; then
    ip -4 addr add "$ipv4_addr" dev eth0
    ip -4 route add default via "$ipv4_gateway"
fi
if ! is_have_ipv6 && [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ]; then
    ip -6 addr add "$ipv6_addr" dev eth0
    ip -6 route add default via "$ipv6_gateway"
fi

# 检查 ipv4/ipv6 是否连接联网
ipv4_has_internet=false
ipv6_has_internet=false

is_need_test_ipv4() {
    is_have_ipv4 && ! $ipv4_has_internet
}

is_need_test_ipv6() {
    is_have_ipv6 && ! $ipv6_has_internet
}

echo 'Testing Internet Connection...'

for i in $(seq 5); do
    {
        if is_need_test_ipv4 && nslookup www.qq.com $ipv4_dns1; then
            ipv4_has_internet=true
        fi
        if is_need_test_ipv6 && nslookup www.qq.com $ipv6_dns1; then
            ipv6_has_internet=true
        fi
        if ! is_need_test_ipv4 && ! is_need_test_ipv6; then
            break
        fi
        sleep 1
    } >/dev/null 2>&1
done

# 等待 udhcpc 创建 /etc/resolv.conf
# 好像只有 dhcpv4 会创建 resolv.conf
if { $dhcpv4 || $dhcpv6_or_slaac; } && [ ! -e /etc/resolv.conf ]; then
    echo "Waiting for /etc/resolv.conf..."
    sleep 5
fi

# 要删除不联网协议的ip，因为
# 1 甲骨文云管理面板添加ipv6地址然后取消
#   依然会分配ipv6地址，但ipv6没网络
#   此时alpine只会用ipv6下载apk，而不用会ipv4下载
# 2 有ipv4地址但没有ipv4网关的情况(vultr)，aria2会用ipv4下载
if $ipv4_has_internet && ! $ipv6_has_internet; then
    echo 0 >/proc/sys/net/ipv6/conf/eth0/accept_ra
    ip -6 addr flush scope global dev eth0
elif ! $ipv4_has_internet && $ipv6_has_internet; then
    ip -4 addr flush scope global dev eth0
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
$is_in_china && echo 1 >/dev/is_in_china || echo 0 >/dev/is_in_china
echo "$mac_addr" >/dev/mac_addr
echo "$ipv4_addr" >/dev/ipv4_addr
echo "$ipv4_gateway" >/dev/ipv4_gateway
echo "$ipv6_addr" >/dev/ipv6_addr
echo "$ipv6_gateway" >/dev/ipv6_gateway

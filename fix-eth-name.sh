#!/usr/bin/env bash
# shellcheck shell=dash
# shellcheck disable=SC3001,SC3010
# alpine 使用 busybox ash

set -eE

# openeuler 需等待 udev 将网卡名从 eth0 改为 enp3s0
sleep 10

# 本脚本在首次进入新系统后运行
# 将 trans 阶段生成的网络配置中的网卡名(eth0) 改为正确的网卡名，也适用于以下情况
# 1. alpine 要运行此脚本，因为安装后的内核可能有 netboot 没有的驱动
# 2. dmit debian 普通内核(安装时)和云内核网卡名不一致
#    https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=928923

# todo: 删除 cloud-init

to_lower() {
    tr '[:upper:]' '[:lower:]'
}

retry() {
    local max_try=$1
    shift

    for i in $(seq "$max_try"); do
        if "$@"; then
            return
        else
            ret=$?
            if [ "$i" -ge "$max_try" ]; then
                return $ret
            fi
            sleep 1
        fi
    done
}

# openeuler 本脚本运行一秒后才有 enp3s0
# 用 systemd-analyze plot >a.svg 发现 sys-subsystem-net-devices-enp3s0.device 也是出现在 NetworkManager 之后
# 因此需要等待网卡出现
get_ethx_by_mac() {
    mac=$(echo "$1" | to_lower)
    retry 10 _get_ethx_by_mac "$mac"
}

_get_ethx_by_mac() {
    if true; then
        # 过滤 azure vf (带 master ethx)
        ip -o link | grep -i "$mac" | grep -v master | awk '{print $2}' | cut -d: -f1 | grep .
        return
    else
        for i in $(cd /sys/class/net && echo *); do
            if [ "$(cat "/sys/class/net/$i/address")" = "$mac" ]; then
                echo "$i"
                return
            fi
        done
        return 1
    fi
}

fix_rh_sysconfig() {
    for file in /etc/sysconfig/network-scripts/ifcfg-eth*; do
        # 没有 ifcfg-eth* 也会执行一次，因此要判断文件是否存在
        [ -f "$file" ] || continue
        mac=$(grep ^HWADDR= "$file" | cut -d= -f2 | grep .) || continue
        ethx=$(get_ethx_by_mac "$mac") || continue

        proper_file=/etc/sysconfig/network-scripts/ifcfg-$ethx
        if [ "$file" != "$proper_file" ]; then
            # 更改文件内容
            sed -i "s/^DEVICE=.*/DEVICE=$ethx/" "$file"

            # 不要直接更改文件名，因为可能覆盖已有文件
            mv "$file" "$proper_file.tmp"
        fi
    done

    # 更改文件名
    for tmp_file in /etc/sysconfig/network-scripts/ifcfg-e*.tmp; do
        if [ -f "$tmp_file" ]; then
            mv "$tmp_file" "${tmp_file%.tmp}"
        fi
    done
}

fix_suse_sysconfig() {
    for file in /etc/sysconfig/network/ifcfg-eth*; do
        [ -f "$file" ] || continue

        # 可能两边有引号
        mac=$(grep ^LLADDR= "$file" | cut -d= -f2 | sed "s/'//g" | grep .) || continue
        ethx=$(get_ethx_by_mac "$mac") || continue

        old_ethx=${file##*-}
        if ! [ "$old_ethx" = "$ethx" ]; then
            # 不要直接更改文件名，因为可能覆盖已有文件
            for type in ifcfg ifroute; do
                old_file=/etc/sysconfig/network/$type-$old_ethx
                new_file=/etc/sysconfig/network/$type-$ethx.tmp
                # 防止没有 ifroute-eth* 导致中断脚本
                if [ -f "$old_file" ]; then
                    mv "$old_file" "$new_file"
                fi
            done
        fi
    done

    # 上面的循环结束后，再将 tmp 改成正式文件
    for tmp_file in \
        /etc/sysconfig/network/ifcfg-e*.tmp \
        /etc/sysconfig/network/ifroute-e*.tmp; do
        if [ -f "$tmp_file" ]; then
            mv "$tmp_file" "${tmp_file%.tmp}"
        fi
    done
}

fix_network_manager() {
    for file in /etc/NetworkManager/system-connections/cloud-init-eth*.nmconnection; do
        [ -f "$file" ] || continue
        mac=$(grep ^mac-address= "$file" | cut -d= -f2 | grep .) || continue
        ethx=$(get_ethx_by_mac "$mac") || continue

        proper_file=/etc/NetworkManager/system-connections/$ethx.nmconnection

        # 更改文件内容
        sed -i "s/^id=.*/id=$ethx/" "$file"

        # 更改文件名
        mv "$file" "$proper_file"
    done
}

# auto lo
# iface lo inet loopback

# # mac 11:22:33:44:55:66    # 用此行匹配网卡
# auto eth0
# iface eth0 inet static
#     address 1.1.1.1/25
#     gateway 1.1.1.1
#     dns-nameservers 1.1.1.1
#     dns-nameservers 8.8.8.8
# iface eth0 inet6 static
#     address 2602:1:0:80::100/64
#     gateway 2602:1:0:80::1
#     dns-nameserver 2606:4700:4700::1111
#     dns-nameserver 2001:4860:4860::8888

fix_ifupdown() {
    file=/etc/network/interfaces
    tmp_file=$file.tmp

    rm -f "$tmp_file"

    if [ -f "$file" ]; then
        while IFS= read -r line; do
            del_this_line=false
            if [[ "$line" = "# mac "* ]]; then
                ethx=
                if mac=$(echo "$line" | awk '{print $NF}'); then
                    ethx=$(get_ethx_by_mac "$mac") || true
                fi
                del_this_line=true
            elif [[ "$line" = "iface e"* ]] ||
                [[ "$line" = "auto e"* ]] ||
                [[ "$line" = "allow-hotplug e"* ]]; then
                if [ -n "$ethx" ]; then
                    line=$(echo "$line" | awk "{\$2=\"$ethx\"; print \$0}")
                fi
            fi
            if ! $del_this_line; then
                echo "$line" >>"$tmp_file"
            fi
        done <"$file"

        mv "$tmp_file" "$file"
    fi
}

fix_netplan() {
    file=/etc/netplan/50-cloud-init.yaml
    tmp_file=$file.tmp

    rm -f "$tmp_file"

    if [ -f "$file" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -Eq '^[[:space:]]+macaddress:'; then
                # 得到正确的网卡名
                mac=$(echo "$line" | awk '{print $NF}' | sed 's/"//g')
                ethx=$(get_ethx_by_mac "$mac") || true
            elif echo "$line" | grep -Eq '^[[:space:]]+eth[0-9]+:'; then
                # 改成正确的网卡名
                if [ -n "$ethx" ]; then
                    line=$(echo "$line" | sed -E "s/[^[:space:]]+/$ethx:/")
                fi
            fi
            echo "$line" >>"$tmp_file"

            # 删除 set-name 不过这一步在 trans 已完成
            # 因为 netplan-generator 会在 systemd generator 阶段就根据 netplan 配置重命名网卡
            # systemd generator 阶段比本脚本和 systemd-networkd 更早运行

            # 倒序
        done < <(grep -Ev "^[[:space:]]+set-name:" "$file" | tac)

        # 再倒序回来
        tac "$tmp_file" >"$file"
        rm -f "$tmp_file"

        # 通过 systemd netplan generator 生成 /run/systemd/network/10-netplan-enp3s0.network
        systemctl daemon-reload
    fi
}

fix_systemd_networkd() {
    for file in /etc/systemd/network/10-cloud-init-eth*.network; do
        [ -f "$file" ] || continue
        mac=$(grep ^MACAddress= "$file" | cut -d= -f2 | grep .) || continue
        ethx=$(get_ethx_by_mac "$mac") || continue

        proper_file=/etc/systemd/network/10-$ethx.network

        # 更改文件内容
        sed -Ei "s/^Name=eth[0-9]+/Name=$ethx/" "$file"

        # 更改文件名
        mv "$file" "$proper_file"
    done
}

fix_rh_sysconfig
fix_suse_sysconfig
fix_network_manager
fix_ifupdown
fix_netplan
fix_systemd_networkd

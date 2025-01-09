#!/bin/bash
# 修复 cloud-init 没有正确渲染 onlink 网关

set -eE
os_dir=$1

# 该脚本也会在 alpine live 下调用
# 防止在 alpine live 下运行 systemctl netplan 报错
systemctl() {
    if systemd-detect-virt --chroot; then
        return
    fi
    command systemctl "$@"
}

netplan() {
    if systemd-detect-virt --chroot; then
        return
    fi
    command netplan "$@"
}

insert_into_file() {
    file=$1
    location=$2
    regex_to_find=$3

    if [ "$location" = head ]; then
        bak=$(mktemp)
        cp "$file" "$bak"
        cat - "$bak" >"$file"
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

fix_netplan_conf() {
    # 修改前
    # gateway4: 1.1.1.1
    # gateway6: ::1

    # 修改后
    # routes:
    #   - to: 0.0.0.0/0
    #     via: 1.1.1.1
    #     on-link: true
    # routes:
    #   - to: ::/0
    #     via: ::1
    #     on-link: true
    conf=$os_dir/etc/netplan/50-cloud-init.yaml
    if ! [ -f "$conf" ]; then
        return
    fi

    # 判断 bug 是否已经修复
    if grep -q 'on-link:' "$conf"; then
        return
    fi

    # 获取网关
    gateways=$(grep 'gateway[4|6]:' "$conf" | awk '{print $2}')
    if [ -z "$gateways" ]; then
        return
    fi

    # 获取缩进
    spaces=$(grep 'gateway[4|6]:' "$conf" | head -1 | grep -o '^[[:space:]]*')

    {
        # 网关头部
        cat <<EOF
${spaces}routes:
EOF
        # 网关条目
        for gateway in $gateways; do
            # debian 11 的 netplan 不支持 to: default
            case $gateway in
            *.*) to='0.0.0.0/0' ;;
            *:*) to='::/0' ;;
            esac

            cat <<EOF
${spaces}  - to: $to
${spaces}    via: $gateway
${spaces}    on-link: true
EOF
        done
    } | insert_into_file "$conf" before 'match:'

    # 删除原来的条目
    sed -i '/gateway[4|6]:/d' "$conf"

    # 重新应用配置
    if command -v netplan && {
        systemctl -q is-enabled systemd-networkd || systemctl -q is-enabled NetworkManager
    }; then
        netplan apply
    fi
}

fix_networkd_conf() {
    # 修改前 gentoo
    # [Route]
    # Gateway=1.1.1.1
    # Gateway=2602::1

    # 修改前 arch
    # [Route]
    # Gateway=1.1.1.1
    #
    # [Route]
    # Gateway=2602::1

    # 修改后
    # [Route]
    # Gateway=1.1.1.1
    # GatewayOnLink=yes
    #
    # [Route]
    # Gateway=2602::1
    # GatewayOnLink=yes

    if ! confs=$(ls "$os_dir"/etc/systemd/network/10-cloud-init-*.network 2>/dev/null); then
        return
    fi

    for conf in $confs; do
        # 判断 bug 是否已经修复
        if grep -q '^GatewayOnLink=' "$conf"; then
            return
        fi

        # 获取网关
        gateways=$(grep '^Gateway=' "$conf" | cut -d= -f2)
        if [ -z "$gateways" ]; then
            return
        fi

        # 删除原来的条目
        sed -i '/^\[Route\]/d; /^Gateway=/d; /^GatewayOnLink=/d' "$conf"

        # 创建新条目
        for gateway in $gateways; do
            echo "
[Route]
Gateway=$gateway
GatewayOnLink=yes
"
        done >>"$conf"
    done

    # 重新应用配置
    # networkctl reload 不起作用
    if systemctl -q is-enabled systemd-networkd; then
        systemctl restart systemd-networkd
    fi
}

fix_wicked_conf() {
    # https://github.com/openSUSE/wicked/wiki/FAQ#q-why-wicked-does-not-set-my-default-static-route

    # 修改前
    # default 1.1.1.1 - -
    # default 2602::1 - -

    # 修改后
    # 1.1.1.1 - -
    # 2602::1 - -
    # default 1.1.1.1 - -
    # default 2602::1 - -

    if ! confs=$(ls "$os_dir/etc/sysconfig/network/ifroute-"* 2>/dev/null); then
        return
    fi

    for conf in $confs; do
        # 判断 bug 是否已经修复
        if grep -v 'default' "$conf" | grep -q '-'; then
            return
        fi

        # 获取网关
        gateways=$(awk '$1=="default" {print $2}' "$conf")
        if [ -z "$gateways" ]; then
            return
        fi

        # 创建新条目
        for gateway in $gateways; do
            echo "$gateway - -"
        done | insert_into_file "$conf" head
    done

    # 重新应用配置
    if systemctl -q is-enabled wicked; then
        systemctl restart wicked
    fi
}

# ubuntu 18.04 cloud-init 版本 23.1.2，因此不用处理

# debian 10/11 云镜像原本用 ifupdown + resolvconf，脚本改成用 netplan + networkd/resolved
# debian 12 云镜像: netplan + networkd/resolved
# 23.1.1 修复
fix_netplan_conf

# arch: networkd/resolved
# gentoo: networkd/resolved
# 24.2 修复
# 只需对云镜像处理
# 因为普通安装用的是 alpine 的 cloud-init，版本够新，不用处理
fix_networkd_conf

# opensuse 15.5: ifcfg + netconfig (dns) + wicked
fix_wicked_conf

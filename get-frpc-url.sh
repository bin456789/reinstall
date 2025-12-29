#!/bin/ash
# shellcheck shell=dash
# trans.sh/debian.cfg 共用此脚本

# debian 9 不支持 set -E
set -e

is_in_china() {
    grep -q 1 /dev/netconf/*/is_in_china
}

is_ipv6_only() {
    ! grep -q 1 /dev/netconf/*/ipv4_has_internet
}

get_frpc_url() {
    # 传入 windows 或者 linux
    local os_type=$1
    local nt_ver=$2

    is_need_old_version() {
        [ "$nt_ver" = "6.0" ] || [ "$nt_ver" = "6.1" ]
    }

    version=$(
        if is_need_old_version; then
            echo 0.54.0
        else
            # debian 11 initrd 没有 xargs awk
            # debian 12 initrd 没有 xargs
            # github 不支持 ipv6
            if is_in_china || is_ipv6_only; then
                wget -O- https://mirrors.nju.edu.cn/github-release/fatedier/frp/LatestRelease/frp_sha256_checksums.txt |
                    grep -m1 frp_ | cut -d_ -f2
            else
                # https://api.github.com/repos/fatedier/frp/releases/latest 有请求次数限制

                # root@localhost:~# wget --spider -S https://github.com/fatedier/frp/releases/latest 2>&1 | grep Location:
                #   Location: https://github.com/fatedier/frp/releases/tag/v0.62.0
                # Location: https://github.com/fatedier/frp/releases/tag/v0.62.0 [following]  # 原版 wget 多了这行

                wget --spider -S https://github.com/fatedier/frp/releases/latest 2>&1 |
                    grep -m1 '^  Location:' | sed 's,.*/tag/v,,'
            fi
        fi
    )

    if [ -z "$version" ]; then
        echo 'cannot find version'
        return 1
    fi

    suffix=$(
        case "$os_type" in
        linux) echo tar.gz ;;
        windows) echo zip ;;
        esac
    )

    mirror=$(
        # nju 没有 win7 用的旧版
        # github 不支持 ipv6
        # daocloud 加速不支持 ipv6
        # jsdelivr 不支持 github releases 文件
        if is_ipv6_only; then
            if is_need_old_version; then
                echo 'NOT_SUPPORT'
                return 1
            else
                echo https://mirrors.nju.edu.cn/github-release/fatedier/frp
            fi
        else
            if is_in_china; then
                if is_need_old_version; then
                    echo https://files.m.daocloud.io/github.com/fatedier/frp/releases/download
                else
                    echo https://mirrors.nju.edu.cn/github-release/fatedier/frp
                fi
            else
                echo https://github.com/fatedier/frp/releases/download
            fi
        fi
    )

    arch=$(
        case "$(uname -m)" in
        x86_64) echo amd64 ;;
        aarch64) echo arm64 ;;
        esac
    )

    filename=frp_${version}_${os_type}_${arch}.$suffix

    echo "${mirror}/v${version}/${filename}"
}

get_frpc_url "$@"

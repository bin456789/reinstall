#!/bin/bash
# shellcheck disable=SC2086

set -eE
confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
github_proxy=raw.fgit.cf

this_script=$(realpath "$0")
trap 'trap_err $LINENO $?' ERR

trap_err() {
    line_no=$1
    ret_no=$2

    error "Line $line_no return $ret_no"
    sed -n "$line_no"p "$this_script"
}

usage_and_exit() {
    cat <<EOF
Usage: reinstall.sh centos   7|8|9
                    alma     8|9
                    rocky    8|9
                    fedora   38|39
                    debian   10|11|12
                    ubuntu   20.04|22.04
                    alpine   3.16|3.17|3.18|3.19
                    opensuse 15.4|15.5|tumbleweed
                    arch
                    gentoo
                    dd       --img=http://xxx
                    windows  --iso=http://xxx --image-name='windows xxx'
                    netboot.xyz

Homepage: https://github.com/bin456789/reinstall
EOF
    exit 1
}

info() {
    upper=$(to_upper <<<"$@")
    echo_color_text '\e[32m' "***** $upper *****"
}

warn() {
    echo_color_text '\e[33m' "Warn: $*"
}

error() {
    echo_color_text '\e[31m' "Error: $*"
}

echo_color_text() {
    color="$1"
    shift
    plain="\e[0m"
    echo -e "$color$*$plain"
}

error_and_exit() {
    error "$@"
    exit 1
}

curl() {
    # 添加 -f, --fail，不然 404 退出码也为0
    # 32位 cygwin 已停止更新，证书可能有问题，先添加 --insecure
    grep -o 'http[^ ]*' <<<"$@" >&2
    command curl --insecure --connect-timeout 5 --retry 2 --retry-delay 1 -f "$@"
}

is_in_china() {
    if [ -z $_is_in_china ]; then
        # https://geoip.fedoraproject.org/city # 不支持 ipv6
        # https://geoip.ubuntu.com/lookup # 不支持 ipv6
        curl -L http://www.cloudflare.com/cdn-cgi/trace |
            grep -qx 'loc=CN' && _is_in_china=true ||
            _is_in_china=false
    fi
    $_is_in_china
}

is_in_windows() {
    [ "$(uname -o)" = Cygwin ] || [ "$(uname -o)" = Msys ]
}

is_in_alpine() {
    [ -f /etc/alpine-release ]
}

is_use_cloud_image() {
    [ -n "$cloud_image" ] && [ "$cloud_image" = 1 ]
}

is_use_dd() {
    [ "$distro" = dd ]
}

is_os_in_btrfs() {
    mount | grep -w 'on / type btrfs'
}

is_os_in_subvol() {
    subvol=$(awk '($2=="/") { print $i }' /proc/mounts | grep -o 'subvol=[^ ]*' | cut -d= -f2)
    [ "$subvol" != / ]
}

get_os_part() {
    awk '($2=="/") { print $1 }' /proc/mounts
}

cp_to_btrfs_root() {
    mount_dir=/tmp/reinstall-btrfs-root
    if ! grep -q $mount_dir /proc/mounts; then
        mkdir -p $mount_dir
        mount "$(get_os_part)" $mount_dir -t btrfs -o subvol=/
    fi
    cp -rf "$@" /tmp/reinstall-btrfs-root
}

is_host_has_ipv4_and_ipv6() {
    host=$1

    install_pkg dig
    # dig会显示cname结果，cname结果以.结尾，grep -v '\.$' 用于去除 cname 结果
    res=$(dig +short $host A $host AAAA | grep -v '\.$')
    # 有.表示有ipv4地址，有:表示有ipv6地址
    grep -q \. <<<$res && grep -q : <<<$res
}

is_netboot_xyz() {
    [ "$distro" = netboot.xyz ]
}

is_alpine_live() {
    [ "$distro" = alpine ] && [ "$hold" = 1 ]
}

is_have_initrd() {
    ! is_netboot_xyz
}

get_host_by_url() {
    cut -d/ -f3 <<<$1
}

get_function_content() {
    declare -f "$1" | sed '1d;2d;$d'
}

insert_into_file() {
    file=$1
    location=$2
    regex_to_find=$3

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
}

test_url() {
    test_url_real false "$@"
}

test_url_grace() {
    test_url_real true "$@"
}

test_url_real() {
    grace=$1
    url=$2
    expect_type=$3
    var_to_eval=$4
    info test url

    failed() {
        $grace && return 1
        error_and_exit "$@"
    }

    tmp_file=/tmp/reinstall-img-test

    # 有的服务器不支持 range，curl会下载整个文件
    # 用 dd 限制下载 1M
    # 并过滤 curl 23 错误（dd限制了空间）
    # 也可用 ulimit -f 但好像 cygwin 不支持
    curl -Lr 0-1048575 "$url" \
        1> >(dd bs=1M count=1 of=$tmp_file iflag=fullblock 2>/dev/null) \
        2> >(grep -v 'curl: (23)' >&2) ||
        if [ ! $? -eq 23 ]; then
            failed "$url not accessible"
        fi

    if [ -n "$expect_type" ]; then
        # gzip的mime有很多种写法
        # centos7中显示为 x-gzip，在其他系统中显示为 gzip，可能还有其他
        # 所以不用mime判断
        # https://www.digipres.org/formats/sources/tika/formats/#application/gzip

        # 有些 file 版本输出的是 # ISO 9660 CD-ROM filesystem data ，要去掉开头的井号
        install_pkg file
        real_type=$(file -b $tmp_file | sed 's/^# //' | cut -d' ' -f1 | to_lower)
        [ -n "$var_to_eval" ] && eval $var_to_eval=$real_type

        if ! grep -wo "$real_type" <<<"$expect_type"; then
            failed "$url expected: $expect_type. actual: $real_type."
        fi
    fi
}

add_community_repo_for_alpine() {
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

assert_not_in_container() {
    _error_and_exit() {
        error_and_exit "Not Supported OS in Container.\nPlease use https://github.com/LloydAsp/OsMutation"
    }

    is_in_windows && return

    if is_have_cmd systemd-detect-virt; then
        if systemd-detect-virt -c >/dev/null; then
            _error_and_exit
        fi
    else
        if [ -d /proc/vz ] || grep container=lxc /proc/1/environ; then
            _error_and_exit
        fi
    fi
}

is_virt() {
    if [ -z "$_is_virt" ]; then
        if is_in_windows; then
            # https://github.com/systemd/systemd/blob/main/src/basic/virt.c
            # https://sources.debian.org/src/hw-detect/1.159/hw-detect.finish-install.d/08hw-detect/
            vmstr='VMware|Virtual|Virtualization|VirtualBox|VMW|Hyper-V|Bochs|QEMU|KVM|OpenStack|KubeVirt|innotek|Xen|Parallels|BHYVE'
            for name in ComputerSystem BIOS BaseBoard; do
                if wmic $name | grep -Eiwo $vmstr; then
                    _is_virt=true
                    break
                fi
            done
            if [ -z "$_is_virt" ]; then
                if wmic /namespace:'\\root\cimv2' PATH Win32_Fan 2>/dev/null | head -1 | grep -q Name; then
                    _is_virt=false
                fi
            fi
        else
            # aws t4g debian 11
            # systemd-detect-virt: 为 none，即使装了dmidecode
            # virt-what: 未装 deidecode时结果为空，装了deidecode后结果为aws
            # 所以综合两个命令的结果来判断
            if is_have_cmd systemd-detect-virt && systemd-detect-virt -v; then
                _is_virt=true
            fi
            if [ -z "$_is_virt" ]; then
                # debian 安装 virt-what 不会自动安装 dmidecode，因此结果有误
                install_pkg dmidecode virt-what
                # virt-what 返回值始终是0，所以用是否有输出作为判断
                if [ -n "$(virt-what)" ]; then
                    _is_virt=true
                fi
            fi
        fi

        if [ -z "$_is_virt" ]; then
            _is_virt=false
        fi
        echo "vm: $_is_virt"
    fi
    $_is_virt
}

setos() {
    local step=$1
    local distro=$2
    local releasever=$3
    info set $step $distro $releasever

    setos_netboot.xyz() {
        if is_efi; then
            if [ "$basearch" = aarch64 ]; then
                eval ${step}_efi=https://boot.netboot.xyz/ipxe/netboot.xyz-arm64.efi
            else
                eval ${step}_efi=https://boot.netboot.xyz/ipxe/netboot.xyz.efi
            fi
        else
            eval ${step}_vmlinuz=https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn
        fi
    }

    setos_alpine() {
        is_virt && flavour=virt || flavour=lts

        # alpine aarch64 3.16/3.17 lts 才有直连链接
        if [ "$basearch" = aarch64 ] &&
            { [ "$releasever" = 3.16 ] || [ "$releasever" = 3.17 ]; }; then
            flavour=lts
        fi

        # 不要用https 因为甲骨文云arm initramfs阶段不会从硬件同步时钟，导致访问https出错
        if is_in_china; then
            mirror=http://mirrors.tuna.tsinghua.edu.cn/alpine/v$releasever
        else
            mirror=http://dl-cdn.alpinelinux.org/alpine/v$releasever
        fi
        eval ${step}_vmlinuz=$mirror/releases/$basearch/netboot/vmlinuz-$flavour
        eval ${step}_initrd=$mirror/releases/$basearch/netboot/initramfs-$flavour
        eval ${step}_repo=$mirror/main
        eval ${step}_modloop=$mirror/releases/$basearch/netboot/modloop-$flavour
    }

    setos_debian() {
        case "$releasever" in
        10) codename=buster ;;
        11) codename=bullseye ;;
        12) codename=bookworm ;;
        esac

        if is_use_cloud_image; then
            # cloud image
            if is_in_china; then
                ci_mirror=https://mirror.nju.edu.cn/debian-cdimage
            else
                ci_mirror=https://cdimage.debian.org/images
            fi

            is_virt && ci_type=genericcloud || ci_type=generic
            # 甲骨文 debian 10 amd64 genericcloud vnc 没有显示
            [ "$releasever" -eq 10 ] && [ "$basearch_alt" = amd64 ] && ci_type=generic
            eval ${step}_img=$ci_mirror/cloud/$codename/latest/debian-$releasever-$ci_type-$basearch_alt.qcow2
        else
            # 传统安装
            if is_in_china; then
                # 部分国内机无法访问 ftp.cn.debian.org
                deb_hostname=mirrors.tuna.tsinghua.edu.cn
            else
                deb_hostname=deb.debian.org
            fi

            mirror=http://$deb_hostname/debian/dists/$codename/main/installer-$basearch_alt/current/images/netboot/debian-installer/$basearch_alt
            eval ${step}_vmlinuz=$mirror/linux
            eval ${step}_initrd=$mirror/initrd.gz
            eval ${step}_ks=$confhome/debian.cfg

            is_virt && flavour=-cloud || flavour=
            # 甲骨文 debian 10 amd64 cloud 内核 vnc 没有显示
            [ "$releasever" -eq 10 ] && [ "$basearch_alt" = amd64 ] && flavour=
            # shellcheck disable=SC2034
            kernel=linux-image$flavour-$basearch_alt

        fi
    }

    setos_ubuntu() {
        case "$releasever" in
        20.04) codename=focal ;;
        22.04) codename=jammy ;;
        esac

        if is_use_cloud_image; then
            # cloud image
            if is_in_china; then
                ci_mirror=https://mirror.nju.edu.cn/ubuntu-cloud-images
            else
                ci_mirror=https://cloud-images.ubuntu.com
            fi

            eval ${step}_img=$ci_mirror/releases/$releasever/release/ubuntu-$releasever-server-cloudimg-$basearch_alt.img

            # minimal 镜像内核风味是 kvm，后台 vnc 无显示
            # 没有 aarch64 minimal 镜像
            # TODO: 在 trans 里安装普通内核/云内核
            use_minimal_image=false
            if $use_minimal_image && [ "$basearch" = x86_64 ]; then
                eval ${step}_img=$ci_mirror/minimal/releases/$codename/release/ubuntu-$releasever-minimal-cloudimg-$basearch_alt.img
            fi
        else
            # 传统安装
            if is_in_china; then
                case "$basearch" in
                "x86_64") mirror=https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/$releasever ;;
                "aarch64") mirror=https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/releases/$releasever/release ;;
                esac
            else
                case "$basearch" in
                "x86_64") mirror=https://releases.ubuntu.com/$releasever ;;
                "aarch64") mirror=https://cdimage.ubuntu.com/releases/$releasever/release ;;
                esac
            fi

            # iso
            filename=$(curl -L $mirror | grep -oP "ubuntu-$releasever.*?-live-server-$basearch_alt.iso" | head -1)
            iso=$mirror/$filename
            # 在 ubuntu 20.04 上，file 命令检测 ubuntu 22.04 iso 结果是 DOS/MBR boot sector
            test_url $iso 'iso|dos/mbr'
            eval ${step}_iso=$iso

            # ks
            eval ${step}_ks=$confhome/ubuntu.yaml
        fi
    }

    setos_arch() {
        cloud_image=1

        # cloud image
        if is_in_china; then
            ci_mirror=https://mirrors.tuna.tsinghua.edu.cn/archlinux
        else
            ci_mirror=https://geo.mirror.pkgbuild.com
        fi
        # eval ${step}_img=$ci_mirror/images/latest/Arch-Linux-x86_64-basic.qcow2
        eval ${step}_img=$ci_mirror/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
    }

    setos_gentoo() {
        cloud_image=1
        if is_in_china; then
            ci_mirror=https://mirrors.tuna.tsinghua.edu.cn/gentoo
        else
            ci_mirror=https://distfiles.gentoo.org
        fi

        if [ "$basearch_alt" = arm64 ]; then
            error_and_exit 'Not support arm64 for gentoo cloud image.'
        fi

        # openrc 镜像没有附带兼容 cloud-init 的网络管理器
        eval ${step}_img=$ci_mirror/experimental/$basearch_alt/openstack/gentoo-openstack-$basearch_alt-systemd-latest.qcow2
    }

    setos_opensuse() {
        cloud_image=1

        # aria2 有 mata4 问题
        # https://download.opensuse.org/

        # 很多国内源缺少 aarch64 tumbleweed appliances
        #                 https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/
        #           https://mirrors.nju.edu.cn/opensuse/ports/aarch64/tumbleweed/appliances/
        #          https://mirrors.ustc.edu.cn/opensuse/ports/aarch64/tumbleweed/appliances/
        # https://mirrors.tuna.tsinghua.edu.cn/opensuse/ports/aarch64/tumbleweed/appliances/

        if is_in_china; then
            mirror=https://mirror.sjtu.edu.cn/opensuse
        else
            mirror=https://mirror.fcix.net/opensuse
        fi

        if [ "$releasever" = tumbleweed ]; then
            # tumbleweed
            if [ "$basearch" = aarch64 ]; then
                dir=ports/aarch64/tumbleweed/appliances
            else
                dir=tumbleweed/appliances
            fi
            file=openSUSE-Tumbleweed-Minimal-VM.$basearch-Cloud.qcow2
        else
            # 常规版本
            dir=distribution/leap/$releasever/appliances
            file=openSUSE-Leap-$releasever-Minimal-VM.$basearch-Cloud.qcow2
        fi

        # 有专门的kvm镜像，openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2，但里面没有cloud-init
        eval ${step}_img=$mirror/$dir/$file
    }

    setos_windows() {
        test_url $iso 'iso|dos/mbr'
        eval "${step}_iso='$iso'"
        eval "${step}_image_name='$image_name'"
    }

    # shellcheck disable=SC2154
    setos_dd() {
        test_url $img 'xz|gzip' ${step}_img_type
        eval "${step}_img='$img'"
    }

    setos_redhat() {
        if is_use_cloud_image; then
            # ci
            if is_in_china; then
                case $distro in
                "centos") ci_mirror="https://mirror.nju.edu.cn/centos-cloud/centos" ;;
                "alma") ci_mirror="https://mirror.nju.edu.cn/almalinux/$releasever/cloud/$basearch/images" ;;
                "rocky") ci_mirror="https://mirror.nju.edu.cn/rocky/$releasever/images/$basearch" ;;
                "fedora") ci_mirror="https://mirror.nju.edu.cn/fedora/releases/$releasever/Cloud/$basearch/images" ;;
                esac
            else
                case $distro in
                "centos") ci_mirror="https://cloud.centos.org/centos" ;;
                "alma") ci_mirror="https://repo.almalinux.org/almalinux/$releasever/cloud/$basearch/images" ;;
                "rocky") ci_mirror="https://download.rockylinux.org/pub/rocky/$releasever/images/$basearch" ;;
                "fedora") ci_mirror="https://download.fedoraproject.org/pub/fedora/linux/releases/$releasever/Cloud/$basearch/images" ;;
                esac
            fi
            case $distro in
            "centos")
                case $releasever in
                "7") ci_image=$ci_mirror/$releasever/images/CentOS-7-$basearch-GenericCloud.qcow2 ;;
                "8" | "9") ci_image=$ci_mirror/$releasever-stream/$basearch/images/CentOS-Stream-GenericCloud-$releasever-latest.$basearch.qcow2 ;;
                esac
                ;;
            "alma")
                # alma8 x86_64 有独立的uefi镜像
                if [ "$releasever" = 8 ] && is_efi && [ "$basearch" = x86_64 ]; then
                    alma_efi=-UEFI
                fi
                ci_image=$ci_mirror/AlmaLinux-$releasever-GenericCloud$alma_efi-latest.$basearch.qcow2
                ;;
            "rocky") ci_image=$ci_mirror/Rocky-$releasever-GenericCloud-Base.latest.$basearch.qcow2 ;;
            "fedora")
                filename=$(curl -L $ci_mirror | grep -oP "Fedora-Cloud-Base-$releasever.*?$basearch" | head -1)
                # ci_image=$ci_mirror/$filename.raw.xz
                ci_image=$ci_mirror/$filename.qcow2
                ;;
            esac

            eval ${step}_img=${ci_image}
        else
            # 传统安装
            case $distro in
            "centos")
                case $releasever in
                "7") mirrorlist="http://mirrorlist.centos.org/?release=7&arch=$basearch&repo=os" ;;
                "8") mirrorlist="http://mirrorlist.centos.org/?release=8-stream&arch=$basearch&repo=BaseOS" ;;
                "9") mirrorlist="https://mirrors.centos.org/mirrorlist?repo=centos-baseos-9-stream&arch=$basearch" ;;
                esac
                ;;
            "alma") mirrorlist="https://mirrors.almalinux.org/mirrorlist/$releasever/baseos" ;;
            "rocky") mirrorlist="https://mirrors.rockylinux.org/mirrorlist?arch=$basearch&repo=BaseOS-$releasever" ;;
            "fedora") mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?arch=$basearch&repo=fedora-$releasever" ;;
            esac

            # rocky/centos9 需要删除第一行注释， alma 需要替换$basearch
            for cur_mirror in $(curl -L $mirrorlist | sed "/^#/d" | sed "s,\$basearch,$basearch,"); do
                host=$(get_host_by_url $cur_mirror)
                if is_host_has_ipv4_and_ipv6 $host &&
                    test_url_grace ${cur_mirror}images/pxeboot/vmlinuz; then
                    mirror=$cur_mirror
                    break
                fi
            done

            if [ -z "$mirror" ]; then
                error_and_exit "All mirror failed."
            fi

            eval "${step}_mirrorlist='${mirrorlist}'"

            eval ${step}_ks=$confhome/redhat.cfg
            eval ${step}_vmlinuz=${mirror}images/pxeboot/vmlinuz
            eval ${step}_initrd=${mirror}images/pxeboot/initrd.img

            if [ "$releasever" = 7 ]; then
                squashfs=${mirror}LiveOS/squashfs.img
            else
                squashfs=${mirror}images/install.img
            fi
            test_url $squashfs 'squashfs'
            eval ${step}_squashfs=$squashfs
        fi
    }

    eval ${step}_distro=$distro
    if is_distro_like_redhat $distro; then
        setos_redhat
    else
        setos_$distro
    fi

    # 集中测试云镜像格式
    if is_use_cloud_image && [ "$step" = finalos ]; then
        # shellcheck disable=SC2154
        test_url $finalos_img 'xz|gzip|qemu' finalos_img_type
    fi
}

is_distro_like_redhat() {
    [ "$1" = centos ] || [ "$1" = alma ] || [ "$1" = rocky ] || [ "$1" = fedora ]
}

# 检查是否为正确的系统名
verify_os_name() {
    if [ -z "$*" ]; then
        usage_and_exit
    fi

    for os in \
        'centos   7|8|9' \
        'alma     8|9' \
        'rocky    8|9' \
        'fedora   38|39' \
        'debian   10|11|12' \
        'ubuntu   20.04|22.04' \
        'alpine   3.16|3.17|3.18|3.19' \
        'opensuse 15.4|15.5|tumbleweed' \
        'arch' \
        'gentoo' \
        'windows' \
        'dd' \
        'netboot.xyz'; do
        ds=$(awk '{print $1}' <<<"$os")
        vers=$(awk '{print $2}' <<<"$os" | sed 's \. \\\. g')
        finalos=$(echo "$@" | to_lower | sed -n -E "s,^($ds)[ :-]?(|$vers)$,\1:\2,p")
        if [ -n "$finalos" ]; then
            distro=$(echo $finalos | cut -d: -f1)
            releasever=$(echo $finalos | cut -d: -f2)
            # 默认版本号
            if [ -z "$releasever" ] && grep -q '|' <<<$os; then
                releasever=$(awk '{print $2}' <<<$os | awk -F'|' '{print $NF}')
            fi
            return
        fi
    done

    error "Please specify a proper os"
    usage_and_exit
}

verify_os_args() {
    case "$distro" in
    dd) [ -n "$img" ] || error_and_exit "dd need --img" ;;
    windows)
        if [ -z "$iso" ] || [ -z "$image_name" ]; then
            error_and_exit "Install Windows need --iso and --image-name"
        fi
        # 防止常见错误
        # --image-name 肯定大于等于3个单词
        if [ "$(echo "$image_name" | wc -w)" -lt 3 ] ||
            [[ "$(to_lower <<<"$image_name")" != windows* ]]; then
            error_and_exit "--image-name wrong."
        fi
        ;;
    esac
}

get_cmd_path() {
    # arch 云镜像不带 which
    # command -v 包括脚本里面的方法
    # ash 无效
    type -f -p $1
}

is_have_cmd() {
    get_cmd_path $1 >/dev/null 2>&1
}

install_pkg() {
    is_in_windows && return

    find_pkg_mgr() {
        if [ -z "$pkg_mgr" ]; then
            for mgr in dnf yum apt pacman zypper emerge apk; do
                is_have_cmd $mgr && pkg_mgr=$mgr && return
            done
            return 1
        fi
    }

    cmd_to_pkg() {
        unset USE
        case $cmd in
        lsmem | lsblk | findmnt) pkg="util-linux" ;;
        unsquashfs)
            case "$pkg_mgr" in
            zypper) pkg="squashfs" ;;
            emerge) pkg="squashfs-tools" && export USE="lzma" ;;
            *) pkg="squashfs-tools" ;;
            esac
            ;;
        nslookup | dig)
            case "$pkg_mgr" in
            apt) pkg="dnsutils" ;;
            pacman) pkg="bind" ;;
            apk | emerge) pkg="bind-tools" ;;
            yum | dnf | zypper) pkg="bind-utils" ;;
            esac
            ;;
        *) pkg=$cmd ;;
        esac
    }

    install_pkg_real() {
        case $pkg_mgr in
        dnf) dnf install -y --setopt=install_weak_deps=False $pkg ;;
        yum) yum install -y $pkg ;;
        emerge) emerge --oneshot $pkg ;;
        pacman) pacman -Syu --noconfirm --needed $pkg ;;
        zypper) zypper install -y $pkg ;;
        apk)
            add_community_repo_for_alpine
            apk add $pkg
            ;;
        apt)
            [ -z "$apk_updated" ] && apt update && apk_updated=1
            DEBIAN_FRONTEND=noninteractive apt install -y $pkg
            ;;
        esac
    }

    for cmd in "$@"; do
        if ! is_have_cmd $cmd ||
            {
                # gentoo 默认编译的 unsquashfs 不支持 xz
                [ "$cmd" = unsquashfs ] &&
                    is_have_cmd emerge &&
                    ! unsquashfs |& grep -w xz &&
                    echo "unsquashfs not supported xz. need rebuild."
            }; then
            if ! find_pkg_mgr; then
                error_and_exit "Can't find compatible package manager. Please manually install $cmd."
            fi
            cmd_to_pkg
            install_pkg_real
        fi
    done
}

check_ram() {
    if is_in_windows; then
        ram_size=$(wmic memorychip get capacity | tail +2 | awk '{sum+=$1} END {print sum/1024/1024}')
    else
        # lsmem最准确但centos7 arm 和alpine不能用
        # arm 24g dmidecode 显示少了128m
        # arm 24g lshw 显示23BiB
        # ec2 t4g arm alpine 用 lsmem 和 dmidecode 都无效，要用 lshw，但结果和free -m一致，其他平台则没问题
        install_pkg lsmem
        ram_size=$(lsmem -b 2>/dev/null | grep 'Total online memory:' | awk '{ print $NF/1024/1024 }')

        if [ -z $ram_size ]; then
            install_pkg dmidecode
            ram_size=$(dmidecode -t 17 | grep "Size.*[GM]B" | awk '{if ($3=="GB") s+=$2*1024; else s+=$2} END {print s}')
        fi

        if [ -z $ram_size ]; then
            install_pkg lshw
            # 不能忽略 -i，alpine 显示的是 System memory
            ram_str=$(lshw -c memory -short | grep -i 'System Memory' | awk '{print $3}')
            ram_size=$(grep <<<$ram_str -o '[0-9]*')
            grep <<<$ram_str GiB && ram_size=$((ram_size * 1024))
        fi
    fi

    if [ -z $ram_size ] || [ $ram_size -le 0 ]; then
        error_and_exit "Could not detect RAM size."
    fi

    case "$distro" in
    alpine) ram_installer=256 ;; # 192 无法启动 netboot
    debian) ram_installer=384 ;;
    *) ram_installer=1024 ;;
    esac

    ram_cloud_image=512

    case "$distro" in
    opensuse | arch | gentoo) cloud_image=1 ;;
    esac

    # ram 足够就用普通方法安装，否则如果内存大于512就用 cloud image
    # TODO: 测试 256 384 内存
    if [ ! "$cloud_image" = 1 ] && [ $ram_size -lt $ram_installer ]; then
        if [ $ram_size -ge $ram_cloud_image ]; then
            info "RAM < $ram_installer MB. Switch to cloud image mode"
            cloud_image=1
        else
            error_and_exit "Could not install $distro: RAM < $ram_cloud_image MB."
        fi
    fi
}

is_efi() {
    if is_in_windows; then
        bcdedit | grep -q '^path.*\.efi'
    else
        [ -d /sys/firmware/efi ]
    fi
}

is_secure_boot_enabled() {
    if is_efi; then
        if is_in_windows; then
            reg query 'HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State' /v UEFISecureBootEnabled | grep 0x1 && return 0
        else
            # mokutil --sb-state
            dmesg | grep -i 'Secure boot enabled' && return 0
        fi
    fi
    return 1
}

is_use_grub() {
    ! { is_netboot_xyz && is_efi; }
}

# 只有 linux bios 是用本机的 grub
is_use_local_grub() {
    is_use_grub && ! is_in_windows && ! is_efi
}

to_upper() {
    tr '[:lower:]' '[:upper:]'
}

to_lower() {
    tr '[:upper:]' '[:lower:]'
}

del_cr() {
    sed 's/\r//g'
}

# TODO: 多网卡 单网卡多IP
collect_netconf() {
    if is_in_windows; then
        convert_net_str_to_array() {
            config=$1
            key=$2
            var=$3
            IFS=',' read -r -a "${var?}" <<<"$(grep "$key=" <<<"$config" | cut -d= -f2 | sed 's/[{}\"]//g')"
        }

        # 部分机器精简了 powershell
        # 所以不要用 powershell 获取网络信息
        # ids=$(wmic nic where "PhysicalAdapter=true and MACAddress is not null and (PNPDeviceID like '%VEN_%&DEV_%' or PNPDeviceID like '%{F8615163-DF3E-46C5-913F-F2D2F965ED0E}%')" get InterfaceIndex | del_cr | sed '1d')

        # 否        手动        0    0.0.0.0/0                  19  192.168.1.1
        # 否        手动        0    0.0.0.0/0                  59  nekoray-tun
        ids="
        $(netsh int ipv4 show route | grep --text -F '0.0.0.0/0' | awk '$6 ~ /\./ {print $5}')
        $(netsh int ipv6 show route | grep --text -F '::/0' | awk '$6 ~ /:/ {print $5}')
        "
        ids=$(echo "$ids" | sort -u)
        for id in $ids; do
            config=$(wmic nicconfig where "InterfaceIndex='$id'" get MACAddress,IPAddress,IPSubnet,DefaultIPGateway /format:list | del_cr)
            # 排除 IP/子网/网关/MAC 为空的
            if grep -q '=$' <<<"$config"; then
                continue
            fi

            mac_addr=$(grep "MACAddress=" <<<"$config" | cut -d= -f2 | to_lower)
            convert_net_str_to_array "$config" IPAddress ips
            convert_net_str_to_array "$config" IPSubnet subnets
            convert_net_str_to_array "$config" DefaultIPGateway gateways

            # IPv4
            # shellcheck disable=SC2154
            for ((i = 0; i < ${#ips[@]}; i++)); do
                ip=${ips[i]}
                subnet=${subnets[i]}
                if [[ "$ip" = *.* ]]; then
                    cidr=$(ipcalc -b "$ip/$subnet" | grep Netmask: | awk '{print $NF}')
                    ipv4_addr="$ip/$cidr"
                    break
                fi
            done

            # IPv6
            ipv6_type_list=$(cmd /c "chcp 437 & netsh interface ipv6 show address $id normal")
            for ((i = 0; i < ${#ips[@]}; i++)); do
                ip=${ips[i]}
                cidr=${subnets[i]}
                if [[ "$ip" = *:* ]]; then
                    ipv6_type=$(grep "$ip" <<<"$ipv6_type_list" | awk '{print $1}')
                    # Public 是 slaac
                    # 还有类型 Temporary，不过有 Temporary 肯定还有 Public，因此不用
                    if [ "$ipv6_type" = Public ] ||
                        [ "$ipv6_type" = Dhcp ] ||
                        [ "$ipv6_type" = Manual ]; then
                        ipv6_addr="$ip/$cidr"
                        break
                    fi
                fi
            done

            # 网关
            # shellcheck disable=SC2154
            for gateway in "${gateways[@]}"; do
                if [ -n "$ipv4_addr" ] && [[ "$gateway" = *.* ]]; then
                    ipv4_gateway="$gateway"
                elif [ -n "$ipv6_addr" ] && [[ "$gateway" = *:* ]]; then
                    ipv6_gateway="$gateway"
                fi
            done

            break
        done
    else
        # linux
        # 通过默认网关得到默认网卡
        for v in 4 6; do
            if ethx=$(ip -$v route show default | head -1 | awk '{print $5}' | grep .); then
                mac_addr=$(ip link show dev $ethx | grep link/ether | head -1 | awk '{print $2}')
                break
            fi
        done

        for v in 4 6; do
            if ip -$v route show default dev $ethx | head -1 | grep -q .; then
                eval ipv${v}_gateway="$(ip -$v route show default dev $ethx | head -1 | awk '{print $3}')"
                eval ipv${v}_addr="$(ip -$v -o addr show scope global dev $ethx | head -1 | awk '{print $4}')"
            fi
        done
    fi

    info "Network Info"
    echo "MAC  Address: $mac_addr"
    echo "IPv4 Address: $ipv4_addr"
    echo "IPv4 Gateway: $ipv4_gateway"
    echo "IPv6 Address: $ipv6_addr"
    echo "IPv6 Gateway: $ipv6_gateway"
}

add_efi_entry_in_windows() {
    source=$1

    # 挂载
    if result=$(find /cygdrive/?/EFI/Microsoft/Boot/bootmgfw.efi 2>/dev/null); then
        # 已经挂载
        x=$(echo $result | cut -d/ -f3)
    else
        # 找到空盘符并挂载
        for x in {a..z}; do
            [ ! -e /cygdrive/$x ] && break
        done
        mountvol $x: /s
    fi

    # 文件夹命名为reinstall而不是grub，因为可能机器已经安装了grub，bcdedit名字同理
    dist_dir=/cygdrive/$x/EFI/reinstall
    basename=$(basename $source)
    mkdir -p $dist_dir
    cp -f "$source" "$dist_dir/$basename"

    # 如果 {fwbootmgr} displayorder 为空
    # 执行 bcdedit /copy '{bootmgr}' 会报错
    # 例如 azure windows 2016 模板
    # 要先设置默认的 {fwbootmgr} displayorder
    # https://github.com/hakuna-m/wubiuefi/issues/286
    bcdedit /set '{fwbootmgr}' displayorder '{bootmgr}' /addfirst

    # 添加启动项
    id=$(bcdedit /copy '{bootmgr}' /d "$(get_entry_name)" | grep -o '{.*}')
    bcdedit /set $id device partition=$x:
    bcdedit /set $id path \\EFI\\reinstall\\$basename
    bcdedit /set '{fwbootmgr}' bootsequence $id
}

get_maybe_efi_dirs_in_linux() {
    # arch云镜像efi分区挂载在/efi，且使用 autofs，挂载后会有两个 /efi 条目
    mount | awk '$5=="vfat" || $5=="autofs" {print $3}' | grep -E '/boot|/efi' | sort | uniq
}

get_disk_by_part() {
    dev_part=$1
    install_pkg lsblk
    lsblk -rn --inverse "$dev_part" | grep -w disk | awk '{print $1}'
}

get_part_num_by_part() {
    dev_part=$1
    grep -o '[0-9]*' <<<"$dev_part" | tail -1
}

grep_efi_index() {
    awk -F '*' '{print $1}' | sed 's/Boot//'
}

add_efi_entry_in_linux() {
    source=$1

    install_pkg efibootmgr

    for efi_part in $(get_maybe_efi_dirs_in_linux); do
        if find $efi_part -name "*.efi" >/dev/null; then
            dist_dir=$efi_part/EFI/reinstall
            basename=$(basename $source)
            mkdir -p $dist_dir

            if [[ "$source" = http* ]]; then
                curl -Lo "$dist_dir/$basename" "$source"
            else
                cp -f "$source" "$dist_dir/$basename"
            fi

            if false; then
                grub_probe="$(command -v grub-probe grub2-probe)"
                dev_part="$("$grub_probe" -t device "$dist_dir")"
            else
                install_pkg findmnt
                # arch findmnt 会得到
                # systemd-1
                # /dev/sda2
                dev_part=$(findmnt -T "$dist_dir" -no SOURCE | grep '^/dev/')
            fi

            id=$(efibootmgr --create-only \
                --disk "/dev/$(get_disk_by_part $dev_part)" \
                --part "$(get_part_num_by_part $dev_part)" \
                --label "$(get_entry_name)" \
                --loader "\\EFI\\reinstall\\$basename" |
                tail -1 | grep_efi_index)
            efibootmgr --bootnext $id
            return
        fi
    done

    error_and_exit "Can't find efi partition."
}

install_grub_linux_efi() {
    info 'download grub efi'

    if [ "$basearch" = aarch64 ]; then
        grub_efi=grubaa64.efi
    else
        grub_efi=grubx64.efi
    fi

    # fedora x86_64 的 efi 无法识别 opensuse tumbleweed 的 btrfs
    # opensuse tumbleweed aarch64 的 efi 无法识别 alpine 3.19 的内核
    if [ "$basearch" = aarch64 ]; then
        efi_distro=fedora
    else
        efi_distro=opensuse
    fi

    if [ "$efi_distro" = fedora ]; then
        fedora_ver=39

        if is_in_china; then
            mirror=https://mirrors.tuna.tsinghua.edu.cn/fedora
        else
            mirror=https://download.fedoraproject.org/pub/fedora/linux
        fi

        curl -Lo /tmp/$grub_efi $mirror/releases/$fedora_ver/Everything/$basearch/os/EFI/BOOT/$grub_efi
    else
        if is_in_china; then
            mirror=https://mirror.sjtu.edu.cn/opensuse
        else
            mirror=https://download.opensuse.org
        fi

        file=tumbleweed/repo/oss/EFI/BOOT/grub.efi
        if [ "$basearch" = aarch64 ]; then
            file=ports/aarch64/$file
        fi
        curl -Lo /tmp/$grub_efi $mirror/$file
    fi

    add_efi_entry_in_linux /tmp/$grub_efi
}

install_grub_win() {
    # 下载 grub
    info download grub
    grub_ver=2.06
    is_in_china && grub_url=https://mirrors.tuna.tsinghua.edu.cn/gnu/grub/grub-$grub_ver-for-windows.zip ||
        grub_url=https://ftpmirror.gnu.org/gnu/grub/grub-$grub_ver-for-windows.zip
    curl -Lo /tmp/grub.zip $grub_url
    # unzip -qo /tmp/grub.zip
    7z x /tmp/grub.zip -o/tmp -r -y -xr!i386-efi -xr!locale -xr!themes -bso0
    grub_dir=/tmp/grub-$grub_ver-for-windows
    grub=$grub_dir/grub

    # 设置 grub 内嵌的模块
    # 原系统是 windows，因此不需要 ext2 lvm xfs btrfs
    grub_modules+=" normal minicmd serial ls echo test cat reboot halt linux linux16 chain search all_video configfile"
    grub_modules+=" scsi part_msdos part_gpt fat ntfs ntfscomp lzopio xzio gzio zstd"
    if ! is_efi; then
        grub_modules+=" biosdisk"
    fi

    # 设置 grub prefix 为c盘根目录
    # 运行 grub-probe 会改变cmd窗口字体
    prefix=$($grub-probe -t drive $c: | sed 's,.*PhysicalDrive,(hd,' | sed 's,\r,,')/
    echo $prefix

    # 安装 grub
    if is_efi; then
        # efi
        info install grub for efi
        $grub-mkimage -p $prefix -O x86_64-efi -o "$(cygpath -w $grub_dir/grubx64.efi)" $grub_modules
        add_efi_entry_in_windows $grub_dir/grubx64.efi
    else
        # bios
        info install grub for bios

        # bootmgr 加载 g2ldr 有64k限制
        # 解决方法1 g2ldr.mbr + g2ldr
        # 解决方法2 生成少于64K的 g2ldr + 动态模块

        # g2ldr.mbr
        is_in_china && host=ftp.cn.debian.org || host=deb.debian.org
        curl -LO http://$host/debian/tools/win32-loader/stable/win32-loader.exe
        7z x win32-loader.exe 'g2ldr.mbr' -o/tmp/win32-loader -r -y -bso0
        find /tmp/win32-loader -name 'g2ldr.mbr' -exec cp {} /cygdrive/$c/ \;

        # g2ldr
        $grub-mkimage -p "$prefix" -O i386-pc -o "$(cygpath -w $grub_dir/core.img)" $grub_modules
        cat $grub_dir/i386-pc/lnxboot.img $grub_dir/core.img >/cygdrive/$c/g2ldr

        # 添加引导
        # 脚本可能不是首次运行，所以先删除原来的
        id='{1c41f649-1637-52f1-aea8-f96bfebeecc8}'
        bcdedit /enum all | grep --text $id && bcdedit /delete $id
        bcdedit /create $id /d "$(get_entry_name)" /application bootsector
        bcdedit /set $id device partition=$c:
        bcdedit /set $id path \\g2ldr.mbr
        bcdedit /displayorder $id /addlast
        bcdedit /bootsequence $id /addfirst
    fi
}

# 转换 finalos_a=1 为 finalos.a=1 ，排除 finalos_mirrorlist
build_finalos_cmdline() {
    if vars=$(compgen -v finalos_); then
        for key in $vars; do
            value=${!key}
            key=${key#finalos_}
            if [ -n "$value" ] && [ $key != "mirrorlist" ]; then
                finalos_cmdline+=" finalos.$key='$value'"
            fi
        done
    fi
}

build_extra_cmdline() {
    for key in confhome hold cloud_image kernel deb_hostname; do
        value=${!key}
        if [ -n "$value" ]; then
            extra_cmdline+=" extra.$key='$value'"
        fi
    done

    # 指定最终安装系统的 mirrorlist，链接有&，在grub中是特殊字符，所以要加引号
    if [ -n "$finalos_mirrorlist" ]; then
        extra_cmdline+=" extra.mirrorlist='$finalos_mirrorlist'"
    elif [ -n "$nextos_mirrorlist" ]; then
        extra_cmdline+=" extra.mirrorlist='$nextos_mirrorlist'"
    fi
}

echo_tmp_ttys() {
    curl -L $confhome/ttys.sh | sh -s "console="
}

get_entry_name() {
    printf 'reinstall (%s%s%s)' "$distro" \
        "$([ -n "$releasever" ] && printf ' %s' "$releasever")" \
        "$([ "$distro" = alpine ] && [ "$hold" = 1 ] && printf ' Live OS')"
}

# shellcheck disable=SC2154
build_nextos_cmdline() {
    if [ $nextos_distro = alpine ]; then
        nextos_cmdline="alpine_repo=$nextos_repo modloop=$nextos_modloop"
    elif [ $nextos_distro = debian ]; then
        nextos_cmdline="lowmem/low=1 auto=true priority=critical url=$nextos_ks"
    else
        # redhat
        nextos_cmdline="root=live:$nextos_squashfs inst.ks=$nextos_ks"
    fi

    nextos_cmdline+=" $(echo_tmp_ttys)"
    # nextos_cmdline+=" mem=256M"
}

build_cmdline() {
    # nextos
    build_nextos_cmdline

    # finalos
    # trans 需要 finalos_distro 识别是安装 alpine 还是其他系统
    if [ "$distro" = alpine ]; then
        finalos_distro=alpine
    fi
    if [ -n "$finalos_distro" ]; then
        build_finalos_cmdline
    fi

    # extra
    build_extra_cmdline

    cmdline="$nextos_cmdline $finalos_cmdline $extra_cmdline"
}

# 脚本可能多次运行，先清理之前的残留
mkdir_clear() {
    dir=$1

    if [ -z "$dir" ] || [ "$dir" = / ]; then
        return
    fi

    # alpine 没有 -R
    # { umount $dir || umount -R $dir || true; } 2>/dev/null
    rm -rf $dir
    mkdir -p $dir
}

mod_alpine_initrd() {
    # 修改 alpine 启动时运行我们的脚本
    info mod alpine initrd
    install_pkg gzip cpio

    # 解压
    # 先删除临时文件，避免之前运行中断有残留文件
    tmp_dir=/tmp/reinstall
    mkdir_clear $tmp_dir
    cd $tmp_dir
    zcat /reinstall-initrd | cpio -idm

    # 预先下载脚本
    curl -Lo $tmp_dir/trans.start $confhome/trans.sh
    curl -Lo $tmp_dir/alpine-network.sh $confhome/alpine-network.sh

    # virt 内核添加 ipv6 模块
    if virt_dir=$(ls -d $tmp_dir/lib/modules/*-virt 2>/dev/null); then
        ipv6_dir=$virt_dir/kernel/net/ipv6
        mkdir -p $ipv6_dir
        modloop_file=/tmp/modloop_file
        modloop_dir=/tmp/modloop_dir
        curl -Lo $modloop_file $nextos_modloop
        if is_in_windows; then
            # cygwin 没有 unsquashfs
            7z e $modloop_file ipv6.ko -r -y -o$ipv6_dir
        else
            install_pkg unsquashfs
            mkdir_clear $modloop_dir
            unsquashfs -f -d $modloop_dir $modloop_file 'modules/*/kernel/net/ipv6/ipv6.ko'
            find $modloop_dir -name ipv6.ko -exec cp {} $ipv6_dir/ \;
        fi
    fi

    # hack 1 添加 ipv6 模块
    insert_into_file init after 'configure_ip\(\)' <<EOF
        depmod
        modprobe ipv6
EOF

    # hack 2 设置 ethx
    ip_choose_if() {
        ip -o link | grep "@mac_addr" | awk '{print $2}' | cut -d: -f1
        return
    }

    collect_netconf
    get_function_content ip_choose_if | sed "s/@mac_addr/$mac_addr/" | insert_into_file init after 'ip_choose_if\(\)'

    # hack 3
    # udhcpc 添加 -n 参数，请求dhcp失败后退出
    # 使用同样参数运行 udhcpc6
    # TODO: digitalocean -i eth1?
    # $MOCK udhcpc -i "$device" -f -q # v3.18
    #       udhcpc -i "$device" -f -q # v3.17
    search='udhcpc -i'
    orig_cmd="$(grep "$search" init)"
    mod_cmd4="$orig_cmd -n || true"
    mod_cmd6="${mod_cmd4//udhcpc/udhcpc6}"
    sed -i "/$search/c$mod_cmd4 \n $mod_cmd6" init

    # hack 4 /usr/share/udhcpc/default.script
    # 脚本被调用的顺序
    # udhcpc:  deconfig
    # udhcpc:  bound
    # udhcpc6: deconfig
    # udhcpc6: bound
    # shellcheck disable=SC2154
    udhcpc() {
        if [ "$1" = deconfig ]; then
            return
        fi
        if [ "$1" = bound ] && [ -n "$ipv6" ]; then
            ip -6 addr add "$ipv6" dev "$interface"
            ip link set dev "$interface" up
            return
        fi
    }

    get_function_content udhcpc |
        insert_into_file usr/share/udhcpc/default.script after 'deconfig\|renew\|bound'

    # 允许设置 ipv4 onlink 网关
    sed -Ei 's,(0\.0\.0\.0\/0),"\1 onlink",' usr/share/udhcpc/default.script

    # hack 5 网络配置
    is_in_china && is_in_china=true || is_in_china=false
    insert_into_file init after 'MAC_ADDRESS=' <<EOF
        source /alpine-network.sh \
        "$mac_addr" "$ipv4_addr" "$ipv4_gateway" "$ipv6_addr" "$ipv6_gateway" "$is_in_china"
EOF

    # hack 5 运行 trans.start
    # exec /bin/busybox switch_root $switch_root_opts $sysroot $chart_init "$KOPT_init" $KOPT_init_args # 3.17
    # exec              switch_root $switch_root_opts $sysroot $chart_init "$KOPT_init" $KOPT_init_args # 3.18
    # 1. alpine arm initramfs 时间问题 要添加 --no-check-certificate
    # 2. aws t4g arm 如果没设置console=ttyx，在initramfs里面wget https会出现bad header错误，chroot后正常
    # Connecting to raw.githubusercontent.com (185.199.108.133:443)
    # 60C0BB2FFAFF0000:error:0A00009C:SSL routines:ssl3_get_record:http request:ssl/record/ssl3_record.c:345:
    # ssl_client: SSL_connect
    # wget: bad header line: �
    insert_into_file init before '^exec (/bin/busybox )?switch_root' <<EOF
        # echo "wget --no-check-certificate -O- $confhome/trans.sh | /bin/ash" >\$sysroot/etc/local.d/trans.start
        # wget --no-check-certificate -O \$sysroot/etc/local.d/trans.start $confhome/trans.sh
        cp /trans.start \$sysroot/etc/local.d/trans.start
        chmod a+x \$sysroot/etc/local.d/trans.start
        ln -s /etc/init.d/local \$sysroot/etc/runlevels/default/
EOF

    # 重建
    # 注意要用 cpio -H newc 不要用 cpio -c ，不同版本的 -c 作用不一样，很坑
    # -c    Use the old portable (ASCII) archive format
    # -c    Identical to "-H newc", use the new (SVR4)
    #       portable format.If you wish the old portable
    #       (ASCII) archive format, use "-H odc" instead.
    find . | cpio --quiet -o -H newc | gzip -1 >/reinstall-initrd
    cd - >/dev/null
}

# 脚本入口
# 检查 root
if ! is_in_windows; then
    if [ "$EUID" -ne 0 ]; then
        info "Please run as root."
        exit 1
    fi
fi

# 整理参数
if ! opts=$(getopt -n $0 -o "" --long debug,hold:,sleep:,iso:,image-name:,img:,ci,cloud-image -- "$@"); then
    usage_and_exit
fi

eval set -- "$opts"
# shellcheck disable=SC2034
while true; do
    case "$1" in
    --debug)
        set -x
        shift
        ;;
    --ci | --cloud-image)
        cloud_image=1
        shift
        ;;
    --hold | --sleep)
        hold=$2
        shift 2
        ;;
    --img)
        img=$2
        shift 2
        ;;
    --iso)
        iso=$2
        shift 2
        ;;
    --image-name)
        image_name=$2
        shift 2
        ;;
    --)
        shift
        break
        ;;
    *)
        echo "Unexpected option: $1."
        usage_and_exit
        ;;
    esac
done

# 检查目标系统名
verify_os_name "$@"

# 检查必须的参数
verify_os_args

# 不支持容器虚拟化
assert_not_in_container

# 不支持安全启动
if is_secure_boot_enabled; then
    error_and_exit "Not Supported with secure boot enabled."
fi

# win系统盘
if is_in_windows; then
    c=$(echo $SYSTEMDRIVE | cut -c1)
fi

# 必备组件
install_pkg curl
# alpine 自带的 grep 是 busybox 里面的， 要下载完整版grep
if is_in_alpine; then
    apk add grep
fi

# 检查内存
if ! { [ "$distro" = dd ] || [ "$distro" = windows ] || [ "$distro" = netboot.xyz ]; }; then
    check_ram
fi

# alpine --ci 参数无效
if [ "$distro" = alpine ] && is_use_cloud_image; then
    error_and_exit "can't install alpine with cloud image"
fi

# 检查硬件架构
# x86强制使用x64
# archlinux 云镜像没有 arch 命令
basearch=$(uname -m)
[ $basearch = i686 ] && basearch=x86_64
case "$basearch" in
"x86_64") basearch_alt=amd64 ;;
"aarch64") basearch_alt=arm64 ;;
esac

# 设置国内代理
# gitee 不支持ipv6
# jsdelivr 有12小时缓存
# https://github.com/XIU2/UserScript/blob/master/GithubEnhanced-High-Speed-Download.user.js#L31
if [ -n "$github_proxy" ] && [[ "$confhome" = http*://raw.githubusercontent.com/* ]] && is_in_china; then
    # confhome=$github_proxy/$confhome
    confhome=${confhome/raw.githubusercontent.com/$github_proxy}
fi

# 以下目标系统不需要两步安装
# alpine
# debian
# el7 x86_64 >=1g
# el7 aarch64 >=1.5g
# el8/9/fedora 任何架构 >=2g
if is_netboot_xyz ||
    { ! is_use_cloud_image && {
        [ "$distro" = "alpine" ] || [ "$distro" = "debian" ] ||
            { is_distro_like_redhat "$distro" && [ $releasever -eq 7 ] && [ $ram_size -ge 1024 ] && [ $basearch = "x86_64" ]; } ||
            { is_distro_like_redhat "$distro" && [ $releasever -eq 7 ] && [ $ram_size -ge 1536 ] && [ $basearch = "aarch64" ]; } ||
            { is_distro_like_redhat "$distro" && [ $releasever -ge 8 ] && [ $ram_size -ge 2048 ]; }
    }; }; then
    setos nextos $distro $releasever
else
    # alpine 作为中间系统时，使用 3.19
    alpine_ver_for_trans=3.19
    setos finalos $distro $releasever
    setos nextos alpine $alpine_ver_for_trans
fi

# 删除之前的条目
# 防止第一次运行 netboot.xyz，第二次运行其他，但还是进入 netboot.xyz
# 防止第一次运行其他，第二次运行 netboot.xyz，但还有第一次的菜单
# bios 无论什么情况都用到 grub，所以不用处理
if is_efi; then
    if is_in_windows; then
        rm -f /cygdrive/$c/grub.cfg

        bcdedit /set '{fwbootmgr}' bootsequence '{bootmgr}'
        bcdedit /enum bootmgr | grep --text -B3 'reinstall' | awk '{print $2}' | grep '{.*}' |
            xargs -I {} cmd /c bcdedit /delete {}
    else
        # shellcheck disable=SC2046
        find $(get_maybe_efi_dirs_in_linux) /boot -type f -name 'custom.cfg' -exec rm -f {} \;

        install_pkg efibootmgr
        efibootmgr | grep -q 'BootNext:' && efibootmgr --quiet --delete-bootnext
        efibootmgr | grep 'reinstall' | grep_efi_index |
            xargs -I {} efibootmgr --quiet --bootnum {} --delete-bootnum
    fi
fi

# 有的机器开启了 kexec，例如腾讯云轻量 debian，要禁用
if ! is_in_windows && [ -f /etc/default/kexec ]; then
    sed -i 's/LOAD_KEXEC=true/LOAD_KEXEC=false/' /etc/default/kexec
fi

# 下载 netboot.xyz / 内核
# shellcheck disable=SC2154
if is_netboot_xyz; then
    if is_efi; then
        curl -Lo /netboot.xyz.efi $nextos_efi
        if is_in_windows; then
            add_efi_entry_in_windows /netboot.xyz.efi
        else
            add_efi_entry_in_linux /netboot.xyz.efi
        fi
    else
        curl -Lo /reinstall-vmlinuz $nextos_vmlinuz
    fi
else
    # 下载 nextos 内核
    info download vmlnuz and initrd
    curl -Lo /reinstall-vmlinuz $nextos_vmlinuz
    curl -Lo /reinstall-initrd $nextos_initrd
fi

# 修改 alpine initrd
if [ "$nextos_distro" = alpine ]; then
    mod_alpine_initrd
fi

# 将内核/netboot.xyz.lkrn 放到正确的位置
if is_use_grub; then
    if is_in_windows; then
        mv /reinstall-vmlinuz /cygdrive/$c/
        is_have_initrd && mv /reinstall-initrd /cygdrive/$c/
    else
        if is_os_in_btrfs && is_os_in_subvol; then
            cp_to_btrfs_root /reinstall-vmlinuz
            is_have_initrd && cp_to_btrfs_root /reinstall-initrd
        fi
    fi
fi

# grub
if is_use_grub; then
    # win 使用外部 grub
    if is_in_windows; then
        install_grub_win
    else
        # linux aarch64 efi 要用去除了内核 magic number 校验的 grub
        # 为了方便测试，linux x86 efi 也是用外部 grub
        if is_efi; then
            install_grub_linux_efi
        fi
    fi

    info 'create grub config'

    # 寻找 grub.cfg
    if is_in_windows; then
        grub_cfg=/cygdrive/$c/grub.cfg
    else
        # linux
        if is_efi; then
            # 现在 linux-efi 是使用 reinstall 目录下的 grub
            # shellcheck disable=SC2046
            efi_reinstall_dir=$(find $(get_maybe_efi_dirs_in_linux) -type d -name "reinstall" | head -1)
            grub_cfg=$efi_reinstall_dir/grub.cfg
        else
            if is_have_cmd update-grub; then
                # alpine debian ubuntu
                grub_cfg=$(grep -o '[^ ]*grub.cfg' "$(get_cmd_path update-grub)" | head -1)
            else
                # 找出主配置文件（含有menuentry|blscfg）
                # 现在 efi 用下载的 grub，因此不需要查找 efi 目录
                grub_cfg=$(
                    find /boot/grub* \
                        -type f -name grub.cfg \
                        -exec grep -E -l 'menuentry|blscfg' {} \;
                )

                if [ "$(wc -l <<<"$grub_cfg")" -gt 1 ]; then
                    error_and_exit 'find multi grub.cfg files.'
                fi
            fi
        fi
    fi

    # 判断用 linux 还是 linuxefi
    # 现在 efi 用下载的 grub，因此不需要判断 linux 或 linuxefi
    if false && is_use_local_grub; then
        # 在x86 efi机器上，不同版本的 grub 可能用 linux 或 linuxefi 加载内核
        # 通过检测原有的条目有没有 linuxefi 字样就知道当前 grub 用哪一种
        if [ -d /boot/loader/entries/ ]; then
            entries="/boot/loader/entries/"
        fi
        if grep -q -r -E '^[[:blank:]]*linuxefi[[:blank:]]' $grub_cfg $entries; then
            efi=efi
        fi
    fi

    # 找到 grub 程序的前缀
    # 并重新生成 grub.cfg
    # 因为有些机子例如hython debian的grub.cfg少了40_custom 41_custom
    if is_use_local_grub; then
        if is_have_cmd grub2-mkconfig; then
            grub=grub2
        elif is_have_cmd grub-mkconfig; then
            grub=grub
        else
            error_and_exit "grub not found"
        fi
        $grub-mkconfig -o $grub_cfg
    fi

    # 选择用 custom.cfg (linux-bios) 还是 grub.cfg (win/linux-efi)
    if is_use_local_grub; then
        target_cfg=$(dirname $grub_cfg)/custom.cfg
    else
        target_cfg=$grub_cfg
    fi

    # 生成 linux initrd 命令
    if is_netboot_xyz; then
        linux_cmd="linux16 /reinstall-vmlinuz"
    else
        build_cmdline
        linux_cmd="linux$efi /reinstall-vmlinuz $cmdline"
        initrd_cmd="initrd$efi /reinstall-initrd"
    fi

    # 生成 grub 配置
    echo $target_cfg
    cat <<EOF | tee $target_cfg
set timeout=5
menuentry "$(get_entry_name)" {
    insmod all_video
    search --no-floppy --file --set=root /reinstall-vmlinuz
    $linux_cmd
    $initrd_cmd
}
EOF

    # 设置重启引导项
    if is_use_local_grub; then
        $grub-reboot "$(get_entry_name)"
    fi
fi

info 'info'
echo "$distro $releasever"
if is_netboot_xyz; then
    echo 'Reboot to start netboot.xyz.'
elif is_alpine_live; then
    echo 'Reboot to start Alpine Live OS.'
elif is_use_dd; then
    echo 'Reboot to start DD.'
else
    if [ "$distro" = windows ]; then
        username="administrator"
    else
        username="root"
    fi

    echo "Username: $username"
    echo "Password: 123@@@"
    echo "Reboot to start the installation."
fi

#!/bin/bash
# shellcheck disable=SC2086

set -eE
confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
localtest_confhome=http://192.168.253.1

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
                    fedora   37|38
                    debian   10|11|12
                    ubuntu   20.04|22.04
                    alpine   3.16|3.17|3.18
                    opensuse 15.4|15.5|tumbleweed
                    arch
                    gentoo
                    dd       --img=xxx
                    windows  --iso=xxx --image-name=xxx
EOF
    exit 1
}

info() {
    upper=$(echo "$*" | tr '[:lower:]' '[:upper:]')
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
    command curl --connect-timeout 5 --retry 2 --retry-delay 1 -f "$@"
}

is_in_china() {
    if [ -z $_is_in_china ]; then
        # https://geoip.fedoraproject.org/city # 不支持 ipv6
        # https://geoip.ubuntu.com/lookup # 不支持 ipv6
        curl -L http://www.cloudflare.com/cdn-cgi/trace | grep -qx 'loc=CN'
        _is_in_china=$?
    fi
    return $_is_in_china
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

get_host_by_url() {
    cut -d/ -f3 <<<$1
}

insert_into_file() {
    file=$1
    location=$2
    regex_to_find=$3

    line_num=$(grep -E -n "$regex_to_find" "$file" | cut -d: -f1)
    if [ "$location" = before ]; then
        line_num=$((line_num - 1))
    elif ! [ "$location" = after ]; then
        return 1
    fi

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
    echo $url

    failed() {
        $grace && return 1
        error_and_exit "$@"
    }

    tmp_file=/tmp/reinstall-img-test
    if ! curl -r 0-1048575 -Lo "$tmp_file" "$url"; then
        failed "$url not accessible"
    fi

    if [ -n "$expect_type" ]; then
        # gzip的mime有很多种写法
        # centos7中显示为 x-gzip，在其他系统中显示为 gzip，可能还有其他
        # 所以不用mime判断
        # https://www.digipres.org/formats/sources/tika/formats/#application/gzip

        # 有些 file 版本输出的是 # ISO 9660 CD-ROM filesystem data ，要去掉开头的井号
        install_pkg file
        real_type=$(file -b $tmp_file | sed 's/^# //' | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
        [ -n "$var_to_eval" ] && eval $var_to_eval=$real_type

        if ! grep -wo "$real_type" <<<"$expect_type"; then
            failed "$url expected: $expect_type. actual: $real_type."
        fi
    fi
}

add_community_repo_for_alpine() {
    # 先检查原来的repo是不是egde
    if grep -x 'http.*/edge/main' /etc/apk/repositories; then
        alpine_ver=edge
    else
        alpine_ver=v$(cut -d. -f1,2 </etc/alpine-release)
    fi

    if ! grep -x "http.*/$alpine_ver/community" /etc/apk/repositories; then
        echo http://dl-cdn.alpinelinux.org/alpine/$alpine_ver/community >>/etc/apk/repositories
    fi
}

is_virt() {
    if is_in_windows; then
        # https://github.com/systemd/systemd/blob/main/src/basic/virt.c
        # https://sources.debian.org/src/hw-detect/1.159/hw-detect.finish-install.d/08hw-detect/
        vmstr='VMware|Virtual|Virtualization|VirtualBox|VMW|Hyper-V|Bochs|QEMU|KVM|OpenStack|KubeVirt|innotek|Xen|Parallels|BHYVE'
        for name in ComputerSystem BIOS BaseBoard; do
            wmic $name | grep -Eiw $vmstr && return 0
        done
        wmic /namespace:'\\root\cimv2' PATH Win32_Fan | head -1 | grep -q -v Name
    else
        # aws t4g debian 11 systemd-detect-virt 为 none，即使装了dmidecode
        # virt-what: 未装 deidecode时结果为空，装了deidecode后结果为aws
        # 所以综合两个命令的结果来判断
        if command -v systemd-detect-virt && systemd-detect-virt; then
            return 0
        fi
        # debian 安装 virt-what 不会自动安装 dmidecode，因此结果有误
        install_pkg dmidecode virt-what
        # virt-what 返回值始终是0，所以用是否有输出作为判断
        [ -n "$(virt-what)" ]
    fi
}

setos() {
    local step=$1
    local distro=$2
    local releasever=$3
    info set $step $distro $releasever

    setos_alpine() {
        flavour=lts
        if is_virt; then
            # alpine aarch64 3.18 才有 virt 直连链接
            if [ "$basearch" == aarch64 ]; then
                install_pkg bc
                (($(echo "$releasever >= 3.18" | bc))) && flavour=virt
            else
                flavour=virt
            fi
        fi

        if [ "$localtest" = 1 ]; then
            mirror=$confhome/alpine-netboot-3.18.0-x86_64/boot
            eval ${step}_vmlinuz=$mirror/vmlinuz-$flavour
            eval ${step}_initrd=$mirror/initramfs-$flavour
            eval ${step}_repo=http://mirrors.tuna.tsinghua.edu.cn/alpine/v$releasever/main
            eval ${step}_modloop=$mirror/modloop-$flavour
        else
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
        fi
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
            if [ "$localtest" = 1 ]; then
                mirror=$confhome/debian/install.amd
                eval ${step}_vmlinuz=$mirror/vmlinuz
                eval ${step}_initrd=$mirror/initrd.gz
            else
                if is_in_china; then
                    hostname=ftp.cn.debian.org
                else
                    hostname=deb.debian.org
                fi
                mirror=http://$hostname/debian/dists/$codename/main/installer-$basearch_alt/current/images/netboot/debian-installer/$basearch_alt
                eval ${step}_vmlinuz=$mirror/linux
                eval ${step}_initrd=$mirror/initrd.gz
            fi
            eval ${step}_ks=$confhome/debian.cfg

            is_virt && flavour=-cloud
            # 甲骨文 debian 10 amd64 cloud 内核 vnc 没有显示
            [ "$releasever" -eq 10 ] && [ "$basearch_alt" = amd64 ] && flavour=
            # shellcheck disable=SC2034
            kernel=linux-image$flavour-$basearch_alt
        fi
    }

    setos_ubuntu() {
        if is_use_cloud_image; then
            # cloud image
            # TODO: Minimal 镜像
            if is_in_china; then
                ci_mirror=https://mirror.nju.edu.cn/ubuntu-cloud-images
            else
                ci_mirror=https://cloud-images.ubuntu.com
            fi
            eval ${step}_img=$ci_mirror/releases/$releasever/release/ubuntu-$releasever-server-cloudimg-$basearch_alt.img
        else
            # 传统安装
            if [ "$localtest" = 1 ]; then
                mirror=$confhome/
            else
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
            fi

            # iso
            filename=$(curl -L $mirror | grep -oP "ubuntu-$releasever.*?-live-server-$basearch_alt.iso" | head -1)
            iso=$mirror/$filename
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

        # 清华源缺少 aarch64 tumbleweed appliances
        # https://mirrors.tuna.tsinghua.edu.cn/opensuse/ports/aarch64/tumbleweed/appliances/
        #           https://mirrors.nju.edu.cn/opensuse/ports/aarch64/tumbleweed/appliances/

        if is_in_china; then
            mirror=https://mirrors.nju.edu.cn/opensuse
        else
            mirror=https://mirror.fcix.net/opensuse
        fi

        if grep -iq Tumbleweed <<<"$releasever"; then
            # Tumbleweed
            releasever=Tumbleweed
            if [ "$basearch" = aarch64 ]; then
                dir=ports/aarch64/tumbleweed/appliances
            else
                dir=tumbleweed/appliances
            fi
        else
            # 常规版本
            # 如果用户输入的版本号是 15，需要查询小版本号
            if ! grep -q '\.' <<<"$releasever"; then
                releasever=$(curl -L https://download.opensuse.org/download/distribution/openSUSE-stable/appliances/boxes/?json |
                    grep -oP "(?<=\"name\":\"Leap-)$releasever\.[0-9]*" | head -1)
            fi
            if [ "$releasever" = 15.4 ]; then
                openstack=-OpenStack
            fi
            dir=distribution/leap/$releasever/appliances
            releasever=Leap-$releasever
        fi

        # 有专门的kvm镜像，openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2，但里面没有cloud-init
        eval ${step}_img=$mirror/$dir/openSUSE-$releasever-Minimal-VM.$basearch$openstack-Cloud.qcow2
    }

    setos_windows() {
        if [ -z "$iso" ] || [ -z "$image_name" ]; then
            error_and_exit "Install Windows need --iso --image-name"
        fi
        # 防止常见错误
        # --image-name 肯定大于等于3个单词
        if [ "$(echo "$image_name" | wc -w)" -lt 3 ]; then
            error_and_exit "--image-name wrong."
        fi
        eval "${step}_iso='$iso'"
        eval "${step}_image_name='$image_name'"
    }

    # shellcheck disable=SC2154
    setos_dd() {
        if [ -z "$img" ]; then
            error_and_exit "dd need --img"
        fi
        eval "${step}_img='$img'"
        eval "${step}_img_type='$img_type'"
    }

    setos_redhat() {
        if is_use_cloud_image; then
            # ci
            [ "$distro" = "centos" ] && [ "$releasever" = "7" ] && stream_suffix="" || stream_suffix="-stream"
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
                "7") ci_image=$ci_mirror/$releasever$stream_suffix/images/CentOS-7-$basearch-GenericCloud.qcow2 ;;
                "8" | "9") ci_image=$ci_mirror/$releasever$stream_suffix/$basearch/images/CentOS-Stream-GenericCloud-$releasever-latest.$basearch.qcow2 ;;
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
            if [ "$localtest" = 1 ]; then
                mirror=$confhome/$releasever/
            else
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
            fi

            eval ${step}_ks=$confhome/redhat.cfg
            eval ${step}_vmlinuz=${mirror}images/pxeboot/vmlinuz
            eval ${step}_initrd=${mirror}images/pxeboot/initrd.img
            eval ${step}_squashfs=${mirror}images/install.img
            if [ "$releasever" = 7 ]; then
                eval ${step}_squashfs=${mirror}LiveOS/squashfs.img
            fi
        fi
    }

    eval ${step}_distro=$distro
    if is_distro_like_redhat $distro; then
        setos_redhat
    else
        setos_$distro
    fi
}

is_distro_like_redhat() {
    [ "$1" = centos ] || [ "$1" = alma ] || [ "$1" = rocky ] || [ "$1" = fedora ]
}

# 检查是否为正确的系统名
verify_os_string() {
    for os in \
        'centos   7|8|9' \
        'alma     8|9' \
        'rocky    8|9' \
        'fedora   37|38' \
        'debian   10|11|12' \
        'ubuntu   20.04|22.04' \
        'alpine   3.16|3.17|3.18' \
        'opensuse 15|15.4|15.5|tumbleweed' \
        'arch' \
        'gentoo' \
        'windows' \
        'dd'; do
        ds=$(awk '{print $1}' <<<"$os")
        vers=$(awk '{print $2}' <<<"$os" | sed 's \. \\\. g')
        finalos=$(echo "$@" | tr '[:upper:]' '[:lower:]' | sed -n -E "s,^($ds)[ :-]?(|$vers)$,\1:\2,p")
        if [ -n "$finalos" ]; then
            distro=$(echo $finalos | cut -d: -f1)
            releasever=$(echo $finalos | cut -d: -f2)
            if [ -z "$releasever" ]; then
                # 默认版本号
                if grep -q '|' <<<$os; then
                    if [ "$distro" = opensuse ]; then
                        field='NF-1'
                    else
                        field='NF'
                    fi
                    releasever=$(awk '{print $2}' <<<$os | awk -F'|' "{print \$($field)}")
                fi
            fi
            return
        fi
    done

    error "Please specify a proper os"
    usage_and_exit
}

install_pkg() {
    is_in_windows && return

    for cmd in "$@"; do
        if ! command -v $cmd ||
            # gentoo 默认编译的 unsquashfs 不支持 xz
            { [ "$cmd" = unsquashfs ] &&
                command -v emerge &&
                ! unsquashfs |& grep -w xz &&
                echo "unsquashfs not supported xz. need rebuild."; }; then

            if ! find_pkg_mgr; then
                error_and_exit "Can't find compatible package manager. Please manually install $cmd."
            fi
            cmd_to_pkg
            install_pkg_real
        fi
    done

    find_pkg_mgr() {
        if [ -z "$pkg_mgr" ]; then
            # command -v 有先后顺序，dnf放yum前面
            if ! pkg_mgr=$(command -v dnf yum apt pacman zypper emerge apk | head -1 | awk -F/ '{print $NF}' | grep .); then
                return 1
            fi
        fi
    }

    cmd_to_pkg() {
        unset USE
        case $cmd in
        lsmem | lsblk) pkg="util-linux" ;;
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
            apt install -y $pkg
            ;;
        esac
    }
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
    alpine) ram_installer=0 ;; # 未测试
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

collect_netconf() {
    if is_in_windows; then
        # TODO:
        echo
    else
        # TODO: 多网卡 单网卡多IP
        nic_name=$(ip -o addr show scope global | head -1 | awk '{print $2}')
        mac_addr=$(ip addr show scope global | grep link/ether | head -1 | awk '{print $2}')
        ipv4_addr=$(ip -4 addr show scope global | grep inet | head -1 | awk '{print $2}')
        ipv6_addr=$(ip -6 addr show scope global | grep inet6 | head -1 | awk '{print $2}')

        ipv4_gateway=$(ip -4 route show default dev $nic_name | awk '{print $3}')
        ipv6_gateway=$(ip -6 route show default dev $nic_name | awk '{print $3}')

        echo 1 $mac_addr
        echo 2 $ipv4_addr
        echo 3 $ipv4_gateway
        echo 4 $ipv6_addr
        echo 5 $ipv6_gateway
    fi
}

install_grub_win() {
    grub_cfg=$1 # /cygdrive/$c/grub.cfg

    # 下载 grub
    info download grub
    grub_ver=2.06
    is_in_china && grub_url=https://mirrors.tuna.tsinghua.edu.cn/gnu/grub/grub-$grub_ver-for-windows.zip ||
        grub_url=https://ftp.gnu.org/gnu/grub/grub-$grub_ver-for-windows.zip
    echo $grub_url
    curl -Lo /tmp/grub.zip $grub_url
    # unzip -qo /tmp/grub.zip
    7z x /tmp/grub.zip -o/tmp -r -y -xr!i386-efi -xr!locale -xr!themes -bso0
    grub_exe_dir=$(readlink -f /tmp/grub-$grub_ver-for-windows)

    # 设置 grub 内嵌的模块
    grub_modules+=" normal minicmd ls echo test cat reboot halt linux chain search all_video configfile"
    grub_modules+=" scsi part_msdos part_gpt fat ntfs ntfscomp ext2 lvm xfs lzopio xzio gzio zstd"
    if ! is_efi; then
        grub_modules+=" biosdisk"
    fi

    # 设置 grub prefix 为c盘根目录
    # 运行 grub-probe 会改变cmd窗口字体
    prefix=$($grub_exe_dir/grub-probe -t drive $c: | sed 's,.*PhysicalDrive,(hd,' | sed 's,\r,,')/
    echo $prefix

    # 安装 grub
    if is_efi; then
        # efi
        info install grub for efi

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
        grub_dir=$x:\\EFI\\reinstall
        mkdir -p $grub_dir
        # grub-mkimage 可设置prefix，也可嵌入配置文件（官方不建议嵌入menuentry条目）
        #  -c $grub_cfg_win
        $grub_exe_dir/grub-mkimage -p $prefix -O x86_64-efi -o $grub_dir\\grubx64.efi $grub_modules

        # 添加引导
        # 脚本可能不是首次运行，所以先删除原来的
        bcdedit /enum bootmgr | grep --text -B3 Reinstall | awk '{print $2}' | grep '{.*}' |
            xargs -I {} cmd /c bcdedit /delete {}
        id=$(bcdedit /copy '{bootmgr}' /d Reinstall | grep -o '{.*}')
        bcdedit /set $id device partition=$x:
        bcdedit /set $id path \\EFI\\reinstall\\grubx64.efi
        bcdedit /set '{fwbootmgr}' bootsequence $id
    else
        # bios
        info install grub for bios

        # bootmgr 加载 gr2ldr 有64k限制
        # 解决方法1 gr2ldr.mbr + gr2ldr
        # 解决方法2 生成少于64K的 g2ldr + 动态模块

        # gr2ldr.mbr
        curl -LO http://ftp.cn.debian.org/debian/tools/win32-loader/stable/win32-loader.exe
        7z x win32-loader.exe 'g2ldr.mbr' -o/tmp/win32-loader -r -y -bso0
        find /tmp/win32-loader -name 'g2ldr.mbr' -exec cp {} /cygdrive/$c/ \;

        # g2ldr
        $grub_exe_dir/grub-mkimage -p "$prefix" -O i386-pc -o core.img $grub_modules
        cat $grub_exe_dir/i386-pc/lnxboot.img core.img >/cygdrive/$c/g2ldr

        # 添加引导
        # 脚本可能不是首次运行，所以先删除原来的
        id='{1c41f649-1637-52f1-aea8-f96bfebeecc8}'
        bcdedit /enum all | grep --text $id && bcdedit /delete $id
        bcdedit /create $id /d Reinstall /application bootsector
        bcdedit /set $id device partition=$c:
        bcdedit /set $id path \\g2ldr.mbr
        bcdedit /displayorder $id /addlast
        bcdedit /bootsequence $id /addfirst
    fi
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
if ! opts=$(getopt -n $0 -o "" --long localtest,debug,sleep:,iso:,image-name:,img:,ci,cloud-image -- "$@"); then
    usage_and_exit
fi

eval set -- "$opts"
# shellcheck disable=SC2034
while true; do
    case "$1" in
    --localtest)
        localtest=1
        confhome=$localtest_confhome
        shift
        ;;
    --debug)
        set -x
        shift
        ;;
    --ci | --cloud-image)
        cloud_image=1
        shift
        ;;
    --sleep)
        sleep=$2
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

# 验证目标系统字符串
verify_os_string "$@"

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
if ! { [ "$distro" = dd ] || [ "$distro" = windows ]; }; then
    check_ram
fi

# alpine --ci 参数无效
if [ "$distro" = alpine ] && is_use_cloud_image; then
    error_and_exit "can't install alpine with cloud image"
fi

# 检查硬件架构
# x86强制使用x64
basearch=$(uname -m)
[ $basearch = i686 ] && basearch=x86_64
case "$basearch" in
"x86_64") basearch_alt=amd64 ;;
"aarch64") basearch_alt=arm64 ;;
esac

# 国内使用 gitee
if [ "$confhome" = https://raw.githubusercontent.com/bin456789/reinstall/main ] &&
    is_in_china; then
    confhome=https://gitee.com/bin456789/reinstall/raw/main
fi

# 以下目标系统不需要进入alpine
# debian
# el7 x86_64 >=1g
# el7 aarch64 >=1.5g
# el8/9/fedora 任何架构 >=2g
if ! is_use_cloud_image &&
    { [ "$distro" = "debian" ] ||
        { is_distro_like_redhat "$distro" && [ $releasever -eq 7 ] && [ $ram_size -ge 1024 ] && [ $basearch = "x86_64" ]; } ||
        { is_distro_like_redhat "$distro" && [ $releasever -eq 7 ] && [ $ram_size -ge 1536 ] && [ $basearch = "aarch64" ]; } ||
        { is_distro_like_redhat "$distro" && [ $releasever -ge 8 ] && [ $ram_size -ge 2048 ]; }; }; then
    setos nextos $distro $releasever
else
    # 安装alpine时，使用指定的版本。 alpine作为中间系统时，使用 3.18
    [ "$distro" = "alpine" ] && alpine_releasever=$releasever || alpine_releasever=3.18
    setos finalos $distro $releasever
    setos nextos alpine $alpine_releasever
fi

# 测试链接
# 在 ubuntu 20.04 上，file 命令检测 ubuntu 22.04 iso 结果不正确，所以去掉 iso 检测
if is_use_cloud_image; then
    test_url $finalos_img 'xz|gzip|qemu' finalos_img_type
elif is_use_dd; then
    test_url $finalos_img 'xz|gzip' finalos_img_type
elif [ -n "$finalos_img" ]; then
    test_url $finalos_img
elif [ -n "$finalos_iso" ]; then
    test_url $finalos_iso
fi

# shellcheck disable=SC2154
{
    # 下载 nextos 内核
    info download vmlnuz and initrd
    echo $nextos_vmlinuz
    curl -Lo /reinstall-vmlinuz $nextos_vmlinuz

    echo $nextos_initrd
    curl -Lo /reinstall-initrd $nextos_initrd
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
    for key in localtest confhome sleep cloud_image kernel; do
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
    # 由于 windows 下无法测试各tty是否有效
    # 这里的 tty 只临时使用，非最终系统的 tty
    if is_in_windows; then
        echo "console=ttyS0,115200n8 console=tty0"
    else
        curl -L $confhome/ttys.sh | sh -s "console="
    fi
}

# shellcheck disable=SC2154
build_cmdline() {
    if [ -n "$finalos_cmdline" ]; then
        # 有 finalos_cmdline 表示需要两步安装
        # 两步安装需要修改 alpine initrd
        mod_alpine_initrd

        # 可添加 pkgs=xxx,yyy 启动时自动安装
        # apkovl=http://xxx.com/apkovl.tar.gz 可用，arm https未测但应该不行
        # apkovl=sda2:ext4:/apkovl.tar.gz 官方有写但不生效
        cmdline="alpine_repo=$nextos_repo modloop=$nextos_modloop $extra_cmdline $finalos_cmdline"
    else
        if [ $distro = debian ]; then
            cmdline="lowmem=+1 lowmem/low=1 auto=true priority=critical url=$nextos_ks $extra_cmdline"
        else
            # redhat
            cmdline="root=live:$nextos_squashfs inst.ks=$nextos_ks $extra_cmdline"
        fi
    fi
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

    # hack 2
    # udhcpc 添加 -n 参数，请求dhcp失败后退出
    # 使用同样参数运行 udhcpc6
    # TODO: digitalocean -i eth1?
    # shellcheck disable=SC2016
    orig_cmd="$(grep '$MOCK udhcpc' init)"
    mod_cmd4="$orig_cmd -n || true"
    mod_cmd6="${mod_cmd4//udhcpc/udhcpc6}"
    sed -i "/\$MOCK udhcpc/c$mod_cmd4 \n $mod_cmd6" init

    # hack 3 /usr/share/udhcpc/default.script
    # 脚本被调用的顺序
    # udhcpc:  deconfig
    # udhcpc:  bound
    # udhcpc6: deconfig
    # udhcpc6: bound
    insert_into_file usr/share/udhcpc/default.script after 'deconfig\|renew\|bound' <<EOF
        if [ "\$1" = deconfig ]; then
            return
        fi
        if [ "\$1" = bound ] && [ -n "\$ipv6" ]; then
            ip -6 addr add \$ipv6 dev \$interface
            ip link set dev \$interface up
            return
        fi
EOF

    # hack 4 网络配置
    collect_netconf
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
    find . | cpio -o -H newc | gzip -1 >/reinstall-initrd
    cd -
}

build_finalos_cmdline
build_extra_cmdline
build_cmdline

info 'create grub config'
# linux grub
if ! is_in_windows; then
    if command -v update-grub; then
        grub_cfg=$(grep -o '[^ ]*grub.cfg' "$(which update-grub)")
    else
        # 找出主配置文件（含有menuentry|blscfg）
        # 如果是efi，先搜索efi目录
        # arch云镜像efi分区挂载在/efi
        if is_efi; then
            for dir in /boot/efi /efi; do
                [ -d $dir ] && efi_dir+=" $dir"
            done
        fi
        grub_cfg=$(
            find $efi_dir /boot/grub* \
                -type f -name grub.cfg \
                -exec grep -E -l 'menuentry|blscfg' {} \;
        )

        if [ "$(wc -l <<<"$grub_cfg")" -gt 1 ]; then
            error_and_exit 'find multi grub.cfg files.'
        fi
    fi

    # 有些机子例如hython debian的grub.cfg少了40_custom 41_custom
    # 所以先重新生成 grub.cfg
    $(command -v grub-mkconfig grub2-mkconfig) -o $grub_cfg

    # 在x86 efi机器上，不同版本的 grub 可能用 linux 或 linuxefi 加载内核
    # 通过检测原有的条目有没有 linuxefi 字样就知道当前 grub 用哪一种
    if [ -d /boot/loader/entries/ ]; then
        entries="/boot/loader/entries/"
    fi
    if grep -q -r -E '^[[:blank:]]*linuxefi[[:blank:]]' $grub_cfg $entries; then
        efi=efi
    fi
fi

# 生成 custom.cfg (linux) 或者 grub.cfg (win)
is_in_windows && custom_cfg=/cygdrive/$c/grub.cfg || custom_cfg=$(dirname $grub_cfg)/custom.cfg
echo $custom_cfg
cat <<EOF | tee $custom_cfg
set timeout=5
menuentry "reinstall" {
    insmod lvm
    insmod xfs
    search --no-floppy --file --set=root /reinstall-vmlinuz
    linux$efi /reinstall-vmlinuz $(echo_tmp_ttys) $cmdline
    initrd$efi /reinstall-initrd
}
EOF

if is_in_windows; then
    mv /reinstall-vmlinuz /cygdrive/$c/
    mv /reinstall-initrd /cygdrive/$c/
    install_grub_win $custom_cfg
else
    if is_os_in_btrfs && is_os_in_subvol; then
        cp_to_btrfs_root /reinstall-vmlinuz
        cp_to_btrfs_root /reinstall-initrd
    fi
    $(command -v grub-reboot grub2-reboot) reinstall
fi

if is_use_cloud_image; then
    info 'cloud image mode'
elif is_use_dd; then
    info 'dd mode'
else
    info 'installer mode'
fi

info 'Please reboot to begin the installation'

#!/bin/bash
set -eE
confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
localtest_confhome=http://192.168.253.1

trap 'error line $LINENO return $?' ERR

usage_and_exit() {
    echo "Usage: reinstall.sh centos-7/8/9 alma-8/9 rocky-8/9 fedora-37/38 ubuntu-20.04/22.04 alpine-3.16/3.17/3.18 debian-10/11/12 windows dd"
    exit 1
}

info() {
    color='\e[32m'
    plain='\e[0m'
    upper=$(echo "$@" | tr '[:lower:]' '[:upper:]')
    echo -e "$color***** $upper *****$plain"
}

error() {
    color='\e[31m'
    plain='\e[0m'
    echo -e "${color}Error: $*$plain"
}

error_and_exit() {
    error "$@"
    exit 1
}

curl() {
    command curl --connect-timeout 5 --retry 3 --retry-delay 0 "$@"
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

is_in_arch() {
    [ -f /etc/arch-release ]
}

is_use_cloud_image() {
    [ -n "$cloud_image" ] && [ "$cloud_image" = 1 ]
}

is_host_has_ipv4_and_ipv6() {
    install_pkg dig
    # dig会显示cname结果，cname结果以.结尾，grep -v '\.$' 用于去除 cname 结果
    res=$(dig +short $host A $host AAAA | grep -v '\.$')
    # 有.表示有ipv4地址，有:表示有ipv6地址
    grep -q \. <<<$res && grep -q : <<<$res
}

get_host_by_url() {
    cut -d/ -f3 <<<$1
}

set_github_proxy() {
    case "$confhome" in
    http*://raw.githubusercontent.com/*)
        if is_in_china; then
            confhome=https://ghproxy.com/$confhome
        fi
        ;;
    esac
}

test_url() {
    url=$1
    expect_type=$2
    var_to_eval=$3
    info test url
    echo $url

    tmp_file=/tmp/reinstall-img-test

    http_code=$(command curl --connect-timeout 5 -Ls -r 0-1048575 -w "%{http_code}" -o $tmp_file $url)
    if [ "$http_code" != 200 ] && [ "$http_code" != 206 ]; then
        error "$url not accessible"
        return 1
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

        if ! echo $expect_type | grep -wo "$real_type"; then
            error "$url expect: $expect_type. real: $real_type."
            return 1
        fi
    fi
}

add_community_repo_for_alpine() {
    if ! grep -x 'http.*/community' /etc/apk/repositories; then
        alpine_ver=$(cut -d. -f1,2 </etc/alpine-release)
        echo http://dl-cdn.alpinelinux.org/alpine/v$alpine_ver/community >>/etc/apk/repositories
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
        12) codename=bookworm ;;
        11) codename=bullseye ;;
        10) codename=buster ;;
        esac

        if is_use_cloud_image; then
            # cloud image
            ci_mirror=https://cloud.debian.org/images/cloud
            is_virt && ci_type=genericcloud || ci_type=generic
            eval ${step}_img=$ci_mirror/$codename/latest/debian-$releasever-$ci_type-$basearch_alt.qcow2
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
        fi
    }

    setos_ubuntu() {
        if is_use_cloud_image; then
            # cloud image
            # TODO: Minimal 镜像
            if is_in_china; then
                ci_mirror=https://mirror.nju.edu.cn/ubuntu-cloud-images/releases
            else
                ci_mirror=https://cloud-images.ubuntu.com/releases/$releasever/release
            fi
            eval ${step}_img=$ci_mirror/ubuntu-$releasever-server-cloudimg-$basearch_alt.img
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
            test_url $iso iso || exit 1
            eval ${step}_iso=$iso

            # ks
            eval ${step}_ks=$confhome/ubuntu.yaml
        fi
    }

    setos_arch() {
        if is_use_cloud_image; then
            # cloud image
            if is_in_china; then
                ci_mirror=https://mirrors.tuna.tsinghua.edu.cn/archlinux
            else
                ci_mirror=https://geo.mirror.pkgbuild.com
            fi
            # eval ${step}_img=$ci_mirror/images/latest/Arch-Linux-x86_64-basic.qcow2
            eval ${step}_img=$ci_mirror/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
        else
            # 先略过
            error_and_exit 'not support without --ci'
        fi
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
        test_url $iso iso || exit 1
        eval "${step}_iso='$iso'"
        eval "${step}_image_name='$image_name'"
    }

    # shellcheck disable=SC2154
    setos_dd() {
        if [ -z "$img" ]; then
            error_and_exit "dd need --img"
        fi
        test_url $img 'xz|gzip' img_type || exit 1
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
            # TODO: alma8 有独立的uefi镜像
            "alma") ci_image=$ci_mirror/AlmaLinux-$releasever-GenericCloud-latest.$basearch.qcow2 ;;
            "rocky") ci_image=$ci_mirror/Rocky-$releasever-GenericCloud-Base.latest.$basearch.qcow2 ;;
            # TODO: 小版本号
            "fedora") ci_image=$ci_mirror/Fedora-Cloud-Base-$releasever-1.6.$basearch.qcow2 ;;
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
                        test_url ${cur_mirror}images/pxeboot/vmlinuz; then
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
    case "$distro" in
    ubuntu) setos_ubuntu ;;
    alpine) setos_alpine ;;
    debian) setos_debian ;;
    arch) setos_arch ;;
    windows) setos_windows ;;
    dd) setos_dd ;;
    *) setos_redhat ;;
    esac
}

is_distro_like_redhat() {
    [ "$1" = centos ] || [ "$1" = alma ] || [ "$1" = rocky ] || [ "$1" = fedora ]
}

# 检查是否为正确的系统名
verify_os_string() {
    for os in 'centos-7|8|9' 'alma|rocky-8|9' 'fedora-37|38' 'ubuntu-20.04|22.04' 'alpine-3.16|3.17|3.18' 'debian-10|11|12' 'arch-' 'windows-' 'dd-'; do
        ds=$(echo $os | cut -d- -f1)
        vers=$(echo $os | cut -d- -f2 | sed 's \. \\\. g')
        finalos=$(echo "$@" | tr '[:upper:]' '[:lower:]' | sed -n -E "s,^($ds)[ :-]?($vers)$,\1:\2,p")
        if [ -n "$finalos" ]; then
            distro=$(echo $finalos | cut -d: -f1)
            releasever=$(echo $finalos | cut -d: -f2)
            return
        fi
    done

    error "Please specify a proper os"
    usage_and_exit
}

apt_install() {
    [ -z "$apk_updated" ] && apt update && apk_updated=1
    apt install -y $pkgs
}

install_pkg() {
    cmds=$*

    is_in_windows && return

    # arch 需先加载 squashfs 模块
    # arch 安装软件时一旦升级了内核，旧的内核文件夹就立即被删除，无法再加载模块
    if ! lsmod | grep squashfs; then
        modprobe squashfs
    fi

    need_install=false
    for cmd in $cmds; do
        if ! command -v $cmd >/dev/null; then
            need_install=true
            break
        fi
    done

    if $need_install; then
        if is_in_alpine; then
            add_community_repo_for_alpine
        fi
        # cmds to pkgs
        for cmd in $cmds; do
            case $cmd in
            lsmem) pkg=util-linux ;;
            nslookup | dig)
                if is_in_alpine; then
                    pkg="bind-tools"
                elif is_in_arch; then
                    pkg="bind"
                else
                    pkg="bind*-*utils"
                fi
                ;;
            *) pkg=$cmd ;;
            esac
            pkgs+=" $pkg"
        done
        {
            apt_install $pkgs ||
                dnf install -y $pkgs ||
                yum install -y $pkgs ||
                zypper install -y $pkgs ||
                pacman -Syu --noconfirm $pkgs ||
                apk add $pkgs
        } 2>/dev/null
    fi
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

    case "$distro" in
    alpine) ram_requirement=0 ;; # 未测试
    debian) ram_requirement=384 ;;
    *) ram_requirement=1024 ;;
    esac

    if [ -z $ram_size ] || [ $ram_size -le 0 ]; then
        error_and_exit "Could not detect RAM size."
    fi

    # ram 足够就用普通方法安装，否则如果内存大于512就用 cloud image
    if [ $ram_size -lt $ram_requirement ]; then
        # TODO: 测试 256 384 内存
        ram_requirement=512
        if false && [ $ram_size -ge $ram_requirement ]; then
            info "RAM < $ram_requirement MB. Switch to cloud image mode"
            cloud_image=1
        else
            error_and_exit "Could not install $distro: RAM < $ram_requirement MB."
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
if ! is_use_cloud_image; then
    check_ram
fi

# 检查硬件架构
# x86强制使用x64
basearch=$(uname -m)
[ $basearch = i686 ] && basearch=x86_64
case "$basearch" in
"x86_64") basearch_alt=amd64 ;;
"aarch64") basearch_alt=arm64 ;;
esac

# 设置 github 国内代理
set_github_proxy

# 以下目标系统需要进入alpine环境安装
# cloud image
# ubuntu/alpine/windows/dd
# el8/9/fedora 任何架构 <2g
# el7 aarch64 <1.5g
if is_use_cloud_image ||
    [ "$distro" = "ubuntu" ] ||
    [ "$distro" = "alpine" ] ||
    [ "$distro" = "arch" ] ||
    [ "$distro" = "windows" ] ||
    [ "$distro" = "dd" ] ||
    { is_distro_like_redhat "$distro" && [ $releasever -ge 8 ] && [ $ram_size -lt 2048 ]; } ||
    { is_distro_like_redhat "$distro" && [ $releasever -eq 7 ] && [ $ram_size -lt 1536 ] && [ $basearch = "aarch64" ]; }; then
    # 安装alpine时，使用指定的版本。 alpine作为中间系统时，使用 3.18
    [ "$distro" = "alpine" ] && alpine_releasever=$releasever || alpine_releasever=3.18
    setos finalos $distro $releasever
    setos nextos alpine $alpine_releasever
else
    setos nextos $distro $releasever
fi

# shellcheck disable=SC2154
{
    # 测试 cloud img 链接
    if is_use_cloud_image; then
        test_url $finalos_img
    fi

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
    for key in localtest confhome sleep cloud_image; do
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
            cmdline="lowmem=+1 lowmem/low=1 auto=true priority=critical url=$nextos_ks"
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
    { umount $dir || umount -R $dir || true; } 2>/dev/null
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

    # virt 内核添加 ipv6 模块
    if virt_dir=$(ls -d $tmp_dir/lib/modules/*-virt 2>/dev/null); then
        ipv6_dir=$virt_dir/kernel/net/ipv6
        mkdir -p $ipv6_dir
        modloop_file=/tmp/modloop_file
        modloop_dir=/tmp/modloop_dir
        curl -Lo $modloop_file $nextos_modloop
        if is_in_windows; then
            # cygwin 无法 mount，只能解压
            7z e $modloop_file ipv6.ko -r -y -oa$ipv6_dir
        else
            mkdir_clear $modloop_dir
            mount $modloop_file $modloop_dir
            find $modloop_dir -name ipv6.ko -exec cp {} $ipv6_dir/ \;
            umount $modloop_dir
        fi
    fi

    # hack 运行 trans.start
    # exec /bin/busybox switch_root $switch_root_opts $sysroot $chart_init "$KOPT_init" $KOPT_init_args # 3.17
    # exec              switch_root $switch_root_opts $sysroot $chart_init "$KOPT_init" $KOPT_init_args # 3.18
    line_num=$(grep -E -n '^exec (/bin/busybox )?switch_root' init | cut -d: -f1)
    line_num=$((line_num - 1))
    # 1. alpine arm initramfs 时间问题 要添加 --no-check-certificate
    # 2. 神奇的 aws t4g arm 会出现bad header错误， 但甲骨文arm就正常，所以只能预先下载
    # Connecting to raw.githubusercontent.com (185.199.108.133:443)
    # 60C0BB2FFAFF0000:error:0A00009C:SSL routines:ssl3_get_record:http request:ssl/record/ssl3_record.c:345:
    # ssl_client: SSL_connect
    # wget: bad header line: �
    cat <<EOF | sed -i "${line_num}r /dev/stdin" init
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
    # 找到主配置 grub.cfg
    grub_cfg=$(find /boot -type f -name grub.cfg -exec grep -E -l 'menuentry|blscfg' {} \;)

    # 在x86 efi机器上，不同版本的 grub 可能用 linux 或 linuxefi 加载内核
    # 通过检测原有的条目有没有 linuxefi 字样就知道当前 grub 用哪一种
    search_files=$(find /boot -type f -name grub.cfg)
    if [ -d /boot/loader/entries/ ]; then
        search_files+=" /boot/loader/entries/"
    fi
    if grep -q -r -E '^[[:blank:]]*linuxefi[[:blank:]]' $search_files; then
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
    linux$efi /reinstall-vmlinuz $cmdline
    initrd$efi /reinstall-initrd
}
EOF

if is_in_windows; then
    mv /reinstall-vmlinuz /cygdrive/$c/
    mv /reinstall-initrd /cygdrive/$c/
    install_grub_win $custom_cfg
else
    $(command -v grub-reboot grub2-reboot) reinstall
fi

info 'Please reboot to begin the installation'

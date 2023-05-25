#!/bin/bash
confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
localtest_confhome=http://192.168.253.1

usage_and_exit() {
    echo "Usage: reinstall.sh centos-7/8/9 alma-8/9 rocky-8/9 fedora-36/37/38 ubuntu-20.04/22.04 alpine-3.16/3.17/3.18 debian-10/11 windows"
    exit 1
}

is_in_china() {
    if [ -z $_is_in_china ]; then
        # https://geoip.ubuntu.com/lookup
        curl -L https://geoip.fedoraproject.org/city | grep -w CHN
        _is_in_china=$?
    fi
    return $_is_in_china
}

setos() {
    local step=$1
    local distro=$2
    local releasever=$3

    setos_alpine() {
        if [ "$localtest" = 1 ]; then
            mirror=$confhome/alpine-netboot-3.18.0-x86_64/boot
            eval ${step}_vmlinuz=$mirror/vmlinuz-lts
            eval ${step}_initrd=$mirror/initramfs-lts
            eval ${step}_repo=https://mirrors.aliyun.com/alpine/v$releasever/main
            eval ${step}_modloop=$mirror/modloop-lts
        else
            # 不要用https 因为甲骨文云arm initramfs阶段不会从硬件同步时钟，导致访问https出错
            if is_in_china; then
                mirror=http://mirrors.aliyun.com/alpine/v$releasever
            else
                mirror=http://dl-cdn.alpinelinux.org/alpine/v$releasever
            fi
            eval ${step}_vmlinuz=$mirror/releases/$basearch/netboot/vmlinuz-lts
            eval ${step}_initrd=$mirror/releases/$basearch/netboot/initramfs-lts
            eval ${step}_repo=$mirror/main
            eval ${step}_modloop=$mirror/releases/$basearch/netboot/modloop-lts
        fi
    }

    setos_debian() {
        if [ "$localtest" = 1 ]; then
            mirror=$confhome/debian/install.amd
            eval ${step}_vmlinuz=$mirror/vmlinuz
            eval ${step}_initrd=$mirror/initrd.gz
        else
            case "$releasever" in
            12) codename=bookworm ;;
            11) codename=bullseye ;;
            10) codename=buster ;;
            esac
            if is_in_china; then
                hostname=ftp.cn.debian.org
            else
                hostname=deb.debian.org
            fi
            mirror=http://$hostname/debian/dists/$codename/main/installer-$basearch_alt/current/images/netboot/debian-installer/$basearch_alt
            eval ${step}_vmlinuz=$mirror/linux
            eval ${step}_initrd=$mirror/initrd.gz
        fi
        eval ${step}_ks=$confhome/preseed.cfg
    }

    setos_ubuntu() {
        if [ "$localtest" = 1 ]; then
            mirror=$confhome/
        else
            if is_in_china; then
                case "$basearch" in
                "x86_64") mirror=https://mirrors.aliyun.com/ubuntu-releases/$releasever/ ;;
                "aarch64") mirror=https://mirrors.aliyun.com/ubuntu-cdimage/releases/$releasever/release/ ;;
                esac
            else
                case "$basearch" in
                "x86_64") mirror=https://releases.ubuntu.com/$releasever/ ;;
                "aarch64") mirror=https://cdimage.ubuntu.com/releases/$releasever/release/ ;;
                esac
            fi
        fi

        filename=$(curl $mirror | grep -oP "ubuntu-$releasever.*?-live-server-$basearch_alt.iso" | head -1)
        eval ${step}_iso=$mirror$filename
        eval ${step}_ks=$confhome/user-data
    }

    setos_windows() {
        if [ -z "$iso" ] || [ -z "$image_name" ]; then
            echo "Install Windows need --iso --image-name"
            exit 1
        fi
        eval "${step}_iso='$iso'"
        eval "${step}_image_name='$image_name'"
    }

    setos_redhat() {
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
            # rocky/centos9 需要删除第一行注释， alma 需要替换$basearch，anigil 这个源不稳定
            mirror=$(curl -L $mirrorlist | sed "/^#/d" | sed "/anigil/d" | head -1 | sed "s,\$basearch,$basearch,")
            eval "${step}_mirrorlist='${mirrorlist}'"
        fi
        eval ${step}_ks=$confhome/ks.cfg
        eval ${step}_vmlinuz=${mirror}images/pxeboot/vmlinuz
        eval ${step}_initrd=${mirror}images/pxeboot/initrd.img
        eval ${step}_squashfs=${mirror}images/install.img

        if [ "$releasever" = 7 ]; then
            eval ${step}_squashfs=${mirror}LiveOS/squashfs.img
        fi
    }

    eval ${step}_distro=$distro
    case "$distro" in
    ubuntu) setos_ubuntu ;;
    alpine) setos_alpine ;;
    debian) setos_debian ;;
    windows) setos_windows ;;
    *) setos_redhat ;;
    esac
}

# 检查是否为正确的系统名
verify_os_string() {
    for os in 'centos-7|8|9' 'alma|rocky-8|9' 'fedora-36|37|38' 'ubuntu-20.04|22.04' 'alpine-3.16|3.17|3.18' 'debian-10|11|12' 'windows-'; do
        ds=$(echo $os | cut -d- -f1)
        vers=$(echo $os | cut -d- -f2 | sed 's \. \\\. g')
        finalos=$(echo "$@" | tr '[:upper:]' '[:lower:]' | sed -n -E "s,^($ds)[ :-]?($vers)$,\1:\2,p")
        if [ -n "$finalos" ]; then
            distro=$(echo $finalos | cut -d: -f1)
            if [ "$distro" = centos ] || [ "$distro" = alma ] || [ "$distro" = rocky ]; then
                distro_like=redhat
            fi
            releasever=$(echo $finalos | cut -d: -f2)
            return
        fi
    done

    echo "Please specify a proper os."
    usage_and_exit
}

apt_install() {
    [ -z "$apk_updated" ] && apt update && apk_updated=1
    apt install -y $pkgs
}

install_pkg() {
    pkgs=$*
    for pkg in $pkgs; do
        # util-linux 用 lsmem 命令测试
        [ "$pkg" = util-linux ] && pkg=lsmem
        if ! command -v $pkg; then
            {
                apt_install $pkgs ||
                    dnf install -y $pkgs ||
                    yum install -y $pkgs ||
                    zypper install -y $pkgs ||
                    pacman -Syu $pkgs ||
                    apk add $pkgs
            } 2>/dev/null
            break
        fi
    done
}

check_ram() {
    # lsmem最准确但centos7 arm 和alpine不能用
    # arm 24g dmidecode 显示少了128m
    install_pkg util-linux
    ram_size=$(lsmem -b 2>/dev/null | grep 'Total online memory:' | awk '{ print $NF/1024/1024 }')
    if [ -z $ram_size ]; then
        install_pkg dmidecode
        ram_size=$(dmidecode -t 17 | grep "Size.*[GM]B" | awk '{if ($3=="GB") s+=$2*1024; else s+=$2} END {print s}')
    fi

    case "$distro" in
    alpine) ram_requirement=0 ;; # 未测试
    debian) ram_requirement=384 ;;
    *) ram_requirement=1024 ;;
    esac

    if [ $ram_size -lt $ram_requirement ]; then
        echo "Could not install $distro: RAM < $ram_requirement MB."
        exit 1
    fi
}

# 脚本入口
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

if ! opts=$(getopt -a -n $0 --options l --long localtest,iso:,image-name: -- "$@"); then
    usage_and_exit
fi

eval set -- "$opts"
while true; do
    case "$1" in
    -l | --localtest)
        localtest=1
        confhome=$localtest_confhome
        shift
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

verify_os_string "$@"

# 必备组件
install_pkg curl
# alpine 自带的 grep 是 busybox 里面的， 要下载完整版grep
if [ -f /etc/alpine-release ]; then
    apk add grep
fi

check_ram
basearch=$(uname -m)
case "$basearch" in
"x86_64") basearch_alt=amd64 ;;
"aarch64") basearch_alt=arm64 ;;
esac

# 以下目标系统需要进入alpine环境安装
# ubuntu/alpine
# el8/9/fedora 任何架构 <2g
# el7 aarch64 <1.5g
if [ "$distro" = "ubuntu" ] ||
    [ "$distro" = "alpine" ] ||
    [ "$distro" = "windows" ] ||
    { [ "$distro_like" = "redhat" ] && [ $releasever -ge 8 ] && [ $ram_size -lt 2048 ]; } ||
    { [ "$distro_like" = "redhat" ] && [ $releasever -eq 7 ] && [ $ram_size -lt 1536 ] && [ $basearch = "aarch64" ]; }; then
    # 安装alpine时，使用指定的版本。 alpine作为中间系统时，使用 3.18
    [ "$distro" = "alpine" ] && alpine_releasever=$releasever || alpine_releasever=3.18
    setos finalos $distro $releasever
    setos nextos alpine $alpine_releasever
else
    setos nextos $distro $releasever
fi

# 下载启动内核
# shellcheck disable=SC2154
{
    cd /
    echo $nextos_vmlinuz
    curl -Lo reinstall-vmlinuz $nextos_vmlinuz

    echo $nextos_initrd
    curl -Lo reinstall-initrd $nextos_initrd
}

# 转换 finalos_a=1 为 finalos.a=1 ，排除 finalos_mirrorlist
build_finalos_cmdline() {
    for key in $(compgen -v finalos_); do
        value=${!key}
        key=${key#finalos_}
        if [ -n "$value" ] && [ $key != "mirrorlist" ]; then
            finalos_cmdline+=" finalos.$key='$value'"
        fi
    done
}

build_extra_cmdline() {
    for key in localtest confhome; do
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

build_finalos_cmdline
build_extra_cmdline
grub_cfg=$(find /boot -type f -name grub.cfg -exec grep -E -l 'menuentry|blscfg' {} \;)
grub_cfg_dir=$(dirname $grub_cfg)

# 在x86 efi机器上，可能用 linux 或 linuxefi 加载内核
# 通过检测原有的条目有没有 linuxefi 字样就知道当前 grub 用哪一种
search_files=$(find /boot -type f -name grub.cfg)
if [ -d /boot/loader/entries/ ]; then
    search_files="$search_files /boot/loader/entries/"
fi
if grep -q -r -E '^[[:blank:]]*linuxefi[[:blank:]]' $search_files; then
    efi=efi
fi

# 修改 alpine 启动时运行我们的脚本
# shellcheck disable=SC2154,SC2164
if [ -n "$finalos_cmdline" ]; then
    install_pkg gzip cpio

    # 解压
    # 先删除临时文件，避免之前运行中断有残留文件
    tmp_dir=/tmp/reinstall/
    rm -rf $tmp_dir
    mkdir -p $tmp_dir
    cd $tmp_dir
    zcat /reinstall-initrd | cpio -idm

    # hack
    # exec /bin/busybox switch_root $switch_root_opts $sysroot $chart_init "$KOPT_init" $KOPT_init_args # 3.17
    # exec              switch_root $switch_root_opts $sysroot $chart_init "$KOPT_init" $KOPT_init_args # 3.18
    line_num=$(grep -E -n '^exec (/bin/busybox )?switch_root' init | cut -d: -f1)
    line_num=$((line_num - 1))
    cat <<EOF | sed -i "${line_num}r /dev/stdin" init
        # alpine arm initramfs 时间问题 要添加 --no-check-certificate
        wget --no-check-certificate -O \$sysroot/etc/local.d/trans.start $confhome/trans.sh
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

    # 删除临时文件
    cd /
    rm -rf $tmp_dir

    # 可添加 pkgs=xxx,yyy 启动时自动安装
    # apkovl=http://xxx.com/apkovl.tar.gz 可用，arm https未测但应该不行
    # apkovl=sda2:ext4:/apkovl.tar.gz 官方有写但不生效
    cmdline="alpine_repo=$nextos_repo modloop=$nextos_modloop $extra_cmdline $finalos_cmdline "
else
    if [ $distro = debian ]; then
        cmdline="lowmem=+1 lowmem/low=1 auto=true priority=critical url=$nextos_ks"
    else
        cmdline="root=live:$nextos_squashfs inst.ks=$nextos_ks $extra_cmdline"
    fi
fi

custom_cfg=$grub_cfg_dir/custom.cfg
echo $custom_cfg
cat <<EOF | tee $custom_cfg
menuentry "reinstall" {
    insmod lvm
    insmod xfs
    search --no-floppy --file --set=root /reinstall-vmlinuz
    linux$efi /reinstall-vmlinuz $cmdline
    initrd$efi /reinstall-initrd
}
EOF

$(command -v grub-reboot grub2-reboot) reinstall
echo "Please reboot to begin the installation."

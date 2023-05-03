#!/bin/bash
confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
localtest_confhome=http://192.168.253.1

usage_and_exit() {
    echo "Usage: reinstall.sh centos-7/8/9 alma-8/9 rocky-8/9 fedora-36/37/38 ubuntu-20.04/22.04"
    exit 1
}

is_in_china() {
    # https://geoip.ubuntu.com/lookup
    curl -L https://geoip.fedoraproject.org/city | grep -w CN
}

setos() {
    step=$1
    distro=$2
    releasever=$3
    ks=$4
    vault=$5

    setos_ubuntu() {
        if [ "$localtest" = 1 ]; then
            mirror=$confhome/
            eval ${step}_ks=$confhome/$ks
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
            eval ${step}_ks=$confhome/user-data
        fi

        case "$basearch" in
        "x86_64") arch=amd64 ;;
        "aarch64") arch=arm64 ;;
        esac

        filename=$(curl $mirror | grep -oP "ubuntu-$releasever.*?-live-server-$arch.iso" | head -1)
        eval ${step}_iso=$mirror$filename
        eval ${step}_distro=ubuntu
    }

    setos_rh() {
        if [ "$localtest" = 1 ]; then
            mirror=$confhome/$releasever/
            eval ${step}_ks=$confhome/$ks
        else
            # 甲骨文 arm 1g内存，用 centos 7.9 镜像会 oom 进不了安装界面，所以用7.6
            if [ "$vault" = 1 ]; then
                if is_in_china; then
                    [ "$basearch" = "x86_64" ] && dir= || dir=/altarch
                    mirror="https://mirrors.aliyun.com/centos-vault$dir/7.6.1810/os/$basearch/"
                else
                    [ "$basearch" = "x86_64" ] && dir=centos || dir=altarch
                    mirror=http://vault.centos.org/$dir/7.6.1810/os/$basearch/
                fi
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
            eval ${step}_ks=$confhome/$ks
        fi

        eval ${step}_distro=${distro}
        eval ${step}_vmlinuz=${mirror}images/pxeboot/vmlinuz
        eval ${step}_initrd=${mirror}images/pxeboot/initrd.img
        eval ${step}_squashfs=${mirror}images/install.img

        if [ "$releasever" = 7 ]; then
            eval ${step}_squashfs=${mirror}LiveOS/squashfs.img
        fi
    }

    if [ "$distro" = "ubuntu" ]; then
        setos_ubuntu
    else
        setos_rh
    fi
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

opts=$(getopt -a -n $0 --options l --long localtest -- "$@")
if [ "$?" != 0 ]; then
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

# 检查是否为正确的系统名
for re in \
    "s,.*\b(centos|alma|rocky)(linux)?[ :-]?([789])\b.*,\1:\3,p" \
    "s,.*\b(fedora)(linux)?[ :-]?(3[678])\b.*,\1:\3,p" \
    "s,.*\b(ubuntu)(linux)?[ :-]?(2[02]\.04)\b.*,\1:\3,p"; do

    finalos=$(echo "$@" | tr '[:upper:]' '[:lower:]' | sed -n -E "$re")
    if [ -n "$finalos" ]; then
        break
    fi
done
if [ -z "$finalos" ]; then
    echo "Please specify a proper os."
    usage_and_exit
fi

# 最小安装的 debian 不包含 curl dmidecode
install_pkg() {
    pkgs=$1
    for pkg in $pkgs; do
        if ! command -v $pkg; then
            {
                { apt update && apt install -y $pkgs; } ||
                    dnf install -y $pkgs ||
                    yum install -y $pkgs ||
                    zypper install -y $pkgs ||
                    pacman -Syu $pkgs
            } 2>/dev/null
            break
        fi
    done
}

# 获取内存大小，lsmem最准确但centos7 arm不能用
# arm 24g dmidecode 显示少了128m
ram_size=$(lsmem -b | grep 'Total online memory:' | awk '{ print $NF/1024/1024 }')
if [ -z $ram_size ]; then
    install_pkg dmidecode
    ram_size=$(dmidecode -t 17 | grep "Size.*[GM]B" | awk '{if ($3=="GB") s+=$2*1024; else s+=$2} END {print s}')
fi

if [ $ram_size -lt 1024 ]; then
    echo 'RAM < 1G. Unsupported.'
    exit 1
fi

install_pkg curl
distro=$(echo $finalos | cut -d: -f1)
releasever=$(echo $finalos | cut -d: -f2)
basearch=$(uname -m)

# 以下目标系统需要两步安装
# ubuntu
# el8/9/fedora 任何架构 <2g
# el7 aarch64 <1.5g
# shellcheck disable=SC2154
if [ $distro = "ubuntu" ] ||
    { [ $releasever -ge 8 ] && [ $ram_size -lt 2048 ]; } ||
    { [ $releasever -eq 7 ] && [ $ram_size -lt 1536 ] && [ $basearch = "aarch64" ]; }; then
    [ $distro = "ubuntu" ] && ks=user-data || ks=ks.cfg
    setos finalos $distro $releasever $ks
    setos nextos centos 7 ks-trans.cfg 1
else
    setos nextos $distro $releasever ks.cfg
fi

# 下载启动内核
# shellcheck disable=SC2154
{
    cd /
    curl -LO $nextos_vmlinuz
    curl -LO $nextos_initrd
    touch reinstall.mark
}

# 转换 finalos_a=1 为 finalos.a=1 ，排除 finalos_mirrorlist
build_finalos_cmdline() {
    for var in $(compgen -v finalos_); do
        key=${var//_/.}
        [ $key != "finalos.mirrorlist" ] && finalos_cmdline+=" $key=${!var}"
    done
}

build_extra_cmdline() {
    extra_cmdline+=" extra.confhome=$confhome"
    if [ "$localtest" = 1 ]; then
        extra_cmdline+=" extra.localtest=$localtest"
    else
        # 指定最终安装系统的 mirrorlist，链接有&，在grub中是特殊字符，所以要加引号
        if [ -n "$finalos_mirrorlist" ]; then
            extra_cmdline+=" extra.mirrorlist='$finalos_mirrorlist'"
        elif [ -n "$nextos_mirrorlist" ]; then
            extra_cmdline+=" extra.mirrorlist='$nextos_mirrorlist'"
        fi
    fi
}

# arm64 不需要添加 efi 字样
if [ -d /sys/firmware/efi ] && [ "$basearch" = x86_64 ]; then
    action='efi'
fi

build_finalos_cmdline
build_extra_cmdline
grub_cfg=$(find /boot -type f -name grub.cfg -exec grep -E -l 'menuentry|blscfg' {} \;)
grub_cfg_dir=$(dirname $grub_cfg)

custom_cfg=$grub_cfg_dir/custom.cfg
echo $custom_cfg
# shellcheck disable=SC2154
cat <<EOF | tee $custom_cfg
menuentry "reinstall" {
    insmod lvm
    insmod xfs
    search --no-floppy --file --set=root /reinstall.mark
    linux$action /vmlinuz root=live:$nextos_squashfs inst.ks=$nextos_ks $finalos_cmdline $extra_cmdline
    initrd$action /initrd.img
}
EOF

$(command -v grub-reboot grub2-reboot) reinstall
echo "Please reboot to begin the installation."

#!/bin/bash
# shellcheck disable=SC2086

set -eE
confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
github_proxy=https://mirror.ghproxy.com/https://raw.githubusercontent.com

# https://www.gnu.org/software/gettext/manual/html_node/The-LANGUAGE-variable.html
export LC_ALL=C

# 处理部分用户用 su 切换成 root 导致环境变量没 sbin 目录
# 不要漏了最后的 $PATH，否则会找不到 windows 系统程序例如 diskpart
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

this_script=$(readlink -f "$0")
trap 'trap_err $LINENO $?' ERR

trap_err() {
    line_no=$1
    ret_no=$2

    error "Line $line_no return $ret_no"
    sed -n "$line_no"p "$this_script"
}

usage_and_exit() {
    if is_in_windows; then
        reinstall____=' reinstall.bat'
    else
        reinstall____='./reinstall.sh'
    fi
    cat <<EOF
Usage: $reinstall____ centos   7|9
                      oracle   7|8|9
                      alma     8|9
                      rocky    8|9
                      fedora   39|40
                      debian   10|11|12
                      ubuntu   20.04|22.04|24.04
                      alpine   3.17|3.18|3.19|3.20
                      opensuse 15.5|15.6|tumbleweed
                      kali
                      arch
                      gentoo
                      dd       --img='http://xxx'
                      windows  --image-name='windows xxx yyy' --lang=xx-yy
                      windows  --image-name='windows xxx yyy' --iso='http://xxx'
                      netboot.xyz

Manual: https://github.com/bin456789/reinstall

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
    # centos 7 curl 不支持 --retry-connrefused --retry-all-errors
    # 因此手动 retry
    grep -o 'http[^ ]*' <<<"$@" >&2
    for i in $(seq 5); do
        if command curl --insecure --connect-timeout 10 -f "$@"; then
            return
        else
            ret=$?
            if [ $ret -eq 22 ]; then
                # 403 404 错误
                return $ret
            fi
        fi
        sleep 1
    done
}

is_in_china() {
    if [ -z $_is_in_china ]; then
        # 部分地区 www.cloudflare.com 被墙
        curl -L http://dash.cloudflare.com/cdn-cgi/trace |
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
    mount | grep -qw 'on / type btrfs'
}

is_os_in_subvol() {
    subvol=$(awk '($2=="/") { print $i }' /proc/mounts | grep -o 'subvol=[^ ]*' | cut -d= -f2)
    [ "$subvol" != / ]
}

get_os_part() {
    awk '($2=="/") { print $1 }' /proc/mounts
}

cp_to_btrfs_root() {
    mount_dir=$tmp/reinstall-btrfs-root
    if ! grep -q $mount_dir /proc/mounts; then
        mkdir -p $mount_dir
        mount "$(get_os_part)" $mount_dir -t btrfs -o subvol=/
    fi
    cp -rf "$@" $tmp/reinstall-btrfs-root
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

is_use_firmware() {
    # shellcheck disable=SC2154
    [ "$nextos_distro" = debian ] && ! is_virt
}

get_host_by_url() {
    cut -d/ -f3 <<<$1
}

get_function() {
    declare -f "$1"
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

    tmp_file=$tmp/reinstall-img-test

    # 有的服务器不支持 range，curl会下载整个文件
    # 用 dd 限制下载 1M
    # 并过滤 curl 23 错误（dd限制了空间）
    # 也可用 ulimit -f 但好像 cygwin 不支持
    echo $url
    for i in $(seq 5 -1 0); do
        if command curl --insecure --connect-timeout 10 -Lfr 0-1048575 "$url" \
            1> >(dd bs=1M count=1 of=$tmp_file iflag=fullblock 2>/dev/null) \
            2> >(grep -v 'curl: (23)' >&2); then
            break
        else
            ret=$?
            msg="$url not accessible"
            case $ret in
            22) failed "$msg" ;;                # 403 404
            23) break ;;                        # 限制了空间
            *) [ $i -eq 0 ] && failed "$msg" ;; # 其他错误
            esac
            sleep 1
        fi
    done

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
        if systemd-detect-virt -qc; then
            _error_and_exit
        fi
    else
        if [ -d /proc/vz ] || grep -q container=lxc /proc/1/environ; then
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
                if wmic $name get /format:list | grep -Eiw $vmstr; then
                    _is_virt=true
                    break
                fi
            done

            # 没有风扇和温度信息，大概是虚拟机
            if [ -z "$_is_virt" ] &&
                ! wmic /namespace:'\\root\cimv2' PATH Win32_Fan 2>/dev/null | grep -q Name &&
                ! wmic /namespace:'\\root\wmi' PATH MSAcpi_ThermalZoneTemperature 2>/dev/null | grep -q Name; then
                _is_virt=true
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

# sr-latn-rs 到 sr-latn
en_us() {
    echo "$lang" | awk -F- '{print $1"-"$2}'

    # zh-hk 可回落到 zh-tw
    if [ "$lang" = zh-hk ]; then
        echo zh-tw
    fi
}

# fr-ca 到 ca
us() {
    # 葡萄牙准确对应 pp
    if [ "$lang" = pt-pt ]; then
        echo pp
        return
    fi
    # 巴西准确对应 pt
    if [ "$lang" = pt-br ]; then
        echo pt
        return
    fi

    echo "$lang" | awk -F- '{print $2}'

    # hk 额外回落到 tw
    if [ "$lang" = zh-hk ]; then
        echo tw
    fi
}

# fr-ca 到 fr-fr
en_en() {
    echo "$lang" | awk -F- '{print $1"-"$1}'

    # en-gb 额外回落到 en-us
    if [ "$lang" = en-gb ]; then
        echo en-us
    fi
}

# fr-ca 到 fr
en() {
    # 巴西/葡萄牙回落到葡萄牙语
    if [ "$lang" = pt-br ] || [ "$lang" = pt-pt ]; then
        echo "pp"
        return
    fi

    echo "$lang" | awk -F- '{print $1}'
}

english() {
    case "$lang" in
    ar-sa) echo Arabic ;;
    bg-bg) echo Bulgarian ;;
    cs-cz) echo Czech ;;
    da-dk) echo Danish ;;
    de-de) echo German ;;
    el-gr) echo Greek ;;
    en-gb) echo Eng_Intl ;;
    en-us) echo English ;;
    es-es) echo Spanish ;;
    es-mx) echo Spanish_Latam ;;
    et-ee) echo Estonian ;;
    fi-fi) echo Finnish ;;
    fr-ca) echo FrenchCanadian ;;
    fr-fr) echo French ;;
    he-il) echo Hebrew ;;
    hr-hr) echo Croatian ;;
    hu-hu) echo Hungarian ;;
    it-it) echo Italian ;;
    ja-jp) echo Japanese ;;
    ko-kr) echo Korean ;;
    lt-lt) echo Lithuanian ;;
    lv-lv) echo Latvian ;;
    nb-no) echo Norwegian ;;
    nl-nl) echo Dutch ;;
    pl-pl) echo Polish ;;
    pt-pt) echo Portuguese ;;
    pt-br) echo Brazilian ;;
    ro-ro) echo Romanian ;;
    ru-ru) echo Russian ;;
    sk-sk) echo Slovak ;;
    sl-si) echo Slovenian ;;
    sr-latn | sr-latn-rs) echo Serbian_Latin ;;
    sv-se) echo Swedish ;;
    th-th) echo Thai ;;
    tr-tr) echo Turkish ;;
    uk-ua) echo Ukrainian ;;
    zh-cn) echo ChnSimp ;;
    zh-hk | zh-tw) echo ChnTrad ;;
    esac
}

parse_windows_image_name() {
    set -- $image_name

    if ! [ "$1" = windows ]; then
        return 1
    fi
    shift

    if [ "$1" = server ]; then
        server=server
        shift
    fi

    version=$1
    # 填写 windows longhorn serverdatacenter 时，寻找 windows server 2008 serverdatacenter iso
    if [ "$version" = longhorn ]; then
        server=server
        version=2008
    fi
    shift

    if [ "$1" = r2 ]; then
        version+=" r2"
        shift
    fi

    edition=
    for i in "$@"; do
        case "$i" in
        # windows 10 enterprise n ltsc 2021
        k | n | kn) ;;
        *)
            if [ -n "$edition" ]; then
                edition+=" "
            fi
            edition+="$1"
            ;;
        esac
        shift
    done
}

is_have_arm_version() {
    case "$version" in
    10)
        case "$edition" in
        pro | education | enterprise | 'pro education' | 'pro for workstations') return ;;
        'iot enterprise') return ;;
        'enterprise ltsc 2021' | 'iot enterprise ltsc 2021') return ;;
        esac
        ;;
    11)
        case "$edition" in
        pro | education | enterprise | 'pro education' | 'pro for workstations') return ;;
        'iot enterprise' | 'iot enterprise subscription') return ;;
        'enterprise ltsc 2024' | 'iot enterprise ltsc 2024' | 'iot enterprise ltsc 2024 subscription') return ;;
        esac
        ;;
    esac
    return 1
}

find_windows_iso() {
    parse_windows_image_name || error_and_exit "--image-name wrong: $image_name"
    if ! [ "$version" = 8.1 ] && [ -z "$edition" ]; then
        error_and_exit "Edition is not set."
    fi
    if [ "$basearch" = 'aarch64' ] && ! is_have_arm_version; then
        error_and_exit "No ARM iso for this Windows Version."
    fi

    if [ -z "$lang" ]; then
        lang=en-us
    fi
    langs="$lang $(en_us) $(us) $(en_en) $(en)"
    langs=$(echo "$langs" | xargs -n 1 | awk '!seen[$0]++')
    full_lang=$(english)

    case "$basearch" in
    x86_64) arch_win=x64 ;;
    aarch64) arch_win=arm64 ;;
    esac

    get_windows_iso_links
    get_windows_iso_link
}

get_windows_iso_links() {
    get_label_msdn() {
        if [ -n "$server" ]; then
            case "$version" in
            2008 | '2008 r2')
                case "$edition" in
                serverweb | serverwebcore) echo _ ;;
                serverstandard | serverstandardcore) echo _ ;;
                serverenterprise | serverenterprisecore) echo _ ;;
                serverdatacenter | serverdatacentercore) echo _ ;;
                esac
                ;;
            '2012 r2' | \
                2016 | 2019 | 2022 | 2025)
                case "$edition" in
                serverstandard | serverstandardcore) echo _ ;;
                serverdatacenter | serverdatacentercore) echo _ ;;
                esac
                ;;
            esac
        else
            case "$version" in
            vista)
                case "$edition" in
                starter)
                    case "$arch_win" in
                    x86) echo _ ;;
                    esac
                    ;;
                homebasic | homepremium | business | ultimate) echo _ ;;
                enterprise) echo enterprise ;;
                esac
                ;;
            7)
                case "$edition" in
                starter)
                    case "$arch_win" in
                    x86) echo ultimate ;;
                    esac
                    ;;
                professional) echo professional ;;
                homebasic | homepremium | ultimate) echo ultimate ;;
                enterprise) echo enterprise ;;
                esac
                ;;
            8.1)
                case "$edition" in
                '') echo _ ;;
                pro) echo pro ;;
                enterprise) echo enterprise ;;
                esac
                ;;
            10)
                case "$edition" in
                home | 'home single language') echo consumer ;;
                pro | education | enterprise | 'pro education' | 'pro for workstations') echo business ;;
                'iot enterprise') echo 'iot enterprise' ;;
                'enterprise 2015 ltsb' | 'enterprise 2016 ltsb' | 'enterprise ltsc 2019') echo "$edition" ;;
                'enterprise ltsc 2021')
                    # arm64 的 enterprise ltsc 2021 要下载 iot enterprise ltsc 2021 iso
                    case "$arch_win" in
                    arm64) echo 'iot enterprise ltsc 2021' ;;
                    x86 | x64) echo 'enterprise ltsc 2021' ;;
                    esac
                    ;;
                'iot enterprise ltsc 2019' | 'iot enterprise ltsc 2021') echo "$edition" ;;
                esac
                ;;
            11)
                case "$edition" in
                home | 'home single language') echo consumer ;;
                pro | education | enterprise | 'pro education' | 'pro for workstations') echo business ;;
                'iot enterprise' | 'iot enterprise subscription') echo 'iot enterprise' ;;
                'enterprise ltsc 2024') echo 'enterprise ltsc 2024' ;;
                'iot enterprise ltsc 2024' | 'iot enterprise ltsc 2024 subscription') echo 'iot enterprise ltsc 2024' ;;
                esac
                ;;
            esac
        fi
    }

    get_label_vlsc() {
        case "$version" in
        10 | 11)
            case "$edition" in
            pro | education | enterprise | 'pro education' | 'pro for workstations') echo pro ;;
            esac
            ;;
        esac
    }

    get_page() {
        if [ "$arch_win" = arm64 ]; then
            echo arm
        elif is_ltsc; then
            echo ltsc
        elif [ "$server" = 'server' ]; then
            echo server
        else
            case "$version" in
            vista | 7 | 8.1 | 10 | 11)
                echo "$version"
                ;;
            esac
        fi
    }

    is_ltsc() {
        grep -Ewq 'ltsb|ltsc' <<<"$edition"
    }

    # 部分 bash 不支持 $() 里面嵌套case，所以定义成函数
    label_msdn=$(get_label_msdn)
    label_vlsc=$(get_label_vlsc)
    page=$(get_page)

    page_url=https://massgrave.dev/windows_${page}_links.html

    info "Find windows iso"
    echo "Version:    $version"
    echo "Edition:    $edition"
    echo "Label msdn: $label_msdn"
    echo "Label vlsc: $label_vlsc"
    echo "List:       $page_url"
    echo

    if [ -z "$page" ] || { [ -z "$label_msdn" ] && [ -z "$label_vlsc" ]; }; then
        error_and_exit "Not support find this iso. Check --image-name or set --iso manually."
    fi

    curl -L "$page_url" | grep -ioP 'https://.*?.iso' >$tmp/win.list

    # 如果不是 ltsc ，应该先去除 ltsc 链接，否则最终链接有 ltsc 的
    # 例如查找 windows 10 iot enterprise，会得到
    # en-us_windows_10_iot_enterprise_ltsc_2021_arm64_dvd_e8d4fc46.iso
    # en-us_windows_10_iot_enterprise_version_22h2_arm64_dvd_39566b6b.iso
    # sed -Ei 和 sed -iE 是不同的
    if is_ltsc; then
        sed -Ei '/ltsc|ltsb/!d' $tmp/win.list
    else
        sed -Ei '/ltsc|ltsb/d' $tmp/win.list
    fi
}

get_shortest_line() {
    # awk '{print length($0), $0}' | sort -n | head -1 | awk '{print $2}'
    awk '(NR == 1 || length($0) < length(shortest)) { shortest = $0 } END { print shortest }'
}

get_windows_iso_link() {
    regexs=()

    # msdn
    if [ -n "$label_msdn" ]; then
        if [ "$label_msdn" = _ ]; then
            label_msdn=
        fi
        for lang in $langs; do
            regex=
            for i in ${lang} windows ${server} ${version} ${label_msdn}; do
                if [ -n "$i" ]; then
                    regex+="${i}_"
                fi
            done
            regex+=".*${arch_win}.*.iso"
            regexs+=("$regex")
        done
    fi

    # vlsc
    if [ -n "$label_vlsc" ]; then
        regex="sw_dvd9_win_${label_vlsc}_${version}.*${arch_win}_${full_lang}.*.iso"
        regexs+=("$regex")
    fi

    # 查找
    for regex in "${regexs[@]}"; do
        regex=${regex// /_}

        echo "looking for: $regex" >&2
        if iso=$(grep -Ei "/$regex" "$tmp/win.list" | get_shortest_line | grep .); then
            return
        fi
    done

    error_and_exit "Could not find windows iso."
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

        # alpine aarch64 3.16/3.17 virt 没有直连链接
        if [ "$basearch" = aarch64 ] &&
            { [ "$releasever" = 3.16 ] || [ "$releasever" = 3.17 ]; }; then
            flavour=lts
        fi

        # 不要用https 因为甲骨文云arm initramfs阶段不会从硬件同步时钟，导致访问https出错
        if is_in_china; then
            mirror=http://mirrors.ustc.edu.cn/alpine/v$releasever
        else
            mirror=http://dl-cdn.alpinelinux.org/alpine/v$releasever
        fi
        eval ${step}_vmlinuz=$mirror/releases/$basearch/netboot/vmlinuz-$flavour
        eval ${step}_initrd=$mirror/releases/$basearch/netboot/initramfs-$flavour
        eval ${step}_modloop=$mirror/releases/$basearch/netboot/modloop-$flavour
        eval ${step}_repo=$mirror/main
    }

    setos_debian() {
        case "$releasever" in
        10) codename=buster ;;
        11) codename=bullseye ;;
        12) codename=bookworm ;;
        esac

        if is_in_china; then
            cdimage_mirror=https://mirrors.ustc.edu.cn/debian-cdimage
        else
            cdimage_mirror=https://cdimage.debian.org/images # 在瑞典，不是 cdn
            # cloud.debian.org 同样在瑞典，不是 cdn
        fi

        if is_use_cloud_image; then
            # cloud image
            is_virt && ci_type=genericcloud || ci_type=generic
            # 甲骨文 debian 10 amd64 genericcloud vnc 没有显示
            # 甲骨文 debian 10 arm64 没有 genericcloud 镜像
            [ "$releasever" -eq 10 ] && ci_type=generic
            eval ${step}_img=$cdimage_mirror/cloud/$codename/latest/debian-$releasever-$ci_type-$basearch_alt.qcow2
        else
            # 传统安装
            if is_in_china; then
                # ftp.cn.debian.org 不在国内还严重丢包
                # https://www.itdog.cn/ping/ftp.cn.debian.org
                deb_hostname=mirrors.ustc.edu.cn
            else
                deb_hostname=deb.debian.org # fastly
            fi
            mirror=http://$deb_hostname/debian/dists/$codename/main/installer-$basearch_alt/current/images/netboot/debian-installer/$basearch_alt

            is_virt && flavour=-cloud || flavour=
            # 甲骨文 debian 10 amd64 cloud 内核 vnc 没有显示
            [ "$releasever" -eq 10 ] && [ "$basearch_alt" = amd64 ] && flavour=
            # 甲骨文 arm64 cloud 内核 vnc 没有显示
            [ "$basearch_alt" = arm64 ] && flavour=

            eval ${step}_vmlinuz=$mirror/linux
            eval ${step}_initrd=$mirror/initrd.gz
            eval ${step}_ks=$confhome/debian.cfg
            eval ${step}_firmware=$cdimage_mirror/firmware/$codename/current/firmware.cpio.gz
            eval ${step}_deb_hostname=$deb_hostname
            eval ${step}_codename=$codename
            eval ${step}_kernel=linux-image$flavour-$basearch_alt
        fi
    }

    setos_kali() {
        if is_use_cloud_image; then
            :
        else
            # 传统安装
            if is_in_china; then
                deb_hostname=mirrors.ustc.edu.cn
            else
                # http.kali.org 没有 ipv6 地址
                # http.kali.org (geoip 重定向) 到 kali.download (cf)
                deb_hostname=kali.download
            fi
            codename=kali-rolling
            mirror=http://$deb_hostname/kali/dists/$codename/main/installer-$basearch_alt/current/images/netboot/debian-installer/$basearch_alt

            is_virt && flavour=-cloud || flavour=

            eval ${step}_vmlinuz=$mirror/linux
            eval ${step}_initrd=$mirror/initrd.gz
            eval ${step}_ks=$confhome/debian.cfg
            eval ${step}_deb_hostname=$deb_hostname
            eval ${step}_codename=$codename
            eval ${step}_kernel=linux-image$flavour-$basearch_alt
            # 缺少 firmware 下载
        fi
    }

    setos_ubuntu() {
        case "$releasever" in
        20.04) codename=focal ;;
        22.04) codename=jammy ;;
        24.04) codename=noble ;;
        esac

        if is_use_cloud_image; then
            # cloud image
            if is_in_china; then
                # 有的源没有 releases 镜像
                # https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/releases/
                #   https://unicom.mirrors.ustc.edu.cn/ubuntu-cloud-images/releases/
                #            https://mirror.nju.edu.cn/ubuntu-cloud-images/releases/

                # mirrors.cloud.tencent.com
                ci_mirror=https://mirror.nju.edu.cn/ubuntu-cloud-images
            else
                ci_mirror=https://cloud-images.ubuntu.com
            fi
            # 20.04/22.04 minimal 镜像没有 aarch64
            if { { [ "$releasever" = 20.04 ] || [ "$releasever" = 22.04 ]; } && [ "$basearch_alt" = amd64 ]; } ||
                [ "$releasever" = 24.04 ]; then
                eval ${step}_img=$ci_mirror/minimal/releases/$codename/release/ubuntu-$releasever-minimal-cloudimg-$basearch_alt.img
            else
                eval ${step}_img=$ci_mirror/releases/$releasever/release/ubuntu-$releasever-server-cloudimg-$basearch_alt.img
            fi
        else
            # 传统安装
            if is_in_china; then
                case "$basearch" in
                "x86_64") mirror=https://mirrors.ustc.edu.cn/ubuntu-releases/$releasever ;;
                "aarch64") mirror=https://mirrors.ustc.edu.cn/ubuntu-cdimage/releases/$releasever/release ;;
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
        if [ "$basearch" = "x86_64" ]; then
            if is_in_china; then
                mirror=https://mirrors.ustc.edu.cn/archlinux
            else
                mirror=https://geo.mirror.pkgbuild.com # geoip
            fi
        else
            if is_in_china; then
                mirror=https://mirrors.ustc.edu.cn/archlinuxarm
            else
                # https 证书有问题
                mirror=http://mirror.archlinuxarm.org # geoip
            fi
        fi

        if is_use_cloud_image; then
            # cloud image
            eval ${step}_img=$mirror/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
        else
            # 传统安装
            case "$basearch" in
            x86_64) dir="core/os/$basearch" ;;
            aarch64) dir="$basearch/core" ;;
            esac
            test_url $mirror/$dir/core.db gzip
            eval ${step}_mirror=$mirror
        fi
    }

    setos_gentoo() {
        if is_in_china; then
            mirror=https://mirrors.ustc.edu.cn/gentoo
        else
            mirror=https://distfiles.gentoo.org # cdn77
        fi

        if is_use_cloud_image; then
            if [ "$basearch_alt" = arm64 ]; then
                error_and_exit 'Not support arm64 for gentoo cloud image.'
            fi

            # openrc 镜像没有附带兼容 cloud-init 的网络管理器
            eval ${step}_img=$mirror/experimental/$basearch_alt/openstack/gentoo-openstack-$basearch_alt-systemd-latest.qcow2
        else
            prefix=stage3-$basearch_alt-systemd
            dir=releases/$basearch_alt/autobuilds/current-$prefix
            file=$(curl -L $mirror/$dir/latest-$prefix.txt | grep '.tar.xz' | awk '{print $1}')
            stage3=$mirror/$dir/$file
            test_url $stage3 'xz'
            eval ${step}_img=$stage3
        fi
    }

    setos_opensuse() {
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
        if [ -z "$iso" ]; then
            echo "iso url is not set. Try to find it."
            find_windows_iso
        fi

        # 防呆设计
        # 将 windows server 2008 改成 windows longhorn
        if ! echo "$image_name" | grep -q r2; then
            image_name=${image_name/server 2008/longhorn}
        fi

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
                "9") ci_image=$ci_mirror/$releasever-stream/$basearch/images/CentOS-Stream-GenericCloud-$releasever-latest.$basearch.qcow2 ;;
                esac
                ;;
            "alma") ci_image=$ci_mirror/AlmaLinux-$releasever-GenericCloud-latest.$basearch.qcow2 ;;
            "rocky") ci_image=$ci_mirror/Rocky-$releasever-GenericCloud-Base.latest.$basearch.qcow2 ;;
            "fedora")
                # Fedora-Cloud-Base-39-1.5.x86_64.qcow2
                # Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2
                page=$(curl -L $ci_mirror)
                # 40
                filename=$(grep -oP "Fedora-Cloud-Base-Generic.*?.qcow2" <<<"$page" | head -1)
                # 38/39
                if [ -z "$filename" ]; then
                    filename=$(grep -oP "Fedora-Cloud-Base-$releasever.*?.qcow2" <<<"$page" | head -1)
                fi
                ci_image=$ci_mirror/$filename
                ;;
            esac

            eval ${step}_img=${ci_image}
        else
            # 传统安装
            case $distro in
            "centos")
                case $releasever in
                "7") mirrorlist="http://mirrorlist.centos.org/?release=7&arch=$basearch&repo=os" ;;
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

    setos_oracle() {
        if is_use_cloud_image; then
            # ci
            install_pkg jq
            mirror=https://yum.oracle.com

            [ "$basearch" = aarch64 ] &&
                template_prefix=ol${releasever}_${basearch}-cloud ||
                template_prefix=ol${releasever}
            curl -Lo $tmp/oracle.json $mirror/templates/OracleLinux/$template_prefix-template.json
            dir=$(jq -r .base_url $tmp/oracle.json)
            file=$(jq -r .kvm.image $tmp/oracle.json)
            ci_image=$mirror$dir/$file

            eval ${step}_img=${ci_image}
        else
            :
        fi
    }

    eval ${step}_distro=$distro
    eval ${step}_releasever=$releasever

    if is_distro_like_redhat && ! [ "$distro" = oracle ]; then
        setos_redhat
    else
        setos_$distro
    fi

    # debian/kali <=256M 必须使用云内核，否则不够内存
    if is_distro_like_debian && ! is_in_windows && [ "$ram_size" -le 256 ]; then
        exit_if_cant_use_cloud_kernel
    fi

    # 集中测试云镜像格式
    if is_use_cloud_image && [ "$step" = finalos ]; then
        # shellcheck disable=SC2154
        test_url $finalos_img 'xz|gzip|qemu' finalos_img_type
    fi
}

is_distro_like_redhat() {
    if [ -n "$1" ]; then
        _distro=$1
    else
        _distro=$distro
    fi
    [ "$_distro" = centos ] || [ "$_distro" = alma ] || [ "$_distro" = rocky ] || [ "$_distro" = fedora ] || [ "$_distro" = oracle ]
}

is_distro_like_debian() {
    if [ -n "$1" ]; then
        _distro=$1
    else
        _distro=$distro
    fi
    [ "$_distro" = debian ] || [ "$_distro" = kali ]
}

# 检查是否为正确的系统名
verify_os_name() {
    if [ -z "$*" ]; then
        usage_and_exit
    fi

    for os in \
        'centos   7|9' \
        'oracle   7|8|9' \
        'alma     8|9' \
        'rocky    8|9' \
        'fedora   39|40' \
        'debian   10|11|12' \
        'ubuntu   20.04|22.04|24.04' \
        'alpine   3.17|3.18|3.19|3.20' \
        'opensuse 15.5|15.6|tumbleweed' \
        'kali' \
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
        if [ -z "$image_name" ]; then
            error_and_exit "Install Windows need --image-name."
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
        ar)
            case "$pkg_mgr" in
            *) pkg="binutils" ;;
            esac
            ;;
        xz)
            case "$pkg_mgr" in
            apt) pkg="xz-utils" ;;
            *) pkg="xz" ;;
            esac
            ;;
        lsblk | findmnt)
            case "$pkg_mgr" in
            apk) pkg="$cmd" ;;
            *) pkg="util-linux" ;;
            esac
            ;;
        lsmem)
            case "$pkg_mgr" in
            apk) pkg="util-linux-misc" ;;
            *) pkg="util-linux" ;;
            esac
            ;;
        fdisk)
            case "$pkg_mgr" in
            apt) pkg="fdisk" ;;
            apk) pkg="util-linux-misc" ;;
            *) pkg="util-linux" ;;
            esac
            ;;
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

    is_need_epel_repo() {
        case "$pkg" in
        dpkg) [ "$pkg_mgr" = yum ] || [ "$pkg_mgr" = dnf ] ;;
        jq) [ "$pkg_mgr" = yum ] ;; # el7/ol7
        *) false ;;
        esac
    }

    add_epel_repo() {
        # epel 名称可能是 epel 或 ol9_developer_EPEL
        # 如果没启用
        if ! $pkg_mgr repolist | awk '{print $1}' | grep -qi 'epel$'; then
            #  删除 epel repo，因为可能安装了但未启用
            rm -rf /etc/yum.repos.d/*epel*.repo
            epel_release="$($pkg_mgr list | grep 'epel-release' | awk '{print $1}' | cut -d. -f1 | head -1)"

            # 如果已安装
            if rpm -qa | grep -q $epel_release; then
                # 检查是否为最新
                if $pkg_mgr check-update $epel_release; then
                    $pkg_mgr reinstall -y $epel_release
                else
                    $pkg_mgr update -y $epel_release
                fi
            else
                # 如果未安装
                $pkg_mgr install -y $epel_release
            fi
        fi
    }

    install_pkg_real() {
        text="$pkg"
        if [ "$pkg" != "$cmd" ]; then
            text+=" ($cmd)"
        fi
        echo "Installing package '$text'..."

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
            [ -z "$apt_updated" ] && apt update && apt_updated=1
            DEBIAN_FRONTEND=noninteractive apt install -y $pkg
            ;;
        esac
    }

    is_need_reinstall() {
        cmd=$1

        # gentoo 默认编译的 unsquashfs 不支持 xz
        if [ "$cmd" = unsquashfs ] && is_have_cmd emerge && ! $cmd |& grep -wq xz; then
            echo "unsquashfs not supported xz. rebuilding."
            return 0
        fi

        # busybox fdisk 无法显示 mbr 分区表的 id
        if [ "$cmd" = fdisk ] && is_have_cmd apk && $cmd |& grep -wq BusyBox; then
            return 0
        fi

        # busybox grep 无法 grep -oP
        if [ "$cmd" = grep ] && is_have_cmd apk && $cmd |& grep -wq BusyBox; then
            return 0
        fi

        return 1
    }

    for cmd in "$@"; do
        if ! is_have_cmd $cmd || is_need_reinstall $cmd; then
            if ! find_pkg_mgr; then
                error_and_exit "Can't find compatible package manager. Please manually install $cmd."
            fi
            cmd_to_pkg
            if is_need_epel_repo; then
                add_epel_repo
            fi
            install_pkg_real
        fi
    done
}

check_ram() {
    ram_standard=$(
        case "$distro" in
        netboot.xyz) echo 0 ;;
        alpine | debian | kali | dd) echo 256 ;;
        arch | gentoo | windows) echo 512 ;;
        centos | alma | rocky | fedora | oracle | ubuntu) echo 1024 ;;
        opensuse) echo -1 ;; # 没有安装模式
        esac
    )

    # 不用检查内存的情况
    if [ "$ram_standard" -eq 0 ]; then
        return
    fi

    # 未测试
    ram_cloud_image=256

    has_cloud_image=$(
        case "$distro" in
        centos | alma | rocky | oracle | fedora | debian | ubuntu | opensuse) echo true ;;
        netboot.xyz | alpine | dd | arch | gentoo | kali | windows) echo false ;;
        esac
    )

    if is_in_windows; then
        ram_size=$(wmic memorychip get capacity | tail +2 | awk '{sum+=$1} END {print sum/1024/1024}')
    else
        # lsmem最准确但 centos7 arm 和 alpine 不能用，debian 9 util-linux 没有 lsmem
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

    # ram 足够就用普通方法安装，否则如果内存大于512就用 cloud image
    # TODO: 测试 256 384 内存
    if ! is_use_cloud_image && [ $ram_size -lt $ram_standard ]; then
        if $has_cloud_image; then
            info "RAM < $ram_standard MB. Fallback to cloud image mode"
            cloud_image=1
        else
            error_and_exit "Could not install $distro: RAM < $ram_standard MB."
        fi
    fi

    if is_use_cloud_image && [ $ram_size -lt $ram_cloud_image ]; then
        error_and_exit "Could not install $distro using cloud image: RAM < $ram_cloud_image MB."
    fi
}

is_efi() {
    if is_in_windows; then
        # bcdedit | grep -qi '^path.*\.efi'
        mountvol | grep -q --text 'EFI'
    else
        [ -d /sys/firmware/efi ]
    fi
}

is_grub_dir_linked() {
    # cloudcone 重装前/重装后(方法1)
    [ "$(readlink -f /boot/grub/grub.cfg)" = /boot/grub2/grub.cfg ] ||
        [ "$(readlink -f /boot/grub2/grub.cfg)" = /boot/grub/grub.cfg ] ||
        # cloudcone 重装后(方法2)
        { [ -f /boot/grub2/grub.cfg ] && [ "$(cat /boot/grub2/grub.cfg)" = 'chainloader (hd0)+1' ]; }
}

is_secure_boot_enabled() {
    if is_efi; then
        if is_in_windows; then
            reg query 'HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State' /v UEFISecureBootEnabled 2>/dev/null | grep 0x1
        else
            # localhost:~# mokutil --sb-state
            # SecureBoot disabled
            # Platform is in Setup Mode
            dmesg | grep -i 'Secure boot enabled'
        fi
    else
        return 1
    fi
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

del_empty_lines() {
    sed '/^[[:space:]]*$/d'
}

# 记录主硬盘
find_main_disk() {
    if [ -n "$main_disk" ]; then
        return
    fi

    if is_in_windows; then
        # TODO:
        # 已测试 vista
        # 测试 软raid
        # 测试 动态磁盘

        # diskpart 命令结果
        # 磁盘 ID: E5FDE61C
        # 磁盘 ID: {92CF6564-9B2E-4348-A3BD-D84E3507EBD7}
        main_disk=$(printf "%s\n%s" "select volume $c" "uniqueid disk" | diskpart |
            tail -1 | awk '{print $NF}' | sed 's,[{}],,g' | del_cr)
    else
        # centos7下测试     lsblk --inverse $mapper | grep -w disk     grub2-probe -t disk /
        # 跨硬盘btrfs       只显示第一个硬盘                            显示两个硬盘
        # 跨硬盘lvm         显示两个硬盘                                显示/dev/mapper/centos-root
        # 跨硬盘软raid      显示两个硬盘                                显示/dev/md127

        # 还有 findmnt

        # 改成先检测 /boot/efi /efi /boot 分区？

        install_pkg lsblk
        # 查找主硬盘时，优先查找 /boot 分区，再查找 / 分区
        # lvm 显示的是 /dev/mapper/xxx-yyy，再用第二条命令得到sda
        mapper=$(mount | awk '$3=="/boot" {print $1}' | grep . || mount | awk '$3=="/" {print $1}')
        xda=$(lsblk -rn --inverse $mapper | grep -w disk | awk '{print $1}' | sort -u)

        # 检测主硬盘是否横跨多个磁盘
        os_across_disks_count=$(wc -l <<<"$xda")
        if [ $os_across_disks_count -eq 1 ]; then
            info "Main disk: $xda"
        else
            error_and_exit "OS across $os_across_disks_count disk: $xda"
        fi

        # 可以用 dd 找出 guid?

        # centos7 blkid lsblk 不显示 PTUUID
        # centos7 sfdisk 不显示 Disk identifier
        # alpine blkid 不显示 gpt 分区表的 PTUUID
        # 因此用 fdisk

        # Disk identifier: 0x36778223                                  # gnu fdisk + mbr
        # Disk identifier: D6B17C1A-FA1E-40A1-BDCB-0278A3ED9CFC        # gnu fdisk + gpt
        # Disk identifier (GUID): d6b17c1a-fa1e-40a1-bdcb-0278a3ed9cfc # busybox fdisk + gpt
        # 不显示 Disk identifier                                        # busybox fdisk + mbr

        # 获取 xda 的 id
        install_pkg fdisk
        main_disk=$(fdisk -l /dev/$xda | grep 'Disk identifier' | awk '{print $NF}' | sed 's/0x//')
    fi

    # 检查 id 格式是否正确
    if ! grep -Eix '[0-9a-f]{8}' <<<"$main_disk" &&
        ! grep -Eix '[0-9a-f-]{36}' <<<"$main_disk"; then
        error_and_exit "Disk ID is invalid: $main_disk"
    fi
}

is_found_ipv4_netconf() {
    [ -n "$ipv4_mac" ] && [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ]
}

is_found_ipv6_netconf() {
    [ -n "$ipv6_mac" ] && [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ]
}

# TODO: 单网卡多IP
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

        # wmic nic:
        # 真实网卡
        # AdapterType=以太网 802.3
        # AdapterTypeId=0
        # MACAddress=68:EC:C5:11:11:11
        # PhysicalAdapter=TRUE
        # PNPDeviceID=PCI\VEN_8086&amp;DEV_095A&amp;SUBSYS_94108086&amp;REV_61\4&amp;295A4BD&amp;1&amp;00E0

        # VPN tun 网卡，部分移动云电脑也有
        # AdapterType=
        # AdapterTypeId=
        # MACAddress=
        # PhysicalAdapter=TRUE
        # PNPDeviceID=SWD\WINTUN\{6A460D48-FB76-6C3F-A47D-EF97D3DC6B0E}

        # VMware 网卡
        # AdapterType=以太网 802.3
        # AdapterTypeId=0
        # MACAddress=00:50:56:C0:00:08
        # PhysicalAdapter=TRUE
        # PNPDeviceID=ROOT\VMWARE\0001

        for v in 4 6; do
            if [ "$v" = 4 ]; then
                # 或者 route print
                routes=$(netsh int ipv4 show route | awk '$4 == "0.0.0.0/0"' | del_cr)
            else
                routes=$(netsh int ipv6 show route | awk '$4 == "::/0"' | del_cr)
            fi

            if [ -z "$routes" ]; then
                continue
            fi

            while read -r route; do
                if false; then
                    read -r _ _ _ _ id gateway <<<"$route"
                else
                    id=$(awk '{print $5}' <<<"$route")
                    gateway=$(awk '{print $6}' <<<"$route")
                fi

                config=$(wmic nicconfig where InterfaceIndex=$id get MACAddress,IPAddress,IPSubnet,DefaultIPGateway /format:list | del_cr)
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
                if [ "$v" = 4 ]; then
                    for ((i = 0; i < ${#ips[@]}; i++)); do
                        ip=${ips[i]}
                        subnet=${subnets[i]}
                        if [[ "$ip" = *.* ]]; then
                            cidr=$(ipcalc -b "$ip/$subnet" | grep Netmask: | awk '{print $NF}')
                            ipv4_addr="$ip/$cidr"
                            ipv4_gateway="$gateway"
                            ipv4_mac="$mac_addr"
                            # 只取第一个 IP
                            break
                        fi
                    done
                fi

                # IPv6
                if [ "$v" = 6 ]; then
                    ipv6_type_list=$(netsh interface ipv6 show address $id normal)
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
                                ipv6_gateway="$gateway"
                                ipv6_mac="$mac_addr"
                                # 只取第一个 IP
                                break
                            fi
                        fi
                    done
                fi

                # 网关
                # shellcheck disable=SC2154
                if false; then
                    for gateway in "${gateways[@]}"; do
                        if [ -n "$ipv4_addr" ] && [[ "$gateway" = *.* ]]; then
                            ipv4_gateway="$gateway"
                        elif [ -n "$ipv6_addr" ] && [[ "$gateway" = *:* ]]; then
                            ipv6_gateway="$gateway"
                        fi
                    done
                fi

                # 如果通过本条 route 的网卡找到了 IP 则退出 routes 循环
                if is_found_ipv${v}_netconf; then
                    break
                fi
            done < <(echo "$routes")
        done
    else
        # linux
        # 通过默认网关得到默认网卡

        # 多个默认路由下
        # ip -6 route show default dev ens3 完全不显示

        # ip -6 route show default
        # default proto static metric 1024 pref medium
        #         nexthop via 2a01:1111:262:4940::2 dev ens3 weight 1 onlink
        #         nexthop via fe80::5054:ff:fed4:5286 dev ens3 weight 1

        # ip -6 route show default
        # default via 2602:1111:0:80::1 dev eth0 metric 1024 onlink pref medium

        for v in 4 6; do
            if ethx=$(ip -$v route show default | awk '$4=="dev"' | head -1 | awk '{print $5}' | grep .); then
                if ip -$v route show default | awk '$5=="'$ethx'"' | head -1 | grep -q .; then
                    eval ipv${v}_ethx="$ethx" # can_use_cloud_kernel 要用
                    eval ipv${v}_mac="$(ip link show dev $ethx | grep link/ether | head -1 | awk '{print $2}')"
                    eval ipv${v}_gateway="$(ip -$v route show default | awk '$5=="'$ethx'"' | head -1 | awk '{print $3}')"
                    eval ipv${v}_addr="$(ip -$v -o addr show scope global dev $ethx | head -1 | awk '{print $4}')"
                fi
            fi
        done
    fi

    if ! is_found_ipv4_netconf && ! is_found_ipv6_netconf; then
        error_and_exit "Can not get IP info."
    fi

    info "Network Info"
    echo "IPv4 MAC: $ipv4_mac"
    echo "IPv4 Address: $ipv4_addr"
    echo "IPv4 Gateway: $ipv4_gateway"
    echo "---"
    echo "IPv6 MAC: $ipv6_mac"
    echo "IPv6 Address: $ipv6_addr"
    echo "IPv6 Gateway: $ipv6_gateway"
    echo
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
    mount | awk '$5=="vfat" || $5=="autofs" {print $3}' | grep -E '/boot|/efi' | sort -u
}

get_disk_by_part() {
    dev_part=$1
    install_pkg lsblk >&2
    lsblk -rn --inverse "$dev_part" | grep -w disk | awk '{print $1}'
}

get_part_num_by_part() {
    dev_part=$1
    grep -oE '[0-9]*$' <<<"$dev_part"
}

grep_efi_index() {
    awk -F '*' '{print $1}' | sed 's/Boot//'
}

add_efi_entry_in_linux() {
    source=$1

    install_pkg efibootmgr

    for efi_part in $(get_maybe_efi_dirs_in_linux); do
        if find $efi_part -iname "*.efi" >/dev/null; then
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

    # fedora 39 的 efi 无法识别 opensuse tumbleweed 的 xfs
    efi_distro=opensuse

    # 不要用 download.opensuse.org 和 download.fedoraproject.org
    # 因为 ipv6 访问有时跳转到 ipv4 地址，造成 ipv6 only 机器无法下载
    # 日韩机器有时得到国内镜像源，但镜像源屏蔽了国外 IP 导致连不上
    # https://mirrors.bfsu.edu.cn/opensuse/ports/aarch64/tumbleweed/repo/oss/EFI/BOOT/grub.efi
    if [ "$efi_distro" = fedora ]; then
        fedora_ver=40

        if is_in_china; then
            mirror=https://mirrors.ustc.edu.cn/fedora
        else
            mirror=https://mirror.fcix.net/fedora/linux
        fi

        curl -Lo $tmp/$grub_efi $mirror/releases/$fedora_ver/Everything/$basearch/os/EFI/BOOT/$grub_efi
    else
        if is_in_china; then
            mirror=https://mirror.sjtu.edu.cn/opensuse
        else
            mirror=https://mirror.fcix.net/opensuse
        fi

        [ "$basearch" = x86_64 ] && ports='' || ports=/ports/$basearch

        curl -Lo $tmp/$grub_efi $mirror$ports/tumbleweed/repo/oss/EFI/BOOT/grub.efi
    fi

    add_efi_entry_in_linux $tmp/$grub_efi
}

install_grub_win() {
    # 下载 grub
    info download grub
    grub_ver=2.06
    # ftpmirror.gnu.org 是 geoip 重定向，不是 cdn
    # 有可能重定义到一个拉黑了部分 IP 的服务器
    is_in_china && grub_url=https://mirrors.ustc.edu.cn/gnu/grub/grub-$grub_ver-for-windows.zip ||
        grub_url=https://ftpmirror.gnu.org/gnu/grub/grub-$grub_ver-for-windows.zip
    curl -Lo $tmp/grub.zip $grub_url
    # unzip -qo $tmp/grub.zip
    7z x $tmp/grub.zip -o$tmp -r -y -xr!i386-efi -xr!locale -xr!themes -bso0
    grub_dir=$tmp/grub-$grub_ver-for-windows
    grub=$grub_dir/grub

    # 设置 grub 包含的模块
    # 原系统是 windows，因此不需要 ext2 lvm xfs btrfs
    grub_modules+=" normal minicmd serial ls echo test cat reboot halt linux chain search all_video configfile"
    grub_modules+=" scsi part_msdos part_gpt fat ntfs ntfscomp lzopio xzio gzio zstd"
    if ! is_efi; then
        grub_modules+=" biosdisk linux16"
    fi

    # 设置 grub prefix 为c盘根目录
    # 运行 grub-probe 会改变cmd窗口字体
    prefix=$($grub-probe -t drive $c: | sed 's|.*PhysicalDrive|(hd|' | del_cr)/
    echo $prefix

    # 安装 grub
    if is_efi; then
        # efi
        info install grub for efi
        if [ "$basearch" = aarch64 ]; then
            # 3.20 是 grub 2.12，可能会有问题
            alpine_ver=3.19
            is_in_china && mirror=http://mirrors.ustc.edu.cn/alpine || mirror=https://dl-cdn.alpinelinux.org/alpine
            grub_efi_apk=$(curl -L $mirror/v$alpine_ver/main/aarch64/ | grep -oP 'grub-efi-.*?apk' | head -1)
            mkdir -p $tmp/grub-efi
            curl -L "$mirror/v$alpine_ver/main/aarch64/$grub_efi_apk" | tar xz --warning=no-unknown-keyword -C $tmp/grub-efi/
            cp -r $tmp/grub-efi/usr/lib/grub/arm64-efi/ $grub_dir
            $grub-mkimage -p $prefix -O arm64-efi -o "$(cygpath -w $grub_dir/grubaa64.efi)" $grub_modules
            add_efi_entry_in_windows $grub_dir/grubaa64.efi
        else
            $grub-mkimage -p $prefix -O x86_64-efi -o "$(cygpath -w $grub_dir/grubx64.efi)" $grub_modules
            add_efi_entry_in_windows $grub_dir/grubx64.efi
        fi
    else
        # bios
        info install grub for bios

        # bootmgr 加载 g2ldr 有大小限制
        # 超过大小会报错 0xc000007b
        # 解决方法1 g2ldr.mbr + g2ldr
        # 解决方法2 生成少于64K的 g2ldr + 动态模块
        if false; then
            # g2ldr.mbr
            # 部分国内机无法访问 ftp.cn.debian.org
            is_in_china && host=mirrors.ustc.edu.cn || host=deb.debian.org
            curl -LO http://$host/debian/tools/win32-loader/stable/win32-loader.exe
            7z x win32-loader.exe 'g2ldr.mbr' -o$tmp/win32-loader -r -y -bso0
            find $tmp/win32-loader -name 'g2ldr.mbr' -exec cp {} /cygdrive/$c/ \;

            # g2ldr
            # 配置文件 c:\grub.cfg
            $grub-mkimage -p "$prefix" -O i386-pc -o "$(cygpath -w $grub_dir/core.img)" $grub_modules
            cat $grub_dir/i386-pc/lnxboot.img $grub_dir/core.img >/cygdrive/$c/g2ldr
        else
            # grub-install 无法设置 prefix
            # 配置文件 c:\grub\grub.cfg
            $grub-install $c \
                --target=i386-pc \
                --boot-directory=$c: \
                --install-modules="$grub_modules" \
                --themes= \
                --fonts= \
                --no-bootsector

            cat $grub_dir/i386-pc/lnxboot.img /cygdrive/$c/grub/i386-pc/core.img >/cygdrive/$c/g2ldr
        fi

        # 添加引导
        # 脚本可能不是首次运行，所以先删除原来的
        id='{1c41f649-1637-52f1-aea8-f96bfebeecc8}'
        bcdedit /enum all | grep --text $id && bcdedit /delete $id
        bcdedit /create $id /d "$(get_entry_name)" /application bootsector
        bcdedit /set $id device partition=$c:
        bcdedit /set $id path \\g2ldr
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
    for key in confhome hold cloud_image main_disk; do
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

    # cloudcone 特殊处理
    if is_grub_dir_linked; then
        finalos_cmdline+=" extra.link_grub_dir=1"
    fi
}

echo_tmp_ttys() {
    curl -L $confhome/ttys.sh | sh -s "console="
}

get_entry_name() {
    printf 'reinstall ('
    printf '%s' "$distro"
    [ -n "$releasever" ] && printf ' %s' "$releasever"
    [ "$distro" = alpine ] && [ "$hold" = 1 ] && printf ' Live OS'
    printf ')'
}

# shellcheck disable=SC2154
build_nextos_cmdline() {
    if [ $nextos_distro = alpine ]; then
        nextos_cmdline="alpine_repo=$nextos_repo modloop=$nextos_modloop"
    elif is_distro_like_debian $nextos_distro; then
        nextos_cmdline="lowmem/low=1 auto=true priority=critical"
        nextos_cmdline+=" url=$nextos_ks"
        nextos_cmdline+=" mirror/http/hostname=$nextos_deb_hostname"
        nextos_cmdline+=" mirror/http/directory=/$nextos_distro"
        nextos_cmdline+=" base-installer/kernel/image=$nextos_kernel"
        # kali 安装好后网卡是 eth0 这种格式，但安装时不是
        if [ "$nextos_distro" = kali ]; then
            nextos_cmdline+=" net.ifnames=0"
            nextos_cmdline+=" simple-cdd/profiles=kali"
        fi
    elif is_distro_like_redhat $nextos_distro; then
        # redhat
        nextos_cmdline="root=live:$nextos_squashfs inst.ks=$nextos_ks"
    fi

    if is_distro_like_debian $nextos_distro; then
        if [ "$basearch" = "x86_64" ]; then
            # debian installer 好像第一个 tty 是主 tty
            # 设置ttyS0,tty0,安装界面还是显示在ttyS0
            :
        else
            # debian arm 在没有ttyAMA0的机器上（aws t4g），最少要设置一个tty才能启动
            # 只设置tty0也行，但安装过程ttyS0没有显示
            nextos_cmdline+=" console=ttyAMA0,115200 console=ttyS0,115200 console=tty0"
        fi
    else
        # nextos_cmdline+=" $(echo_tmp_ttys)"
        nextos_cmdline+=" console=ttyAMA0,115200 console=ttyS0,115200 console=tty0"
    fi
    # nextos_cmdline+=" mem=256M"
    # nextos_cmdline+=" lowmem=+1"
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

mod_initrd_debian_kali() {
    # hack 1
    # 允许设置 ipv4 onlink 网关
    sed -Ei 's,&&( onlink=),||\1,' etc/udhcpc/default.script

    # hack 2
    # 修改 /var/lib/dpkg/info/netcfg.postinst 运行我们的脚本
    # shellcheck disable=SC1091,SC2317
    netcfg() {
        #!/bin/sh
        . /usr/share/debconf/confmodule
        db_progress START 0 5 debian-installer/netcfg/title

        : get_ip_conf_cmd

        # 运行 trans.sh，保存配置
        db_progress INFO base-installer/progress/netcfg
        sh /trans.sh
        db_progress STEP 1
    }

    # 直接覆盖 net-retriever，方便调试
    # curl -Lo /usr/lib/debian-installer/retriever/net-retriever $confhome/net-retriever

    postinst=var/lib/dpkg/info/netcfg.postinst
    get_function_content netcfg >$postinst
    get_ip_conf_cmd | insert_into_file $postinst after ": get_ip_conf_cmd"
    # cat $postinst

    # shellcheck disable=SC2317
    expand_packages() {
        expand_packages_real "$@" | while IFS= read -r line; do
            key_=$(echo "$line" | cut -d' ' -f1)
            value=$(echo "$line" | cut -d' ' -f2-)

            case "$key_" in
            Package:)
                package="$value"
                ;;
            Priority:)
                # shellcheck disable=SC2154
                if [ "$value" = standard ] && echo "$disabled_list" | grep -qx "$package"; then
                    line="Priority: optional"
                elif [[ "$package" = ata-modules* ]]; then
                    # 改成强制安装
                    # 因为是 pata-modules sata-modules scsi-modules 的依赖
                    # 但我们没安装它们，也就不会自动安装 ata-modules
                    line="Priority: standard"
                fi
                ;;
            esac
            echo "$line"
        done
    }

    # shellcheck disable=SC2012
    kver=$(ls -d lib/modules/* | awk -F/ '{print $NF}')

    net_retriever=usr/lib/debian-installer/retriever/net-retriever
    sed -i 's/^expand_packages()/expand_packages_real()/' $net_retriever
    insert_into_file $net_retriever after '#!/bin/sh' <<EOF
disabled_list="
depthcharge-tools-installer
kickseed-common
nobootloader
partman-btrfs
partman-cros
partman-iscsi
partman-jfs
partman-md
partman-xfs
rescue-check
wpasupplicant-udeb
nic-modules-$kver-di
nic-pcmcia-modules-$kver-di
nic-usb-modules-$kver-di
nic-wireless-modules-$kver-di
nic-shared-modules-$kver-di
pcmcia-modules-$kver-di
pcmcia-storage-modules-$kver-di
cdrom-core-modules-$kver-di
firewire-core-modules-$kver-di
usb-storage-modules-$kver-di
isofs-modules-$kver-di
jfs-modules-$kver-di
xfs-modules-$kver-di
loop-modules-$kver-di
pata-modules-$kver-di
sata-modules-$kver-di
scsi-modules-$kver-di
"

expand_packages() {
    $(get_function_content expand_packages)
}
EOF

    # https://github.com/linuxhw/LsPCI?tab=readme-ov-file#storageata-pci
    # https://debian.pkgs.org/12/debian-main-amd64/linux-image-6.1.0-18-cloud-amd64_6.1.76-1_amd64.deb.html
    # https://deb.debian.org/debian/pool/main/l/linux-signed-amd64/
    # https://deb.debian.org/debian/dists/bookworm/main/debian-installer/binary-all/Packages.xz
    # https://deb.debian.org/debian/dists/bookworm/main/debian-installer/binary-amd64/Packages.xz
    # 以下是 debian-installer 有的驱动，这些驱动云内核不一定都有，(+)表示云内核有
    # scsi-core-modules 默认安装（不用修改），是 ata-modules 的依赖
    #                   包含 sd_mod.ko(+) scsi_mod.ko(+) scsi_transport_fc.ko(+) scsi_transport_sas.ko(+) scsi_transport_spi.ko(+)
    # ata-modules       默认可选（改成必装），是下方模块的依赖。只有 ata_generic.ko(+) 和 libata.ko(+) 两个驱动

    # pata-modules      默认安装（改成可选），里面的驱动都是 pata_ 开头，但只有 pata_legacy.ko(+) 在云内核中
    # sata-modules      默认安装（改成可选），里面的驱动大部分是 sata_ 开头的，其他重要的还有 ahci.ko libahci.ko ata_piix.ko(+)
    #                   云内核没有 sata 模块，也没有内嵌，有一个 CONFIG_SATA_HOST=y，libata-$(CONFIG_SATA_HOST)	+= libata-sata.o
    # scsi-modules      默认安装（改成可选），包含 nvme.ko(+) 和各种虚拟化驱动(+)

    download_and_extract_udeb() {
        package=$1
        extract_dir=$2

        # 获取 udeb 列表
        udeb_list=$tmp/udeb_list
        if ! [ -f $udeb_list ]; then
            # shellcheck disable=SC2154
            curl -L http://$nextos_deb_hostname/$distro/dists/$nextos_codename/main/debian-installer/binary-$basearch_alt/Packages.gz |
                zcat | grep 'Filename:' | awk '{print $2}' >$udeb_list
        fi

        # 下载 udeb
        curl -Lo $tmp/tmp.udeb http://$nextos_deb_hostname/$distro/"$(grep /$package $udeb_list)"

        if false; then
            # 使用 dpkg
            # cygwin 没有 dpkg
            install_pkg dpkg
            dpkg -x $tmp/tmp.udeb $extract_dir
        else
            # 使用 ar tar xz
            # cygwin 需安装 binutils
            # centos7 ar 不支持 --output
            install_pkg ar tar xz
            (cd $tmp && ar x $tmp/tmp.udeb)
            tar xf $tmp/data.tar.xz -C $extract_dir
        fi
    }

    # 不用在 windows 判断是哪种硬盘控制器，因为 256M 运行 windows 只可能是 xp，而脚本本来就不支持 xp
    # 在 debian installer 中判断能否用云内核
    create_can_use_cloud_kernel_sh can_use_cloud_kernel.sh

    # 最近 kali initrd 删除了原版 wget
    # 但 initrd 的 busybox wget 又不支持 https
    # 因此改成在这里下载
    curl -LO "$confhome/get-xda.sh"
    curl -LO "$confhome/ttys.sh"

    # 可以节省一点内存？
    echo 'export DEBCONF_DROP_TRANSLATIONS=1' |
        insert_into_file lib/debian-installer/menu before 'exec debconf'

    # 还原 kali netinst.iso 的 simple-cdd 机制
    # 主要用于调用 kali.postinst 设置 zsh 为默认 shell
    # 但 mini.iso 又没有这种机制
    # https://gitlab.com/kalilinux/build-scripts/live-build-config/-/raw/master/kali-config/common/includes.installer/kali-finish-install?ref_type=heads
    # https://salsa.debian.org/debian/simple-cdd/-/blob/master/debian/14simple-cdd?ref_type=heads
    # https://http.kali.org/pool/main/s/simple-cdd/simple-cdd-profiles_0.6.9_all.udeb
    if [ "$distro" = kali ]; then
        # 但我们没有使用 iso，因此没有 kali.postinst，需要另外下载
        mkdir -p cdrom/simple-cdd
        curl -Lo cdrom/simple-cdd/kali.postinst https://gitlab.com/kalilinux/build-scripts/live-build-config/-/raw/master/kali-config/common/includes.installer/kali-finish-install?ref_type=heads
        chmod a+x cdrom/simple-cdd/kali.postinst
    fi

    # 提前下载 fdisk
    # 因为 fdisk-udeb 包含 fdisk 和 sfdisk，提前下载可减少占用
    mkdir_clear $tmp/fdisk
    download_and_extract_udeb fdisk-udeb $tmp/fdisk
    cp -f $tmp/fdisk/usr/sbin/fdisk usr/sbin/

    # >256M 或者当前系统是 windows
    if [ $ram_size -gt 256 ] || is_in_windows; then
        sed -i '/^pata-modules/d' $net_retriever
        sed -i '/^sata-modules/d' $net_retriever
        sed -i '/^scsi-modules/d' $net_retriever
    else
        # <=256M 极限优化
        find_main_disk
        extra_drivers=
        for driver in $(get_disk_drivers); do
            echo "using driver: $driver"
            case $driver in
            nvme | virtio_blk | virtio_scsi | xen_blkfront | xen_scsifront | hv_storvsc | vmw_pvscsi) extra_drivers+=" $driver" ;;
            pata_legacy) sed -i '/^pata-modules/d' $net_retriever ;; # 属于 pata-modules
            ata_piix) sed -i '/^sata-modules/d' $net_retriever ;;    # 属于 sata-modules
            ata_generic) ;;                                          # 属于 ata-modules，不用处理，因为我们设置强制安装了 ata-modules
            esac
        done

        # extra drivers
        # xen 还需要以下两个？
        # kernel/drivers/xen/xen-scsiback.ko
        # kernel/drivers/block/xen-blkback/xen-blkback.ko
        # 但反查也找不到 curl https://deb.debian.org/debian/dists/bookworm/main/Contents-udeb-amd64.gz | zcat | grep xen
        if [ -n "$extra_drivers" ]; then
            mkdir_clear $tmp/scsi
            download_and_extract_udeb scsi-modules-$kver-di $tmp/scsi
            udeb_drivers_dir=$tmp/scsi/lib/modules/$kver/kernel/drivers
            (
                cd lib/modules/*/kernel/drivers/
                mkdir -p block scsi nvme/host
                for driver in $extra_drivers; do
                    echo "adding driver: $driver"
                    case $driver in
                    # debian 模块没有压缩
                    # kali 模块有压缩
                    # 因此要有 *
                    nvme)
                        cp -fv $udeb_drivers_dir/nvme/host/nvme.ko* nvme/host/
                        cp -fv $udeb_drivers_dir/nvme/host/nvme-core.ko* nvme/host/
                        ;;
                    virtio_blk) cp -fv $udeb_drivers_dir/block/virtio_blk.ko* block/ ;;
                    virtio_scsi) cp -fv $udeb_drivers_dir/scsi/virtio_scsi.ko* scsi/ ;;
                        # xen 的横杠特别不同
                    xen_blkfront) cp -fv $udeb_drivers_dir/block/xen-blkfront.ko* block/ ;;
                    xen_scsifront) cp -fv $udeb_drivers_dir/scsi/xen-scsifront.ko* scsi/ ;;
                    hv_storvsc) cp -fv $udeb_drivers_dir/scsi/hv_storvsc.ko* scsi/ ;;
                    vmw_pvscsi) cp -fv $udeb_drivers_dir/scsi/vmw_pvscsi.ko* scsi/ ;;
                    esac
                done
            )
        fi
    fi

    # amd64)
    # 	level1=737 # MT=754108, qemu: -m 780
    # 	level2=424 # MT=433340, qemu: -m 460
    # 	min=316    # MT=322748, qemu: -m 350

    # 将 use_level 2 9 修改为 use_level 1
    # x86 use_level 2 会出现 No root file system is defined.
    # arm 即使 use_level 1 也会出现 No root file system is defined.
    sed -i 's/use_level=[29]/use_level=1/' lib/debian-installer-startup.d/S15lowmem

    # hack 3
    # 修改 trans.sh
    # 1. 直接调用 create_ifupdown_config
    insert_into_file $tmp_dir/trans.sh after ': main' <<EOF
        distro=$nextos_distro
        create_ifupdown_config /etc/network/interfaces
        exit
EOF
    # 2. 删除 debian busybox 无法识别的语法
    # 3. 删除 apk 语句
    # 4. debian 11/12 initrd 无法识别 > >
    # 5. debian 11/12 initrd 无法识别 < <
    # 6. debian 11 initrd 无法识别 set -E
    # 7. debian 11 initrd 无法识别 trap ERR
    # 删除或注释，可能会导致空方法而报错，因此改为替换成'\n: #'
    replace='\n: #'
    sed -Ei "s/> >/$replace/" $tmp_dir/trans.sh
    sed -Ei "s/< </$replace/" $tmp_dir/trans.sh
    sed -Ei "s/(^[[:space:]]*set[[:space:]].*)E/\1/" $tmp_dir/trans.sh
    sed -Ei "s/^[[:space:]]*apk[[:space:]]/$replace/" $tmp_dir/trans.sh
    sed -Ei "s/^[[:space:]]*trap[[:space:]]/$replace/" $tmp_dir/trans.sh
}

get_disk_drivers() {
    get_drivers "/sys/block/$1"
}

get_net_drivers() {
    get_drivers "/sys/class/net/$1"
}

# 不用在 windows 判断是哪种硬盘/网络驱动，因为 256M 运行 windows 只可能是 xp，而脚本本来就不支持 xp
# 而且安装过程也有二次判断
get_drivers() {
    # 有以下结果组合出现
    # sd_mod
    # virtio_blk
    # virtio_scsi
    # virtio_pci
    # pcieport
    # xen_blkfront
    # ahci
    # nvme
    # mptspi
    # mptsas
    # vmw_pvscsi
    (
        cd "$(readlink -f $1)"
        while ! [ "$(pwd)" = / ]; do
            if [ -d driver ]; then
                if [ -d driver/module ]; then
                    # 显示全名，例如 xen_blkfront sd_mod
                    # 但 ahci 没有这个文件，所以 else 不能省略
                    basename "$(readlink -f driver/module)"
                else
                    # 不显示全名，例如 vbd sd
                    basename "$(readlink -f driver)"
                fi
            fi
            cd ..
        done
    )
}

exit_if_cant_use_cloud_kernel() {
    find_main_disk
    collect_netconf

    # shellcheck disable=SC2154
    if ! can_use_cloud_kernel "$xda" $ipv4_ethx $ipv6_ethx; then
        error_and_exit "Can't use cloud kernel. And not enough RAM to run normal kernel."
    fi
}

can_use_cloud_kernel() {
    # initrd 下也要使用，不要用 <<<

    # 有些虚拟机用了 ahci，但云内核没有 ahci 驱动
    cloud_eth_modules='ena|gve|mana|virtio_net|xen_netfront|hv_netvsc|vmxnet3|mlx4_en|mlx4_core|mlx5_core|ixgbevf'
    cloud_blk_modules='ata_generic|ata_piix|pata_legacy|nvme|virtio_blk|virtio_scsi|xen_blkfront|xen_scsifront|hv_storvsc|vmw_pvscsi'

    # disk
    drivers="$(get_disk_drivers $1)"
    shift
    for driver in $drivers; do
        echo "using disk driver: $driver"
    done
    echo "$drivers" | grep -Ewq "$cloud_blk_modules" || return 1

    # net
    # v4 v6 eth 相同，只检查一次
    if [ "$1" = "$2" ]; then
        shift
    fi
    while [ $# -gt 0 ]; do
        drivers="$(get_net_drivers $1)"
        shift
        for driver in $drivers; do
            echo "using net driver: $driver"
        done
        echo "$drivers" | grep -Ewq "$cloud_eth_modules" || return 1
    done
}

create_can_use_cloud_kernel_sh() {
    cat <<EOF >$1
        $(get_function get_drivers)
        $(get_function get_net_drivers)
        $(get_function get_disk_drivers)
        $(get_function can_use_cloud_kernel)

        can_use_cloud_kernel "\$@"
EOF
}

get_ip_conf_cmd() {
    collect_netconf >&2
    is_in_china && is_in_china=true || is_in_china=false

    sh=/alpine-network.sh
    if is_found_ipv4_netconf && is_found_ipv6_netconf && [ "$ipv4_mac" = "$ipv6_mac" ]; then
        echo "'$sh' '$ipv4_mac' '$ipv4_addr' '$ipv4_gateway' '$ipv6_addr' '$ipv6_gateway' '$is_in_china'"
    else
        if is_found_ipv4_netconf; then
            echo "'$sh' '$ipv4_mac' '$ipv4_addr' '$ipv4_gateway' '' '' '$is_in_china'"
        fi
        if is_found_ipv6_netconf; then
            echo "'$sh' '$ipv6_mac' '' '' '$ipv6_addr' '$ipv6_gateway' '$is_in_china'"
        fi
    fi
}

mod_initrd_alpine() {
    # hack 1 v3.19 和之前的 virt 内核需添加 ipv6 模块
    if virt_dir=$(ls -d $tmp_dir/lib/modules/*-virt 2>/dev/null); then
        ipv6_dir=$virt_dir/kernel/net/ipv6
        if ! [ -f $ipv6_dir/ipv6.ko ] || ! grep -q ipv6 $tmp_dir/lib/modules/*/modules.builtin; then
            mkdir -p $ipv6_dir
            modloop_file=$tmp/modloop_file
            modloop_dir=$tmp/modloop_dir
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
    fi

    # hack 2 /usr/share/udhcpc/default.script
    # 脚本被调用的顺序
    # udhcpc:  deconfig
    # udhcpc:  bound
    # udhcpc6: deconfig
    # udhcpc6: bound
    # shellcheck disable=SC2317
    udhcpc() {
        if [ "$1" = deconfig ]; then
            return
        fi
        if [ "$1" = bound ] && [ -n "$ipv6" ]; then
            # shellcheck disable=SC2154
            ip -6 addr add "$ipv6" dev "$interface"
            ip link set dev "$interface" up
            return
        fi
    }

    get_function_content udhcpc |
        insert_into_file usr/share/udhcpc/default.script after 'deconfig\|renew\|bound'

    # 允许设置 ipv4 onlink 网关
    sed -Ei 's,(0\.0\.0\.0\/0),"\1 onlink",' usr/share/udhcpc/default.script

    # hack 3 网络配置
    # alpine 根据 MAC_ADDRESS 判断是否有网络
    # https://github.com/alpinelinux/mkinitfs/blob/c4c0115f9aa5aa8884c923dc795b2638711bdf5c/initramfs-init.in#L914
    insert_into_file init after 'configure_ip\(\)' <<EOF
        depmod
        [ -d /sys/module/ipv6 ] || modprobe ipv6
        $(get_ip_conf_cmd)
        MAC_ADDRESS=1
        return
EOF

    # grep -E -A5 'configure_ip\(\)' init

    # hack 4 运行 trans.start
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
        cp /trans.sh \$sysroot/etc/local.d/trans.start
        chmod a+x \$sysroot/etc/local.d/trans.start
        ln -s /etc/init.d/local \$sysroot/etc/runlevels/default/
EOF

    # 判断云镜像 debain 能否用云内核
    if is_distro_like_debian; then
        create_can_use_cloud_kernel_sh can_use_cloud_kernel.sh
        insert_into_file init before '^exec (/bin/busybox )?switch_root' <<EOF
        cp /can_use_cloud_kernel.sh \$sysroot/
        chmod a+x \$sysroot/can_use_cloud_kernel.sh
EOF
    fi
}

mod_initrd() {
    info "mod $nextos_distro initrd"
    install_pkg gzip cpio

    # 解压
    # 先删除临时文件，避免之前运行中断有残留文件
    tmp_dir=$tmp/initrd
    mkdir_clear $tmp_dir
    cd $tmp_dir

    # cygwin 下处理 debian initrd 时
    # 解压/重新打包/删除 initrd 的 /dev/console /dev/null 都会报错
    # cpio: dev/console: Cannot utime: Invalid argument
    # cpio: ./dev/console: Cannot stat: Bad address
    # 用 windows 文件管理器可删除

    # 但同样运行 zcat /reinstall-initrd | cpio -idm
    # 打开 C:\cygwin\Cygwin.bat ，运行报错
    # 打开桌面的 Cygwin 图标，运行就没问题

    # shellcheck disable=SC2046
    # nonmatching 是精确匹配路径
    zcat /reinstall-initrd | cpio -idm \
        $(is_in_windows && echo --nonmatching 'dev/console' --nonmatching 'dev/null')

    curl -Lo $tmp_dir/trans.sh $confhome/trans.sh
    curl -Lo $tmp_dir/alpine-network.sh $confhome/alpine-network.sh
    chmod a+x $tmp_dir/trans.sh $tmp_dir/alpine-network.sh

    if is_distro_like_debian $nextos_distro; then
        mod_initrd_debian_kali
    else
        mod_initrd_$nextos_distro
    fi

    # alpine live 不精简 initrd
    # 因为不知道用户想干什么，可能会用到精简的文件
    if is_virt && ! is_alpine_live; then
        remove_useless_initrd_files
    fi

    # 重建
    # 注意要用 cpio -H newc 不要用 cpio -c ，不同版本的 -c 作用不一样，很坑
    # -c    Use the old portable (ASCII) archive format
    # -c    Identical to "-H newc", use the new (SVR4)
    #       portable format.If you wish the old portable
    #       (ASCII) archive format, use "-H odc" instead.
    find . | cpio --quiet -o -H newc | gzip -1 >/reinstall-initrd
    cd - >/dev/null
}

remove_useless_initrd_files() {
    # 显示精简前的大小
    du -sh .

    # 删除 initrd 里面没用的文件/驱动
    rm -rf bin/brltty
    rm -rf etc/brltty
    rm -rf sbin/wpa_supplicant
    rm -rf usr/lib/libasound.so.*
    rm -rf usr/share/alsa
    (
        cd lib/modules/*/kernel/drivers/net/ethernet/
        for item in *; do
            case "$item" in
            intel | amazon | google) ;;
            *) rm -rf $item ;;
            esac
        done
    )
    (
        cd lib/modules/*/kernel
        for item in \
            net/mac80211 \
            net/wireless \
            net/bluetooth \
            drivers/hid \
            drivers/mmc \
            drivers/mtd \
            drivers/usb \
            drivers/ssb \
            drivers/mfd \
            drivers/bcma \
            drivers/pcmcia \
            drivers/parport \
            drivers/platform \
            drivers/staging \
            drivers/net/usb \
            drivers/net/bonding \
            drivers/net/wireless \
            drivers/input/rmi4 \
            drivers/input/keyboard \
            drivers/input/touchscreen \
            drivers/bus/mhi \
            drivers/char/pcmcia \
            drivers/misc/cardreader; do
            rm -rf $item
        done
    )

    # 显示精简后的大小
    du -sh .
}

# 脚本入口
if is_in_windows; then
    # win系统盘
    c=$(echo $SYSTEMDRIVE | cut -c1)

    # 64位系统 + 32位cmd/cygwin，需要添加 PATH，否则找不到64位系统程序，例如bcdedit
    sysnative=$(cygpath -u $WINDIR\\Sysnative)
    if [ -d $sysnative ]; then
        PATH=$PATH:$sysnative
    fi

    # 更改 windows 命令输出语言为英文
    # chcp 会清屏
    mode.com con cp select=437 >/dev/null
fi

# 检查 root
if is_in_windows; then
    # 64位系统 + 32位cmd/cygwin，运行 openfiles 报错：目标系统必须运行 32 位的操作系统
    if ! fltmc >/dev/null 2>&1; then
        error_and_exit "Please run as administrator."
    fi
else
    if [ "$EUID" -ne 0 ]; then
        error_and_exit "Please run as root."
    fi
fi

# 整理参数
if ! opts=$(getopt -n $0 -o "" --long ci,debug,hold:,sleep:,iso:,image-name:,img:,lang:,commit: -- "$@"); then
    usage_and_exit
fi

eval set -- "$opts"
# shellcheck disable=SC2034
while true; do
    case "$1" in
    --commit)
        commit=$2
        shift 2
        ;;
    --debug)
        set -x
        shift
        ;;
    --ci)
        cloud_image=1
        shift
        ;;
    --hold | --sleep)
        hold=$2
        if ! { [ "$hold" = 1 ] || [ "$hold" = 2 ]; }; then
            error_and_exit "Invalid --hold value: $hold."
        fi
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
        image_name=$(echo "$2" | to_lower)
        shift 2
        ;;
    --lang)
        lang=$(echo "$2" | to_lower)
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
    error_and_exit "Please disable secure boot first."
fi

# 必备组件
install_pkg curl grep

# /tmp 挂载在内存的话，可能不够空间
tmp=/reinstall-tmp
mkdir_clear "$tmp"

# 强制忽略/强制添加 --ci 参数
# debian 不强制忽略 ci 留作测试
case "$distro" in
dd | windows | netboot.xyz | kali | alpine | arch | gentoo)
    if is_use_cloud_image; then
        echo "ignored --ci"
        cloud_image=0
    fi
    ;;
centos | alma | rocky | oracle | ubuntu | fedora | opensuse)
    cloud_image=1
    ;;
esac

# 检查内存
check_ram

# 检查硬件架构
if is_in_windows; then
    # x86-based PC
    # x64-based PC
    # ARM-based PC
    # ARM64-based PC
    basearch=$(wmic ComputerSystem get SystemType /format:list |
        grep '=' | cut -d= -f2 | cut -d- -f1)
else
    # archlinux 云镜像没有 arch 命令
    # https://en.wikipedia.org/wiki/Uname
    basearch=$(uname -m)
fi

# 统一架构名称，并强制 64 位
case "$(echo $basearch | to_lower)" in
i?86 | x64 | x86* | amd64)
    basearch=x86_64
    basearch_alt=amd64
    ;;
arm* | aarch64)
    basearch=aarch64
    basearch_alt=arm64
    ;;
*) error_and_exit "Unsupported arch: $basearch" ;;
esac

# 设置国内代理
# gitee 不支持ipv6
# jsdelivr 有12小时缓存
# https://github.com/XIU2/UserScript/blob/master/GithubEnhanced-High-Speed-Download.user.js#L31
if [ -n "$github_proxy" ] && [[ "$confhome" = http*://raw.githubusercontent.com/* ]]; then
    # 未测试
    if false; then
        repo=$(echo $confhome | cut -d/ -f4,5)
        branch=$(echo $confhome | cut -d/ -f6)
        # 避免脚本更新时，文件不同步造成错误
        if [ -z "$commit" ]; then
            commit=$(curl -L https://api.github.com/repos/$repo/git/refs/heads/$branch |
                grep '"sha"' | grep -Eo '[0-9a-f]{40}')
        fi
        # shellcheck disable=SC2001
        confhome=$(echo "$confhome" | sed "s/main$/$commit/")
    fi

    if is_in_china; then
        confhome=${confhome/http:\/\//https:\/\/}
        confhome=${confhome/https:\/\/raw.githubusercontent.com/$github_proxy}
    fi
fi

# 以下目标系统不需要两步安装
# alpine
# debian
# el7 x86_64 >=1g
# el7 aarch64 >=1.5g
# el8/9/fedora 任何架构 >=2g
if is_netboot_xyz ||
    { ! is_use_cloud_image && {
        [ "$distro" = "alpine" ] || is_distro_like_debian ||
            { is_distro_like_redhat && [ $releasever -eq 7 ] && [ $ram_size -ge 1024 ] && [ $basearch = "x86_64" ]; } ||
            { is_distro_like_redhat && [ $releasever -eq 7 ] && [ $ram_size -ge 1536 ] && [ $basearch = "aarch64" ]; } ||
            { is_distro_like_redhat && [ $releasever -ge 8 ] && [ $ram_size -ge 2048 ]; }
    }; }; then
    setos nextos $distro $releasever
else
    # alpine 作为中间系统时，使用 3.20
    alpine_ver_for_trans=3.20
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
    if is_use_firmware; then
        curl -Lo /reinstall-firmware $nextos_firmware
    fi
fi

# 修改 alpine debian kali initrd
if [ "$nextos_distro" = alpine ] || is_distro_like_debian "$nextos_distro"; then
    mod_initrd
fi

# 将内核/netboot.xyz.lkrn 放到正确的位置
if false && is_use_grub; then
    if is_in_windows; then
        cp -f /reinstall-vmlinuz /cygdrive/$c/
        is_have_initrd && cp -f /reinstall-initrd /cygdrive/$c/
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
        # linux aarch64 原系统的 grub 可能无法启动 alpine 3.19 的内核
        # 要用去除了内核 magic number 校验的 grub
        # 为了方便测试，linux x86 efi 也采用外部 grub
        if is_efi; then
            install_grub_linux_efi
        fi
    fi

    info 'create grub config'

    # 寻找 grub.cfg
    if is_in_windows; then
        if is_efi; then
            grub_cfg=/cygdrive/$c/grub.cfg
        else
            grub_cfg=/cygdrive/$c/grub/grub.cfg
        fi
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

    # 判断用 linux 还是 linuxefi（主要是红帽系）
    # 现在 efi 用下载的 grub，因此不需要判断 linux 或 linuxefi
    if false && is_use_local_grub; then
        # 在x86 efi机器上，不同版本的 grub 可能用 linux 或 linuxefi 加载内核
        # 通过检测原有的条目有没有 linuxefi 字样就知道当前 grub 用哪一种
        # 也可以检测 /etc/grub.d/10_linux
        if [ -d /boot/loader/entries/ ]; then
            entries="/boot/loader/entries/"
        fi
        if grep -q -r -E '^[[:space:]]*linuxefi[[:space:]]' $grub_cfg $entries; then
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

    # 找到 /reinstall-vmlinuz /reinstall-initrd 的绝对路径
    if is_in_windows; then
        # dir=/cygwin/
        dir=$(cygpath -m / | cut -d: -f2-)/
    else
        # 获取当前系统根目录在 btrfs 中的绝对路径
        if is_os_in_btrfs; then
            # btrfs subvolume show /
            # 输出可能是 / 或 root 或 @/.snapshots/1/snapshot
            dir=$(btrfs subvolume show / | head -1)
            if ! [ "$dir" = / ]; then
                dir="/$dir/"
            fi
        else
            dir=/
        fi
    fi

    vmlinuz=${dir}reinstall-vmlinuz
    initrd=${dir}reinstall-initrd
    firmware=${dir}reinstall-firmware

    # 生成 linux initrd 命令
    if is_netboot_xyz; then
        linux_cmd="linux16 $vmlinuz"
    else
        find_main_disk
        build_cmdline
        linux_cmd="linux$efi $vmlinuz $cmdline"
        initrd_cmd="initrd$efi $initrd"
        if is_use_firmware; then
            initrd_cmd+=" $firmware"
        fi
    fi

    # cloudcone 从光驱的 grub 启动，再加载硬盘的 grub.cfg
    # menuentry "Grub 2" --id grub2 {
    #         set root=(hd0,msdos1)
    #         configfile /boot/grub2/grub.cfg
    # }

    # 加载后 $prefix 依然是光驱的 (hd96)/boot/grub
    # 导致找不到 $prefix 目录的 grubenv，因此读取不到 next_entry
    # 以下方法为 cloudcone 重新加载 grubenv

    # 需查找 2*2 个文件夹
    # 分区：系统 / boot
    # 文件夹：grub / grub2
    # shellcheck disable=SC2121,SC2154
    # cloudcone debian 能用但 ubuntu 模板用不了
    # ubuntu 模板甚至没显示 reinstall menuentry
    load_grubenv_if_not_loaded() {
        if ! [ -s $prefix/grubenv ]; then
            for dir in /boot/grub /boot/grub2 /grub /grub2; do
                set grubenv="($root)$dir/grubenv"
                if [ -s $grubenv ]; then
                    load_env --file $grubenv
                    if [ "${next_entry}" ]; then
                        set default="${next_entry}"
                        set next_entry=
                        save_env --file $grubenv next_entry
                    else
                        set default="0"
                    fi
                    return
                fi
            done
        fi
    }

    # 生成 grub 配置
    # 实测 centos 7 lvm 要手动加载 lvm 模块
    echo $target_cfg

    get_function_content load_grubenv_if_not_loaded >$target_cfg

    del_empty_lines <<EOF | tee -a $target_cfg
set timeout_style=menu
set timeout=5
menuentry "$(get_entry_name)" {
    $(! is_in_windows && echo 'insmod lvm')
    $(is_os_in_btrfs && echo 'set btrfs_relative_path=n')
    insmod all_video
    search --no-floppy --file --set=root $vmlinuz
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

if ! { is_netboot_xyz || is_use_dd; }; then
    if [ "$distro" = windows ]; then
        username="administrator"
    else
        username="root"
    fi
    echo "Username: $username"
    echo "Password: 123@@@"
fi

if is_netboot_xyz; then
    echo 'Reboot to start netboot.xyz.'
elif is_alpine_live; then
    echo 'Reboot to start Alpine Live OS.'
elif is_use_dd; then
    echo 'Reboot to start DD.'
else
    echo "Reboot to start the installation."
fi

if is_in_windows; then
    echo 'You can run this command to reboot:'
    echo 'shutdown /r /t 0'
fi

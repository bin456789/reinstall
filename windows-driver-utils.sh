#!/bin/ash
# shellcheck shell=dash
# shellcheck disable=SC3001,SC3003,SC3010
# reinstall.sh / trans.sh 共用此文件

# grep 无法处理 UTF-16LE 编码的 inf，有以下几种解决方法
# 1. 使用 ripgrep (rg) 或者 ugrep，但 cygwin 没有
# 2. grep -a a.b.c.d
# 3. iconv -f UTF-16 -t UTF-8

del_inf_comment() {
    sed 's/;.*//'
}

simply_inf() {
    convert_file_to_utf8 "$1" | del_cr | del_inf_comment | trim | del_empty_lines
}

convert_file_to_utf8() {
    # ash 用 * 比较字符串有问题
    # [[ $'\xEF\xBB' = $'\xEF\xBB*' ]] && echo 1

    # UTF-16LE without BOM 要处理吗？ windows 支持这种编码的 inf?

    # UTF-16LE with BOM
    if [ "$(head -c2 "$1")" = $'\xFF\xFE' ]; then
        # -f UTF-16LE -t UTF-8 会添加 UTF-8 BOM
        iconv -f UTF-16 -t UTF-8 "$1"

    # UTF-8 with BOM
    elif [ "$(head -c3 "$1")" = $'\xEF\xBB\xBF' ]; then
        # busybox sed 不支持
        # sed '1s/^\xEF\xBB\xBF//' "$1"
        tail -c +4 "$1"

    # 其它
    else
        cat "$1"
    fi
}

simply_inf_word() {
    # 1 删除引号 "
    # 2 删除两边空格
    # 3 \ 和 .\ 换成 /
    # 4 连续的 / 替换成单个 /
    # 5 删除最前面的 /
    sed -E \
        -e 's,",,g' \
        -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' \
        -e 's,\.?\\,/,g' \
        -e 's,/+,/,g' \
        -e 's,^/,,'
}

# reinstall.sh 下无法判断 iso 是 32 位还是 64 位，此时 mix_x86_x86_64 为 true
# trans.sh 下可以判断 iso 是 32 位还是 64 位，此时 mix_x86_x86_64 为 false
list_files_from_inf() {
    local inf=$1
    local arch=$2 # x86 amd64 arm64
    local mix_x86_x86_64=$3

    # 所有字段不区分大小写
    inf_txts=$(simply_inf "$inf" | to_lower)

    is_match_section() {
        local section=$1

        [ "$line" = "[$section]" ] || [ "$line" = "[$section.$arch]" ] ||
            { $mix_x86_x86_64 && [ "$arch" = x86 ] && [ "$line" = "[$section.amd64]" ]; } ||
            { $mix_x86_x86_64 && [ "$arch" = amd64 ] && [ "$line" = "[$section.x86]" ]; }
    }

    is_match_catalogfile() {
        local left
        left=$(echo "$line" | awk -F= '{print $1}' | simply_inf_word)

        # catalogfile.nt 是指所有 nt ?
        [ "$left" = "catalogfile" ] ||
            [ "$left" = "catalogfile.nt" ] ||
            [ "$left" = "catalogfile.nt$arch" ] ||
            { $mix_x86_x86_64 && [ "$arch" = x86 ] && [ "$left" = "catalogfile.ntamd64" ]; } ||
            { $mix_x86_x86_64 && [ "$arch" = amd64 ] && [ "$left" = "catalogfile.ntx86" ]; }
    }

    is_match_manufacturer_arch() {
        # x86 可写 NT / NTx86, 其它必须明确架构
        # https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-manufacturer-section
        case "$arch" in
        x86) $mix_x86_x86_64 && regex='NT|NTx86|NTamd64' || regex='NT|NTx86' ;;
        amd64) $mix_x86_x86_64 && regex='NT|NTx86|NTamd64' || regex='NTamd64' ;;
        arm64) regex='NTarm64' ;;
        esac

        # 注意 cut awk 结果不同
        # 虽然在这里不会造成影响
        # echo 1 | cut -d, -f2-
        # 1
        # echo 1 | awk -F, '{print $2}'
        # 空白

        echo "$line" | awk -F, '{for(i=2;i<=NF;i++) print $i}' | grep -Eiwq "$regex"
    }

    # 还需要从 [Strings] 读取字符串?

    # 0. 检测 inf 是否适合当前架构
    # 目前没有对比版本号

    ##############################################
    # 注意这种情况, NTamd64.6.0 为空，表示不支持 6.0

    # [Manufacturer]
    # %V_INTEL%   = Intel, NTamd64.6.0, NTamd64.6.1.1

    # [Intel.NTamd64.6.0]
    # ; Empty section.

    # 如果后期改成不从 Manufacturer 获取支持的架构，而是从[]获取支持的架构，注意这种情况
    # [Intel.NTamd64.10.0.1..22000]
    ##############################################

    # 例子1
    # [Manufacturer]
    # %Amazon% = AWSNVME, NTamd64, NTARM64

    # 例子2
    # [Manufacturer]
    # %MyName% = MyName,NTx86.6.0,NTx86.5.1,
    # .
    # [MyName.NTx86.6.0] ; Empty section, so this INF does not support
    # .                  ; NT 6.0 and later.
    # .
    # [MyName.NTx86.5.1] ; Used for NT 5.1 and later
    # .                  ; (but not NT 6.0 and later due to the NTx86.6.0 entry)
    # %MyDev% = InstallB,hwid
    # .
    # [MyName]           ; Empty section, so this INF does not support
    # .                  ; Win2000
    # .

    # 例子3
    # 系统自带的驱动，没有 [Manufacturer]

    # 例子4
    # C:\Windows\INF\wfcvsc.inf
    # %StdMfg%=Standard,NTamd64...0x0000001,NTamd64...0x0000002,NTamd64...0x0000003

    in_section=false
    arch_matched=false
    has_manufacturer=false
    # 未添加 IFS= 时，read 会删除行首行尾的空白字符
    while read -r line; do
        if [[ "$line" = "["* ]]; then
            is_match_section manufacturer && has_manufacturer=true && in_section=true || in_section=false
            continue
        fi

        if $in_section; then
            if is_match_manufacturer_arch; then
                arch_matched=true
                break
            fi
        fi
    done < <(echo "$inf_txts")

    if $has_manufacturer && ! $arch_matched; then
        return 10
    fi

    # 1. 输出 .inf 文件名
    basename "$inf"

    # 2. 输出 .cat 相对路径
    # 例子
    # [version]
    # CatalogFile = "xxxxx.cat"
    # CatalogFile.NTAMD64=Balloon.cat
    in_section=false
    # 未添加 IFS= 时，read 会删除行首行尾的空白字符
    while read -r line; do
        if [[ "$line" = "["* ]]; then
            is_match_section version && in_section=true || in_section=false
            continue
        fi

        if $in_section && is_match_catalogfile; then
            echo "$line" | awk -F= '{print $2}' | simply_inf_word
        fi
    done < <(echo "$inf_txts")

    # 3. 获取 SourceDisksNames
    # 例子
    # [SourceDisksNames]
    # 1 = "Windows NT CD-ROM",file.tag,, "\common"
    SourceDisksNames=
    in_section=false
    # 未添加 IFS= 时，read 会删除行首行尾的空白字符
    while read -r line; do
        if [[ "$line" = "["* ]]; then
            is_match_section sourcedisksnames && in_section=true || in_section=false
            continue
        fi
        # 注意可能有空格和引号

        if $in_section; then
            local num dir
            num=$(echo "$line" | awk -F= '{print $1}' | simply_inf_word)
            dir=$(echo "$line" | awk -F, '{print $4}' | simply_inf_word)
            # 每行一条记录
            if [ -n "$SourceDisksNames" ]; then
                SourceDisksNames=$SourceDisksNames$'\n'
            fi
            SourceDisksNames="$SourceDisksNames$num:$dir"
        fi
    done < <(echo "$inf_txts")

    # 4. 打印 SourceDisksFiles 的绝对路径
    # 例子
    # [SourceDisksFiles]
    # aha154x.sys = 1 , "\x86" ,,
    in_section=false
    # 未添加 IFS= 时，read 会删除行首行尾的空白字符
    while read -r line; do
        if [[ "$line" = "["* ]]; then
            is_match_section sourcedisksfiles && in_section=true || in_section=false
            continue
        fi

        if $in_section; then
            file=$(echo "$line" | awk -F= '{print $1}' | simply_inf_word)
            num=$(echo "$line" | awk -F'=|,' '{print $2}' | simply_inf_word)
            sub_dir=$(echo "$line" | awk -F, '{print $2}' | simply_inf_word)
            # 可能有多个
            while IFS= read -r parent_dir; do
                echo "$parent_dir/$sub_dir/$file" | simply_inf_word
            done < <(echo "$SourceDisksNames" | awk -F: "\$1==\"$num\" {print \$2}")
        fi
    done < <(echo "$inf_txts")
}

# windows 安装驱动时，只会安装相同架构的驱动文件到系统，即使 inf 里有列出其它架构的驱动
# 因此 DISM 导出驱动时，也就没有包含其它架构的驱动文件

# 用于尽可能匹配路径大小写
get_path_in_correct_case() {
    # 同时支持参数和管道
    local path
    path=$({ if [ -n "$1" ]; then echo "$1"; else cat; fi; })

    # 用 / 分割路径，提取成列表
    # 例如: ///a///b/c.inf -> a b c.inf
    # shellcheck disable=SC2046
    set -- $(echo "$path" | grep -o '[^/]*')
    (
        local output=
        if is_absolute_path "$path"; then
            cd /
            output=/
        fi

        stop_find=false

        while [ $# -gt 0 ]; do
            local part=$1
            local tmp
            # shellcheck disable=SC2010
            if ! $stop_find; then
                if tmp=$(ls -1 | grep -Fix "$part"); then
                    part=$tmp
                    # 大于 1 表示当前 part 是目录
                    if [ $# -gt 1 ]; then
                        if ! cd "$part" 2>/dev/null; then
                            warn "Can't cd $path"
                            stop_find=true
                        fi
                    fi
                else
                    stop_find=true
                fi
            fi

            if [ $# -gt 1 ]; then
                output="$output$part/"
            else
                # 最后 part
                output="$output$part"
            fi
            shift
        done

        echo "$output"
    )
}

is_file_or_link() {
    # -e / -f 坏软连接，返回 false
    # -L 坏软连接，返回 true
    [ -f "$1" ] || [ -L "$1" ]
}

find_file_ignore_case() {
    # 同时支持参数和管道
    local path
    path=$({ if [ -n "$1" ]; then echo "$1"; else cat; fi; })

    path=$(get_path_in_correct_case "$path")
    if is_file_or_link "$path"; then
        echo "$path"
    else
        warn "Can't find $path" >&2
        return 1
    fi
}

parse_inf_and_cp_driever() {
    local inf=$1
    local dst=$2
    local arch=$3
    local mix_x86_x86_64=$4

    info false "Add driver: $inf"

    # 首先创建目录，否则无法通过 ls 文件数得到编号
    mkdir -p "$dst"
    # shellcheck disable=SC2012
    inf_index=$(($(ls -1 "$dst" | wc -l) + 1))
    inf_old_dir=$(dirname "$inf")
    inf_new_dir=$dst/$inf_index
    if driver_files=$(list_files_from_inf "$inf" "$arch" "$mix_x86_x86_64"); then
        mkdir -p "$inf_new_dir"
        (
            cd "$inf_old_dir" || error_and_exit "Can't cd $inf_old_dir"
            while read -r file; do
                if file=$(find_file_ignore_case "$file"); then
                    cp -v --parents "$file" "$inf_new_dir"
                fi
            done < <(echo "$driver_files")
        )
    else
        if [ $? -eq 10 ]; then
            warn "$inf arch not match."
        else
            error_and_exit "Unknown error while parse $inf."
        fi
    fi
}

get_sys_dir_for_eth() {
    (
        cd "$(readlink -f "/sys/class/net/$1")" || error_and_exit "Can't cd to $1"
        while ! [ "$(pwd)" = / ]; do
            # DRIVER=virtio-pci
            # PCI_CLASS=20000            # 2 开头表示网络设备
            # PCI_ID=1AF4:1041
            # PCI_SUBSYS_ID=1AF4:1100
            # PCI_SLOT_NAME=0000:03:00.0
            if [ -f uevent ] && grep -q 'PCI_CLASS=2' uevent && grep -q 'PCI_ID' uevent; then
                pwd
                return
            fi
            cd ..
        done
        return 1
    )
}

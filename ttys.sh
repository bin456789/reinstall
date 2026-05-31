#!/bin/sh
prefix=$1

# 不要在 windows 上使用，因为不准确
# 在原系统上使用，也可能不准确？例如安装了 cloud 内核的甲骨文？

# 注意 debian initrd 没有 xargs

# 最后一个 tty 是主 tty，显示的信息最全
if [ "$(uname -m)" = "aarch64" ]; then
    ttys="ttyS0 ttyAMA0 tty0"
else
    ttys="ttyS0 tty0"
fi

# 安装环境下 tty 不一定齐全
# hytron 有ttyS0 但无法写入
# 用于 cmdline 引导参数时，明确排除不可写的 tty，避免 getty 反复重启
# https://github.com/bin456789/reinstall/issues/620

if [ "$prefix" = "console=" ]; then
    is_for_cmdline=true
else
    is_for_cmdline=false
fi

# 用途       条件
# 安装日志   存在且可写
# console    存在且可写 或 不存在（因为安装环境下 tty 不一定齐全）

is_first=true
for tty in $ttys; do
    if { [ -c "/dev/$tty" ] && stty -g -F "/dev/$tty" >/dev/null 2>&1; } ||
        { $is_for_cmdline && ! [ -c "/dev/$tty" ]; }; then
        if $is_first; then
            is_first=false
        else
            printf " "
        fi

        printf "%s" "$prefix$tty"

        if $is_for_cmdline &&
            { [ "$tty" = ttyS0 ] || [ "$tty" = ttyAMA0 ]; }; then
            printf ",115200n8"
        fi
    fi
done

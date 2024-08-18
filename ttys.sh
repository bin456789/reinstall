#!/bin/sh
prefix=$1

# 不要在 windows 上使用，因为不准确
# 在原系统上使用，也可能不准确？例如安装了 cloud 内核的甲骨文？

# 注意 debian initrd 没有 xargs

# 最后一个 tty 是主 tty，显示的信息最全
is_first=true
if [ "$(uname -m)" = "aarch64" ]; then
    ttys="ttyS0 ttyAMA0 tty0"
else
    ttys="ttyS0 tty0"
fi

for tty in $ttys; do
    # hytron 有ttyS0 但无法写入
    if stty -g -F "/dev/$tty" >/dev/null 2>&1; then
        if $is_first; then
            is_first=false
        else
            printf " "
        fi

        printf "%s" "$prefix$tty"

        if [ "$prefix" = "console=" ] &&
            { [ "$tty" = ttyS0 ] || [ "$tty" = ttyAMA0 ]; }; then
            printf ",115200n8"
        fi
    fi
done

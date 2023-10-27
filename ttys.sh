#!/bin/sh
prefix=$1

is_in_windows() {
    [ "$(uname -o)" = Cygwin ] || [ "$(uname -o)" = Msys ]
}

# 最后一个 tty 是主 tty，显示的信息最全
is_first=true
for tty in ttyS0 ttyAMA0 tty0; do
    # hytron 有ttyS0 但无法写入
    # cygwin 没有 tty0，所以 windows 下 tty0 免检
    if { [ "$tty" = tty0 ] && is_in_windows; } || stty -g -F "/dev/$tty" >/dev/null 2>&1; then
        if $is_first; then
            is_first=false
        else
            printf " "
        fi

        printf "%s" "$prefix$tty"

        if [ "$prefix" = "console=" ] && [ "$tty" = ttyS0 ]; then
            printf ",115200n8"
        fi
    fi
done

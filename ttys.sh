#!/bin/sh
prefix=$1

# 最后一个 tty 是主 tty，显示的信息最全
# 有些平台例如 aws/gcp 后台vnc只能截图，不能输入，用有没有鼠标判断
# 因此如果有显示器且有鼠标，tty0 放最后面，否则 tty0 放前面
ttys="ttyS0 ttyAMA0"
if [ -e /dev/fb0 ] && [ -e /dev/input/mouse0 ]; then
    ttys="$ttys tty0"
else
    ttys="tty0 $ttys"
fi

is_first=true
for tty in $ttys; do
    if [ -e /dev/$tty ] && echo >/dev/$tty 2>/dev/null; then
        if ! $is_first; then
            printf " "
        fi

        is_first=false

        printf "%s" "$prefix$tty"

        if [ "$prefix" = "console=" ] && [ "$tty" = ttyS0 ]; then
            printf ",115200n8"
        fi
    fi
done

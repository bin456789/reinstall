#!/bin/sh
prefix=$1
for tty in tty0 ttyS0 ttyAMA0; do
    dev_tty=/dev/$tty
    if [ -e $dev_tty ] && echo >$dev_tty 2>/dev/null; then
        if [ -z "$str" ]; then
            str="$prefix$tty"
        else
            str="$str $prefix$tty"
        fi
    fi
done
echo $str

#!/bin/bash

# todo 设置各种参数，例如是否自动安装
localtest=0
if [ $localtest == 1 ]; then
    vmlinuz=http://192.168.43.139/images/pxeboot/vmlinuz
    initrd=http://192.168.43.139/images/pxeboot/initrd.img
    squashfs=http://192.168.43.139/LiveOS/squashfs.img
    ks=http://192.168.43.139/ks-cd.cfg
else
    site=$(curl -L "http://mirrorlist.centos.org/?release=7&repo=os&arch=x86_64" | head -1)
    vmlinuz=${site}images/pxeboot/vmlinuz
    initrd=${site}images/pxeboot/initrd.img
    squashfs=${site}LiveOS/squashfs.img

    ks=https://xxx.com/ks.cfg
fi

# 获取系统盘信息
root_name=$(lsblk -l -o NAME,UUID,TYPE,MOUNTPOINT | tr -s ' ' | grep '/$' | cut -d ' ' -f1)
root_uuid=$(lsblk -l -o NAME,UUID,TYPE,MOUNTPOINT | tr -s ' ' | grep '/$' | cut -d ' ' -f2)
root_type=$(lsblk -l -o NAME,UUID,TYPE,MOUNTPOINT | tr -s ' ' | grep '/$' | cut -d ' ' -f3)

# 清除之前的自定义启动条目
sed -i '3,$d' /etc/grub.d/40_custom

# 下载启动内核
cd /
curl -LO $vmlinuz
curl -LO $initrd
cd -

if [ -d /sys/firmware/efi ]; then
    action='efi'
else
    action='16'
fi

if [ $root_type == "lvm" ]; then
    cat <<EOF >>/etc/grub.d/40_custom
menuentry "reinstall" {
    insmod lvm
    insmod xfs
    set root=(lvm/$root_name)
    linux$action /vmlinuz root=live:$squashfs inst.ks=$ks
    initrd$action /initrd.img
    }
EOF

else
    cat <<EOF >>/etc/grub.d/40_custom
menuentry "reinstall" {
    insmod xfs
    search --no-floppy --fs-uuid --set=root $root_uuid
    linux$action /vmlinuz root=live:$squashfs inst.ks=$ks
    initrd$action /initrd.img
    }
EOF
fi

grub_cfg=$(find /boot -type f -name grub.cfg)
grub-mkconfig -o $grub_cfg || grub2-mkconfig -o $grub_cfg
grub-reboot reinstall || grub2-reboot reinstall
cat $grub_cfg
# reboot

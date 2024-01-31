#!/bin/bash

get_all_disks() {
    lsblk -rn --nodeps -o NAME,TYPE | grep 'disk$' | awk '{print $1}'
}

get_xda() {
    # 防止 $main_disk 为空
    if [ -z "$main_disk" ]; then
        return
    fi

    for disk in $(get_all_disks); do
        # shellcheck disable=SC2154
        if fdisk -l "/dev/$disk" | grep -iq "$main_disk"; then
            echo "$disk"
            break
        fi
    done
}

sed -i -E '/^\.{3}$/d' /autoinstall.yaml
echo 'storage:' >>/autoinstall.yaml

# 禁用 swap
cat <<EOF >>/autoinstall.yaml
  swap:
    size: 0
EOF

xda="$(get_xda)"

# 是用 size 寻找分区，number 没什么用
# https://curtin.readthedocs.io/en/latest/topics/storage.html
size_os=$(lsblk -bn -o SIZE /dev/disk/by-label/os)

if parted "/dev/$xda" print | grep '^Partition Table' | grep gpt; then
    # efi
    if [ -e /dev/disk/by-label/efi ]; then
        size_efi=$(lsblk -bn -o SIZE /dev/disk/by-label/efi)
        cat <<EOF >>/autoinstall.yaml
  config:
    # disk
    - ptable: gpt
      path: /dev/$xda
      preserve: true
      type: disk
      id: disk-xda
    # efi 分区
    - device: disk-xda
      size: $size_efi
      number: 1
      preserve: true
      grub_device: true
      type: partition
      id: partition-efi
    - fstype: fat32
      volume: partition-efi
      type: format
      id: format-efi
    # os 分区
    - device: disk-xda
      size: $size_os
      number: 2
      preserve: true
      type: partition
      id: partition-os
    - fstype: ext4
      volume: partition-os
      type: format
      id: format-os
    # mount
    - path: /
      device: format-os
      type: mount
      id: mount-os
    - path: /boot/efi
      device: format-efi
      type: mount
      id: mount-efi
EOF
    else
        # bios > 2t
        size_biosboot=$(parted "/dev/$xda" unit b print | grep bios_grub | awk '{print $4}' | sed 's/B$//')
        cat <<EOF >>/autoinstall.yaml
  config:
    # disk
    - ptable: gpt
      path: /dev/$xda
      preserve: true
      grub_device: true
      type: disk
      id: disk-xda
    # biosboot 分区
    - device: disk-xda
      size: $size_biosboot
      number: 1
      preserve: true
      type: partition
      id: partition-biosboot
    # os 分区
    - device: disk-xda
      size: $size_os
      number: 2
      preserve: true
      type: partition
      id: partition-os
    - fstype: ext4
      volume: partition-os
      type: format
      id: format-os
    # mount
    - path: /
      device: format-os
      type: mount
      id: mount-os
EOF
    fi
else
    # bios
    cat <<EOF >>/autoinstall.yaml
  config:
    # disk
    - ptable: msdos
      path: /dev/$xda
      preserve: true
      grub_device: true
      type: disk
      id: disk-xda
    # os 分区
    - device: disk-xda
      size: $size_os
      number: 1
      preserve: true
      type: partition
      id: partition-os
    - fstype: ext4
      volume: partition-os
      type: format
      id: format-os
    # mount
    - path: /
      device: format-os
      type: mount
      id: mount-os
EOF
fi
echo ... >>/autoinstall.yaml

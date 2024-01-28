# reinstall

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/dc679a17751448628fe6d8ac35e26eed)](https://app.codacy.com/gh/bin456789/reinstall/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![CodeFactor](https://www.codefactor.io/repository/github/bin456789/reinstall/badge)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://tokei.rs/b1/github/bin456789/reinstall?category=code&style=flat)](https://github.com/XAMPPRocky/tokei_rs)

One-click reinstallation script

[中文](README.md) | English

## Highlights

- By default, the official installation program is used. When the memory requirements of the installation program are not met, the official cloud image (Cloud Image) will be used.
- The script does not include third-party links or homemade packages; all resources are obtained in real-time from the source site.
- Compatible with 512M + 5G small servers and supports installing Alpine on 256M small servers.
- Supports installing Windows using the official ISO.
- Supports reinstalling Windows as Linux or Windows itself.
- Supports BIOS, EFI, ARM.
- The original system partition supports LVM, Btrfs.
- Supports installing Alpine, Arch, openSUSE, Gentoo, and can also install these systems from them.
- Progress of DD and cloud image installation can be viewed through SSH, browser, serial console, and background VNC.
- Includes many comments.

## Download (Current system is Linux)

For users outside China:

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
```

For users in China:

```bash
curl -O https://raw.fgit.cf/bin456789/reinstall/main/reinstall.sh
```

## Download (Current system is Windows)

[Unable to download?](#if-the-script-cannot-be-downloaded-under-windows)

Before proceeding, please disable the 'Real-time protection' feature in `Windows Defender`. This feature may prevent `certutil` from downloading any files.

For users outside China:

```batch
certutil -urlcache -f -split https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
```

For users in China:

```batch
certutil -urlcache -f -split https://raw.fgit.cf/bin456789/reinstall/main/reinstall.bat
```

## Usage

All features can be used on both Linux and Windows.

- on Linux, execute `bash reinstall.sh`
- on Windows, execute `reinstall.bat`

### Feature 1: Install Linux

- For machines with static IP, install CentOS, Alma, Rocky, Fedora, Debian, Ubuntu, and add the --ci parameter to force the use of the cloud image.

```bash
bash reinstall.sh centos   7|8|9  (8|9 for the stream version)
                  alma     8|9
                  rocky    8|9
                  fedora   38|39
                  debian   10|11|12
                  ubuntu   20.04|22.04
                  alpine   3.16|3.17|3.18|3.19
                  opensuse 15.5|tumbleweed (only supports cloud image)
                  arch     (only supports amd64 cloud image)
                  gentoo   (only supports amd64 cloud image)

                  If no version number is entered, the latest version will be installed.
```

Parameters:

```bash
--ci              Force the use of the cloud image
```

### Feature 2: DD

- Supports gzip, xz formats.

- For machines with static IP, DD Windows, and the script will automatically configure the IP.

```bash
bash reinstall.sh dd --img https://example.com/xxx.xz
```

### Feature 3: Reboot to Alpine Rescue System (Live OS)

- Can be connected via SSH to perform manual DD, modify partitions, manually install Arch / Gentoo, etc.

- If the disk content is not modified, rebooting again will return to the original system.

```bash
bash reinstall.sh alpine --hold=1
```

### Feature 4: Reboot to [netboot.xyz](https://netboot.xyz/)

- Can install more systems using background VNC.

```bash
bash reinstall.sh netboot.xyz
```

![netboot.xyz](https://netboot.xyz/images/netboot.xyz.gif)

### Feature 5: Install Windows ISO

```bash
bash reinstall.sh windows \
     --iso 'https://drive.massgrave.dev/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso' \
     --image-name 'Windows 10 Enterprise LTSC 2021'
```

![windows installer](https://filestore.community.support.microsoft.com/api/images/67c13a8c-cee6-47cd-ae80-a55923875c83)

Parameters:

`--iso` Original image link

`--image-name` Specify the image to install, case-insensitive, should be enclosed in quotes on both sides, for example:

```text
'Windows 7 Ultimate'
'Windows 10 Enterprise LTSC 2021'
'Windows 11 Pro'
'Windows Server 2022 SERVERDATACENTER'
```

Use `Dism++` File menu > Open Image File, select the iso to be installed to get the image name.

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

1. Supported systems:
   - Windows Vista to Windows 11
   - Windows Server 2008 to Windows Server 2022
   - Windows Server variants, such as
     - Windows Server Essentials
     - Windows Server Annual Channel
     - Hyper-V Server
     - Azure Stack HCI
2. The script will install the following drivers as needed:
    - KVM ([Virtio](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/))
    - XEN ([XEN PV](https://xenproject.org/windows-pv-drivers/), [AWS PV](https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/xen-drivers-overview.html))
    - AWS ([ENA Network Adapter](https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/enhanced-networking-ena.html), [NVMe Storage Controller](https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/aws-nvme-drivers.html))
    - GCP ([gVNIC Network Adapter](https://cloud.google.com/compute/docs/networking/using-gvnic), [GGA Graphics](https://cloud.google.com/compute/docs/instances/enable-instance-virtual-display))
    - Azure ([MANA Network Adapter](https://learn.microsoft.com/zh-cn/azure/virtual-network/accelerated-networking-mana-windows))
3. Vista (Server 2008) and 32-bit systems may lack drivers.
4. If the machine has a static IP, the IP will be automatically set after installation.
5. Can bypass Windows 11 hardware restrictions.
6. Supports Azure ARM (Hyper-V), does not support Oracle ARM (KVM).
7. The process `wsappx` will occupy CPU for a long time after installing the image `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso`.

   This is an issue with the image, and the solution is to install the `VCLibs` library.

   <https://www.google.com/search?q=ltsc+wsappx>

8. The following website provides iso links.

   <https://massgrave.dev/genuine-installation-media.html>

## Memory Requirements

| System                                | Traditional Installation | Cloud Image |
| ------------------------------------- | ------------------------ | ----------- |
| Debian                                | 384M                     | 512M        |
| Ubuntu                                | 1G                       | 512M        |
| CentOS / Alma / Rocky / Fedora        | 1G                       | 512M        |
| Alpine                                | 256M                     | -           |
| openSUSE                              | -                        | 512M        |
| Arch                                  | -                        | 512M        |
| Gentoo                                | -                        | 512M        |
| Windows 8.1 (Server 2012 R2) or below | 512M                     | -           |
| Windows 10 (Server 2016) or above     | 1G                       | -           |

## Network Requirements

Install Linux using the `Install Mode` must have DHCPv4.

Other cases support static IP, IPv6 (including installing Alpine, Linux cloud image, Windows iso, dd).

No need to fill in the static IP address when running the script.

## Virtualization Requirements

Not supported on OpenVZ, LXC virtual machines.

Please use <https://github.com/LloydAsp/OsMutation>.

## Default Passwords

| System        | Username       | Password       |
| ------------- | -------------- | -------------- |
| Linux         | root           | 123@@@         |
| Windows (iso) | administrator  | 123@@@         |
| Windows (dd)  | Image username | Image password |

## If the script cannot be downloaded under Windows

You can try the following methods:

1. Disable Windows Defender Real-time Protection.

2. For Windows 7, install this patch to enable TLS 1.2.

   <https://aka.ms/easyfix51044>

3. Update SSL root certificates.

   ```batch
   certutil -generateSSTFromWU root.sst
   certutil -addstore Root root.sst
   ```

4. Download manually by copying these two files through `Remote Desktop Connection`.

   <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat>

   <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh>

## TODO

- Install mode: Static IP, IPv6, multiple NICs

## Promotion

[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/7531e443-4069-4bf1-a40e-2e965f311e3f)](https://dartnode.com/)

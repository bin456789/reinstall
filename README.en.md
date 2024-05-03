# reinstall

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/dc679a17751448628fe6d8ac35e26eed)](https://app.codacy.com/gh/bin456789/reinstall/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![CodeFactor](https://www.codefactor.io/repository/github/bin456789/reinstall/badge)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://tokei.rs/b1/github/bin456789/reinstall?category=code&style=flat)](https://github.com/XAMPPRocky/tokei_rs)

One-click reinstallation script

[中文](README.md) | English

## Highlights

- Support arbitrary conversion between the following systems (including Windows to Linux).
- Compatible low-spec servers and automatically select the appropriate official slimmed-down kernel.
- Supports installing Windows using the official ISO.
- Automatically detect dynamic/static IPv4/IPv6, eliminating the need to fill in IP/mask/gateway (even for DD/ISO installation of Windows).
- Supports BIOS, EFI, ARM. The original system partition supports LVM, Btrfs.
- Progress of DD and cloud image installation can be viewed through SSH, HTTP port 80, serial console, and vendor backend VNC.
- The script does not include third-party homemade packages; all resources are obtained in real-time from the source site.
- Includes many comments.

## System Requirements

| Target System                                            | Memory    | Disk                   |
| -------------------------------------------------------- | --------- | ---------------------- |
| Alpine                                                   | 256 MB    | 1 GB                   |
| Debian / Kali                                            | 256 MB    | 1~1.5 GB ^             |
| Ubuntu                                                   | 512 MB \* | 2 GB                   |
| CentOS / Alma / Rocky                                    | 512 MB \* | 5 GB                   |
| Fedora                                                   | 512 MB \* | 5 GB                   |
| openSUSE                                                 | 512 MB \* | 5 GB                   |
| Arch                                                     | 512 MB    | 5 GB                   |
| Gentoo                                                   | 512 MB    | 5 GB                   |
| DD                                                       | 512 MB    | Depending on the image |
| Windows 8.1 (Server 2012 R2) or below (ISO installation) | 512 MB    | 20~25 GB               |
| Windows 10 (Server 2016) or above (ISO installation)     | 1G        | 20~25 GB               |

(\*) Indicates installation using cloud images

(^) indicates requiring either 256 MB memory + 1.5 GB disk, or 512 MB memory + 1 GB disk

## Download (Current system is Linux)

For users outside China:

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
```

For users in China:

```bash
curl -O https://mirror.ghproxy.com/https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
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
certutil -urlcache -f -split https://mirror.ghproxy.com/https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
```

## Usage

All features can be used on both Linux and Windows.

- on Linux, execute `bash reinstall.sh`
- on Windows, execute `reinstall.bat`

### Feature 1: Install Linux

- If no version number is entered, the latest version will be installed.
- When installing on a virtual machine, it will automatically select a slimmed-down kernel.

```bash
bash reinstall.sh centos   7|8|9  (8|9 for the stream version)
                  alma     8|9
                  rocky    8|9
                  fedora   38|39|40
                  debian   10|11|12
                  opensuse 15.5|tumbleweed
                  ubuntu   20.04|22.04|24.04
                  alpine   3.16|3.17|3.18|3.19
                  kali
                  arch
                  gentoo
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

### Feature 4: Reboot to netboot.xyz

- Can install [more systems](https://github.com/netbootxyz/netboot.xyz?tab=readme-ov-file#what-operating-systems-are-currently-available-on-netbootxyz) using vendor backend VNC.
- If the disk content is not modified, rebooting again will return to the original system.

```bash
bash reinstall.sh netboot.xyz
```

![netboot.xyz](https://netboot.xyz/images/netboot.xyz.gif)

### Feature 5: Install Windows ISO

- Pay attention to the quotation marks around the parameters
- Supports automatically searching for some ISO links. Need to set the language using `--lang`, default is `en-us`.

```bash
bash reinstall.sh windows \
     --image-name 'Windows 10 Enterprise LTSC 2021' \
     --lang zh-cn
```

- You can also specify an ISO link.

```bash
bash reinstall.sh windows \
     --image-name 'Windows 10 Enterprise LTSC 2021' \
     --iso 'https://drive.massgrave.dev/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso'
```

![Installing Windows](https://github.com/bin456789/reinstall/assets/7548515/07c1aea2-1ce3-4967-904f-aaf9d6eec3f7)

Parameters Description:

`--image-name` Specify the image to install, case-insensitive, Commonly used images include:

```text
Windows 7 Ultimate
Windows 10 Enterprise LTSC 2021
Windows 11 Pro
Windows Server 2022 SERVERDATACENTER
```

Use `Dism++` File menu > Open Image File, select the iso to be installed to get the image name.

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

1. Supported systems:
   - Windows Vista to 11
   - Windows Server 2008 to 2022, including the following variants
     - Windows Server Essentials
     - Windows Server Annual Channel
     - Hyper-V Server
     - Azure Stack HCI
2. The script will install the following drivers as needed:
   - KVM ([Virtio](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/))
   - XEN ([XEN](https://xenproject.org/windows-pv-drivers/), [Citrix](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/Upgrading_PV_drivers.html#win2008-citrix-upgrade), [AWS](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/xen-drivers-overview.html))
   - AWS ([ENA Network Adapter](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/enhanced-networking-ena.html), [NVMe Storage Controller](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/aws-nvme-drivers.html))
   - GCP ([gVNIC Network Adapter](https://cloud.google.com/compute/docs/networking/using-gvnic), [GGA Graphics](https://cloud.google.com/compute/docs/instances/enable-instance-virtual-display))
   - Azure ([MANA Network Adapter](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-windows))
3. Vista (Server 2008) and 32-bit systems may lack drivers.
4. For EFI machines without CSM enabled, Windows 7 (Server 2008 R2) cannot be installed.
5. If the machine has a static IP, the IP will be automatically set after installation.
6. Can bypass Windows 11 hardware restrictions.
7. Supports Windows 11 on ARM, exclusively for Hyper-V (Azure), not compatible with KVM (Oracle Cloud).
8. The process `wsappx` will occupy CPU for a long time after installing the image `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso`.

   This is an issue with the image, and the solution is to install the `VCLibs` library.

   <https://www.google.com/search?q=ltsc+wsappx>

9. The following website provides iso links.

   <https://massgrave.dev/genuine-installation-media.html> (Recommended, iso sourced from official channels, updated monthly, includes the latest patches)

   <https://www.microsoft.com/software-download/windows8>

   <https://www.microsoft.com/software-download/windows10> (Need to open it with a mobile User-Agent)

   <https://www.microsoft.com/software-download/windows11>

## Virtualization Requirements

Not supported on OpenVZ, LXC virtual machines.

Please use <https://github.com/LloydAsp/OsMutation>.

## Default Passwords

| System        | Username       | Password       |
| ------------- | -------------- | -------------- |
| Linux         | root           | 123@@@         |
| Windows (iso) | administrator  | 123@@@         |
| Windows (dd)  | Image username | Image password |

If encountering a password error during remote login to Windows, try using the username .\administrator.

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

## Thanks

Thanks to the following businesses for providing free servers.

[![Oracle Cloud](https://github.com/bin456789/reinstall/assets/7548515/8b430ed4-8344-4f96-b4da-c2bda031cc90)](https://www.oracle.com/cloud/)
[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/435d6740-bcdd-4f3a-a196-2f60ae397f17)](https://dartnode.com/)

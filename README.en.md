<!-- markdownlint-disable MD028 MD033 MD045 -->

# reinstall

[![Codacy](https://img.shields.io/codacy/grade/dc679a17751448628fe6d8ac35e26eed?logo=Codacy&label=Codacy)](https://app.codacy.com/gh/bin456789/reinstall/dashboard)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/bin456789/reinstall?logo=CodeFactor&logoColor=white&label=CodeFactor)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://aschey.tech/tokei/github/bin456789/reinstall?category=code&label=Lines%20of%20Code)](https://github.com/aschey/vercel-tokei)
<!-- [![Lines of Code](https://tokei.rs/b1/github/bin456789/reinstall?category=code&style=flat&label=Lines%20of%20Code)](https://github.com/XAMPPRocky/tokei_rs) -->

Reinstall server with one-click [中文](README.md)

## Highlights

- Support installation of 16 common Linux distributions.
- Support for installing Windows using the official original ISO. The script can automatically search for the ISO and drivers.
- Support reinstallation in any direction, meaning `Linux to Linux`, `Linux to Win`, `Win to Win`, `Win to Linux`.
- Specifically tailored for low-spec machines, addressing insufficient memory that prevents network installation.
- Automatically detect dynamic and static IPv4 / IPv6, eliminating the need to fill in IP / subnet mask / gateway.
- Support ARM, BIOS, EFI boot, with original system supporting LVM, BTRFS.
- No third-party custom packages included, all resources obtained in real-time from source sites.
- Includes many comments.

## System Requirements

| Target System                                                                                                                                                                                                                                              | Version                               | Memory    | Disk                   |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | --------- | ---------------------- |
| <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine                                                                                                                                                                    | 3.17, 3.18, 3.19, 3.20                | 256 MB    | 1 GB                   |
| <img width="16" height="16" src="https://www.debian.org/favicon.ico" /> Debian                                                                                                                                                                             | 9, 10, 11, 12                         | 256 MB    | 1 ~ 1.5 GB ^           |
| <img width="16" height="16" src="https://github.com/bin456789/reinstall/assets/7548515/f74b3d5b-085f-4df3-bcc9-8a9bd80bb16d" /> Kali                                                                                                                       | Rolling                               | 256 MB    | 1 ~ 1.5 GB ^           |
| <img width="16" height="16" src="https://netplan.readthedocs.io/en/latest/_static/favicon.png" /> Ubuntu                                                                                                                                                   | 20.04, 22.04, 24.04                   | 512 MB \* | 2 GB                   |
| <img width="16" height="16" src="https://www.centos.org/assets/img/favicon.png" /> CentOS                                                                                                                                                                  | 9                                     | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://img.alicdn.com/imgextra/i1/O1CN01oJnJZg1yK4RzI4Rx2_!!6000000006559-2-tps-118-118.png" /> Anolis                                                                                                                   | 7, 8                                  | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://www.redhat.com/favicon.ico" /> RedHat &nbsp; <img width="16" height="16" src="https://almalinux.org/fav/favicon.ico" /> Alma &nbsp; <img width="16" height="16" src="https://rockylinux.org/favicon.png" /> Rocky | 8, 9                                  | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://opencloudos.org/qq.ico" /> OpenCloudOS                                                                                                                                                                            | 8, 9                                  | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://www.oracle.com/asset/web/favicons/favicon-32.png" /> Oracle                                                                                                                                                       | 7, 8, 9                               | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://fedoraproject.org/favicon.ico" /> Fedora                                                                                                                                                                          | 39, 40                                | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://www.openeuler.org/favicon.ico" /> openEuler                                                                                                                                                                       | 20.03, 22.03, 24.03                   | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://static.opensuse.org/favicon.ico" /> openSUSE                                                                                                                                                                      | 15.5, 15.6, Tumbleweed (Rolling)      | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://archlinux.org/static/favicon.png" /> Arch                                                                                                                                                                         | Rolling                               | 512 MB    | 5 GB                   |
| <img width="16" height="16" src="https://www.gentoo.org/assets/img/logo/gentoo-g.png" /> Gentoo                                                                                                                                                            | Rolling                               | 512 MB    | 5 GB                   |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (DD)                                                                                                  | Any                                   | 512 MB    | Depending on the image |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO)                                                                                                 | Vista, 7, 8.x (Server 2008 ~ 2012 R2) | 512 MB    | 25 GB                  |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO)                                                                                                 | 10, 11 (Server 2016 ~ 2025)           | 1 GB      | 25 GB                  |

(\*) Indicates installation using cloud images, not traditional network installation.

(^) indicates requiring either 256 MB memory + 1.5 GB disk, or 512 MB memory + 1 GB disk

> [!WARNING]
> ❌ This script does not support OpenVZ or LXC virtual machines.
>
> Please use <https://github.com/LloydAsp/OsMutation> instead.

## System Accounts

| System                                                                                                                                                     | Username       | Password       |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | -------------- |
| <img width="16" height="16" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux                                                           | root           | 123@@@         |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO) | administrator  | 123@@@         |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (DD)  | Image username | Image password |

> [!TIP]
> If remote login to Windows fails, try using the username `.\administrator`.

## Download (Current system is <img width="20" height="20" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux)

For server outside China:

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
```

For server inside China:

```bash
curl -O https://jihulab.com/bin456789/reinstall/-/raw/main/reinstall.sh
```

## Download (Current system is <img width="20" height="20" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows)

> [!IMPORTANT]
> Before proceeding, please disable the 'Real-time protection' feature in `Windows Defender`. This feature may prevent `certutil` from downloading any files.

<details>

<summary>😢Still unable to download?</summary>

### Try the following methods

1. For Windows 7, install this patch to enable TLS 1.2.

   <https://aka.ms/easyfix51044>

2. Update SSL root certificates.

   ```batch
   certutil -generateSSTFromWU root.sst
   certutil -addstore Root root.sst
   ```

3. Download manually by copying these two files through `Remote Desktop Connection`.

   <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat>

   <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh>

</details>

For server outside China:

```batch
certutil -urlcache -f -split https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
```

For server inside China:

```batch
certutil -urlcache -f -split https://jihulab.com/bin456789/reinstall/-/raw/main/reinstall.bat
```

## Usage

> [!TIP]
> All features can be used on both Linux and Windows.
>
> on Linux, execute `bash reinstall.sh`
>
> on Windows, execute `reinstall.bat`

### Feature 1: Install <img width="16" height="16" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux

- If no version number is entered, the latest version will be installed.
- Does not include a boot partition (except for Fedora), nor a swap partition, maximizing disk space utilization.
- When installing on a virtual machine, it will automatically select a official limmed-down kernel.
- During the initial login, you may receive a password error prompt; just wait a moment and it should be resolved.

> [!TIP]
> When installing Debian / Kali, x86 architectures can monitor the installation progress through VNC in the background, while ARM architectures can use the serial console.
>
> When installing other systems, can monitor the progress through various methods (SSH, HTTP 80 port, VNC in the background, serial console).

> [!IMPORTANT]
> To install Red Hat, you need to provide the `qcow2` image link obtained from the following website.
>
> See <https://access.redhat.com/downloads/content/rhel>

```bash
bash reinstall.sh centos      9
                  anolis      7|8
                  alma        8|9
                  rocky       8|9
                  redhat      8|9   --img='http://xxx.qcow2'
                  opencloudos 8|9
                  oracle      7|8|9
                  fedora      39|40
                  debian      9|10|11|12
                  openeuler   20.03|22.03|24.03
                  ubuntu      20.04|22.04|24.04
                  alpine      3.17|3.18|3.19|3.20
                  opensuse    15.5|15.6|tumbleweed
                  kali
                  arch
                  gentoo
```

### Feature 2: DD

- Supports gzip, xz formats.
- A machine with a static IP running DD Windows will automatically configure the IP, which may take a few minutes to complete after the first boot.

> [!TIP]
> Can monitor the progress through various methods (SSH, HTTP 80 port, VNC in the background, serial console).

```bash
bash reinstall.sh dd --img https://example.com/xxx.xz
```

### Feature 3: Reboot to <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine Rescue System (Live OS)

- Can be connected via SSH to perform manual DD, modify partitions, manually install Arch / Gentoo, etc.
- If the disk content is not modified, rebooting again will return to the original system.

```bash
bash reinstall.sh alpine --hold=1
```

### Feature 4: Reboot to <img width="16" height="16" src="https://netboot.xyz/img/favicon.ico" /> netboot.xyz

- Can install [more systems](https://github.com/netbootxyz/netboot.xyz?tab=readme-ov-file#what-operating-systems-are-currently-available-on-netbootxyz) using vendor backend VNC.
- If the disk content is not modified, rebooting again will return to the original system.

```bash
bash reinstall.sh netboot.xyz
```

![netboot.xyz](https://netboot.xyz/images/netboot.xyz.gif)

### Feature 5: Install <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows ISO

- Can automatically searching for most iso links. Need to set the language using `--lang`, default is `en-us`.
- Machines with static IP addresses will have their IPs automatically configured after installation.
- Can bypass Windows 11 installation restrictions.

> [!TIP]
> The script uses <https://massgrave.dev/genuine-installation-media.html> as the ISO source. All ISOs provided are official originals.

> [!IMPORTANT]
> Note that parameters should be enclosed in quotation marks.

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

<details>

<summary>The following website provides iso links.</summary>

- Massgrave
  - <https://massgrave.dev/genuine-installation-media.html> (Recommended, iso sourced from official channels, updated monthly, includes the latest patches)
- Microsoft
  - <https://www.microsoft.com/software-download/windows8>
  - <https://www.microsoft.com/software-download/windows10> (Need to open it with a mobile User-Agent)
  - <https://www.microsoft.com/software-download/windows11>
  - <https://www.microsoft.com/software-download/windowsinsiderpreviewiso> (Preview)
  - <https://www.microsoft.com/evalcenter/download-windows-10-enterprise>
  - <https://www.microsoft.com/evalcenter/download-windows-11-enterprise>
  - <https://www.microsoft.com/evalcenter/download-windows-11-iot-enterprise-ltsc>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2012-r2>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2016>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2019>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2022>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2025>

</details>

![Installing Windows](https://github.com/bin456789/reinstall/assets/7548515/07c1aea2-1ce3-4967-904f-aaf9d6eec3f7)

#### Parameters Description

`--image-name` Specify the image to install, case-insensitive, Commonly used images include:

```text
Windows 7 Ultimate
Windows 10 Enterprise LTSC 2021
Windows 11 Pro
Windows Server 2022 SERVERDATACENTER
```

Use `Dism++` File menu > Open Image File, select the iso to be installed to get the image name.

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

#### Supported systems

- Windows (Vista ~ 11)
- Windows Server (2008 ~ 2025)
  - Windows Server Essentials \*
  - Windows Server (Semi) Annual Channel \*
  - Hyper-V Server \*
  - Azure Stack HCI \*

\* Must specify an ISO link.

#### The script will install the following drivers as needed

- KVM ([Virtio](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/))
- XEN ([XEN](https://xenproject.org/windows-pv-drivers/), [Citrix](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/Upgrading_PV_drivers.html#win2008-citrix-upgrade), [AWS](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/xen-drivers-overview.html))
- AWS ([ENA Network Adapter](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/enhanced-networking-ena.html), [NVMe Storage Controller](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/aws-nvme-drivers.html))
- GCP ([gVNIC Network Adapter](https://cloud.google.com/compute/docs/networking/using-gvnic), [GGA Graphics](https://cloud.google.com/compute/docs/instances/enable-instance-virtual-display))
- Azure ([MANA Network Adapter](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-windows))

> [!WARNING]
> Vista (Server 2008) and 32-bit systems may lack drivers.

> [!WARNING]
> For EFI machines without CSM enabled, Windows 7 (Server 2008 R2) cannot be installed.

> [!WARNING]
> Supports installation of Windows 11 on ARM machines, limited to Hyper-V (Azure) only, not supported on KVM (Oracle Cloud).

> [!WARNING]
> In the Chinese version of Windows 10 LTSC 2021 ISO `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso`, the `wsappx` process may indefinitely consume CPU resources.
>
> The solution is to update the system patches or manually install the `VCLibs` library <https://www.google.com/search?q=ltsc+wsappx>.

## How to Modify the Script

1. Fork this repository.
2. Modify the `confhome` at the beginning of `reinstall.sh` and `reinstall.bat`.
3. Make changes to the other code.

## Thanks

Thanks to the following businesses for providing free servers.

[![Oracle Cloud](https://github.com/bin456789/reinstall/assets/7548515/8b430ed4-8344-4f96-b4da-c2bda031cc90)](https://www.oracle.com/cloud/)
[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/435d6740-bcdd-4f3a-a196-2f60ae397f17)](https://dartnode.com/)

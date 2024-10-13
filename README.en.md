<!-- markdownlint-disable MD028 MD033 MD045 -->

# reinstall

[![Codacy](https://img.shields.io/codacy/grade/dc679a17751448628fe6d8ac35e26eed?logo=Codacy&label=Codacy&style=flat-square)](https://app.codacy.com/gh/bin456789/reinstall/dashboard)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/bin456789/reinstall?logo=CodeFactor&logoColor=white&label=CodeFactor&style=flat-square)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://aschey.tech/tokei/github/bin456789/reinstall?category=code&label=Lines%20of%20Code&style=flat-square)](https://github.com/aschey/vercel-tokei)
[![Telegram Group](https://img.shields.io/badge/Telegram-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/reinstall_os)
[![Github Sponsors](https://img.shields.io/badge/sponsor-30363D?style=flat-square&logo=GitHub-Sponsors&logoColor=#EA4AAA)](https://github.com/sponsors/bin456789)

One-Click Script to Reinstall System [中文](README.md)

![Sponsors](https://raw.githubusercontent.com/bin456789/sponsors/refs/heads/master/sponsors.svg)

## Highlights

- Supports installation of 17 common Linux distributions
- Supports installation of official Windows ISO, automatically finds ISO links, and integrates virtual machine drivers
- Supports installation in any direction, i.e., `Linux to Linux`, `Linux to Windows`, `Windows to Windows`, `Windows to Linux`
- No need to input IP parameters; automatically recognizes dynamic and static IPs, supports `/32`, `/128`, `gateway outside subnet`, `IPv6 only`, `dual NIC` and other special network configurations
- Specially optimized for low-spec servers, requires less memory than the official netboot
- Uses partition table ID to identify hard drives throughout the process, ensuring no wrong disk is written
- Supports BIOS and EFI boot, and ARM architecture
- No homemades image included, all resources are obtained in real-time from source sites
- Includes many comments.

## System Requirements

| Target System                                                                                                                                                                                                                                              | Version                               | Memory    | Disk                   |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | --------- | ---------------------- |
| <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine                                                                                                                                                                    | 3.17, 3.18, 3.19, 3.20                | 256 MB    | 1 GB                   |
| <img width="16" height="16" src="https://www.debian.org/favicon.ico" /> Debian                                                                                                                                                                             | 9, 10, 11, 12                         | 256 MB    | 1 ~ 1.5 GB ^           |
| <img width="16" height="16" src="https://github.com/bin456789/reinstall/assets/7548515/f74b3d5b-085f-4df3-bcc9-8a9bd80bb16d" /> Kali                                                                                                                       | Rolling                               | 256 MB    | 1 ~ 1.5 GB ^           |
| <img width="16" height="16" src="https://netplan.readthedocs.io/en/latest/_static/favicon.png" /> Ubuntu                                                                                                                                                   | 16.04, 18.04, 20.04, 22.04, 24.04     | 512 MB \* | 2 GB                   |
| <img width="16" height="16" src="https://www.centos.org/assets/img/favicon.png" /> CentOS                                                                                                                                                                  | 9                                     | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://img.alicdn.com/imgextra/i1/O1CN01oJnJZg1yK4RzI4Rx2_!!6000000006559-2-tps-118-118.png" /> Anolis                                                                                                                   | 7, 8                                  | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://www.redhat.com/favicon.ico" /> RedHat &nbsp; <img width="16" height="16" src="https://almalinux.org/fav/favicon.ico" /> Alma &nbsp; <img width="16" height="16" src="https://rockylinux.org/favicon.png" /> Rocky | 8, 9                                  | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://opencloudos.org/qq.ico" /> OpenCloudOS                                                                                                                                                                            | 8, 9                                  | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://www.oracle.com/asset/web/favicons/favicon-32.png" /> Oracle                                                                                                                                                       | 7, 8, 9                               | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://fedoraproject.org/favicon.ico" /> Fedora                                                                                                                                                                          | 39, 40                                | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://www.openeuler.org/favicon.ico" /> openEuler                                                                                                                                                                       | 20.03, 22.03, 24.03                   | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://static.opensuse.org/favicon.ico" /> openSUSE                                                                                                                                                                      | 15.5, 15.6, Tumbleweed (Rolling)      | 512 MB \* | 5 GB                   |
| <img width="16" height="16" src="https://nixos.org/_astro/flake-blue.Bf2X2kC4_Z1yqDoT.svg" /> NixOS                                                                                                                                                        | 24.05                                 | 512 MB    | 5 GB                   |
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

## Download (Current system is <img width="20" height="20" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux)

For server outside China:

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O reinstall.sh $_
```

For server inside China:

```bash
curl -O https://jihulab.com/bin456789/reinstall/-/raw/main/reinstall.sh || wget -O reinstall.sh $_
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

**All features** can be used on both Linux and Windows.

- on Linux, execute `bash reinstall.sh`
- on Windows, execute `reinstall.bat`

### Feature 1: Install <img width="16" height="16" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux

- If no version number is entered, the latest version will be installed.
- Does not include a boot partition (except for Fedora), nor a swap partition, maximizing disk space utilization.
- On virtual machines, the appropriate official slimmed-down kernel will be automatically installed.
- To install Red Hat, you need to provide the `qcow2` image link obtained from <https://access.redhat.com/downloads/content/rhel>.
- Username `root`, Default password `123@@@`. It may take a few minutes for the password to take effect on the first boot.
- After reinstalling, if you need to change SSH port or switch to key-based login, be sure to modify the files inside `/etc/ssh/sshd_config.d/`.
- Optional parameters:
  - `--password PASSWORD` Set password
  - `--ssh-port PORT` Change SSH port
  - `--hold 2` Prevent entering the system after installation. You can connect via SSH to modify system content, with the system mounted at `/os` (this feature is not supported on Debian/Kali).

```bash
bash reinstall.sh centos      9
                  anolis      7|8
                  alma        8|9
                  rocky       8|9
                  redhat      8|9   --img='http://xxx.com/xxx.qcow2'
                  opencloudos 8|9
                  oracle      7|8|9
                  fedora      39|40
                  nixos       24.05
                  debian      9|10|11|12
                  openeuler   20.03|22.03|24.03
                  alpine      3.17|3.18|3.19|3.20
                  opensuse    15.5|15.6|tumbleweed
                  ubuntu      16.04|18.04|20.04|22.04|24.04 [--minimal]
                  kali
                  arch
                  gentoo
```

> [!TIP]
> When installing Debian / Kali, x86 architectures can monitor the installation progress through VNC in the background, while ARM architectures can use the serial console.
>
> When installing other systems, can monitor the progress through various methods (SSH, HTTP 80 port, VNC in the background, serial console).
> Even if errors occur during the installation process, you can still install Alpine via SSH by running `xda=drive_name /trans.sh alpine`

<details>

<summary>Experimental Features</summary>

Install Debian using a cloud image, suitable for machines with slower CPUs

```bash
bash reinstall.sh debian --ci
```

Install CentOS, Alma, Rocky, Fedora using ISO, only supports machines with more than 2G of memory and dynamic IP.

Password `123@@@`, SSH Port `22`

Password and SSH port options are not supported.

```bash
bash reinstall.sh centos --installer
```

Install Ubuntu using ISO, only supports machines with more than 1G of memory and dynamic IP.

Password `123@@@`, SSH Port `22`

Password and SSH port options are not supported.

```bash
bash reinstall.sh ubuntu --installer
```

</details>

### Feature 2: DD

- Supports `raw`, `vhd` images or those compressed with `xz` or `gzip`.
- When deploy a Windows image, the system disk will be expanded, and machines with static IPs will have their IPs configured. However, it may take a few minutes after the first boot for the configuration to take effect.
- When deploy a Linux image, the script will not modify any contents of the image.
- Optional parameters:
  - `--rdp-port PORT` Change RDP port (Windows only).
  - `--allow-ping` Allow ping responses (Windows only).
  - `--hold 2` Prevent entering the system after DD completion. You can connect via SSH to modify system content, with the system mounted at `/os`.

```bash
bash reinstall.sh dd --img https://example.com/xxx.xz
```

> [!TIP]
> Can monitor the progress through various methods (SSH, HTTP 80 port, VNC in the background, serial console).
> Even if errors occur during the installation process, you can still install Alpine via SSH by running `xda=drive_name /trans.sh alpine`

### Feature 3: Reboot to <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine Rescue System (Live OS)

- You can use SSH to manually perform DD operations, modify partitions, and manually install Alpine, Arch, Gentoo, and other systems.
- Username `root`, Default password `123@@@`
- If the disk content is not modified, rebooting again will return to the original system.
- Optional parameters:
  - `--password PASSWORD` Set password

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

- Username `administrator`, Default password `123@@@`
- If remote login fails, try using the username `.\administrator`.
- The machine with a static IP will automatically configure the IP. It may take a few minutes to take effect on the first boot.
- Optional parameters:
  - `--password PASSWORD` Set Password
  - `--rdp-port PORT` Change RDP port
  - `--allow-ping` Allow ping responses
  - `--hold 2` Allow SSH connections for modifying the hard disk content before rebooting into the official Windows installation program, with the hard disk mounted at `/os`.

![Windows Installation](https://github.com/bin456789/reinstall/assets/7548515/07c1aea2-1ce3-4967-904f-aaf9d6eec3f7)

#### Method 1: Allow the script to automatically find the ISO

- The script will search for ISO files from <https://massgrave.dev/genuine-installation-media.html>. The ISOs provided on this site are all official versions.
- Only supports automatic detection of standard Windows and Windows Server versions.

```bash
bash reinstall.sh windows \
     --image-name 'Windows 11 Enterprise LTSC 2024' \
     --lang zh-cn
```

<details>
<summary>Supported languages</summary>

```text
ar-sa
bg-bg
cs-cz
da-dk
de-de
el-gr
en-gb
en-us
es-es
es-mx
et-ee
fi-fi
fr-ca
fr-fr
he-il
hr-hr
hu-hu
it-it
ja-jp
ko-kr
lt-lt
lv-lv
nb-no
nl-nl
pl-pl
pt-pt
pt-br
ro-ro
ru-ru
sk-sk
sl-si
sr-latn-rs
sv-se
th-th
tr-tr
uk-ua
zh-cn
zh-hk
zh-tw
```

</details>

#### Method 2: Specify the ISO link manually

- If you don’t know the `--image-name`, you can enter any value. After rebooting, connect via SSH and re-enter the correct value based on the error messages.

```bash
bash reinstall.sh windows \
     --image-name 'Windows 11 Enterprise LTSC 2024' \
     --iso 'https://drive.massgrave.dev/zh-cn_windows_11_enterprise_ltsc_2024_x64_dvd_cff9cd2d.iso'
```

> [!IMPORTANT]
> Note that parameters should be enclosed in quotation marks.

<details>

<summary>The following website provides iso links.</summary>

- <https://massgrave.dev/genuine-installation-media.html> (Recommended, iso sourced from official channels, updated monthly, includes the latest patches)
- <https://www.microsoft.com/software-download/windows10> (Need to open it with a non-Windows User-Agent)
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

#### Parameters Description

`--image-name` Specify the image to install, case-insensitive, Commonly used images include:

```text
Windows 7 Ultimate
Windows 11 Pro
Windows 11 Enterprise LTSC 2024
Windows Server 2025 SERVERDATACENTER
```

Open [DISM++](https://github.com/Chuyu-Team/Dism-Multi-language/releases) File menu > Open Image File, select the iso to be installed to get the image name (full system name), and all available image names are installable.

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

#### Supported systems

- Windows (Vista ~ 11)
- Windows Server (2008 ~ 2025)
  - Windows Server Essentials \*
  - Windows Server (Semi) Annual Channel \*
  - Hyper-V Server \*
  - Azure Stack HCI \*

With * indicating that an ISO link is required.

#### The script will install the following drivers as needed

- KVM ([Virtio](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/), [Alibaba Cloud](https://www.alibabacloud.com/help/ecs/user-guide/update-red-hat-virtio-drivers-of-windows-instances))
- XEN ([XEN](https://xenproject.org/windows-pv-drivers/), [Citrix](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Upgrading_PV_drivers.html#win2008-citrix-upgrade), [AWS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/xen-drivers-overview.html))
- AWS ([ENA Network Adapter](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ena-driver-releases-windows.html), [NVMe Storage Controller](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/nvme-driver-version-history.html))
- GCP ([gVNIC Network Adapter](https://cloud.google.com/compute/docs/networking/using-gvnic), [GGA Graphics](https://cloud.google.com/compute/docs/instances/enable-instance-virtual-display))
- Azure ([MANA Network Adapter](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-windows))

> [!WARNING]
> Vista (Server 2008) and 32-bit systems may lack drivers.

> [!WARNING]
> For EFI machines without CSM enabled, Windows 7 (Server 2008 R2) cannot be installed.
>
> Hyper-V (Azure) requires selecting the appropriate VM generation: <https://learn.microsoft.com/windows-server/virtualization/hyper-v/plan/should-i-create-a-generation-1-or-2-virtual-machine-in-hyper-v>

> [!WARNING]
> In the Chinese version of Windows 10 LTSC 2021 ISO `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso`, the `wsappx` process may indefinitely consume CPU resources.
>
> The solution is to update the system patches or manually install the `VCLibs` library <https://www.google.com/search?q=ltsc+wsappx>.

#### ARM Considerations

Most ARM machines support ISO installation of Windows 11 24H2, but some machines may experience a black screen during installation, which does not affect the installation process.

- ✔️Azure: B2pts_v2
- ✔️Alibaba Cloud: g8y, c8y, r8y (may occasionally get stuck on the boot logo during restart; force restart to resolve)
- ✔️Alibaba Cloud: g6r, c6r
- ✔️Oracle Cloud A1.Flex (Success depends on the machine's creation date; newer instances are more likely to install successfully. You will also need to manually load the GPU drivers after installation.)
- ✔️AWS: T4g
- ✔️Scaleway: COPARM1
- ✔️Gcore
- ❌Google Cloud: t2a (lacking network card driver)

<details>

<summary>Loading Graphics Driver on Oracle Cloud</summary>

No need to download the driver, just open Device Manager, find the graphics card, select 'Update driver', and choose `Red Hat VirtIO GPU DOD controller` from the list.

![virtio-gpu-1](https://github.com/user-attachments/assets/503e1d82-4fa9-4486-917e-73326ad7c988)
![virtio-gpu-2](https://github.com/user-attachments/assets/bf3a9af6-13d8-4f93-9d6c-d3b2dbddb37d)
![virtio-gpu-3](https://github.com/user-attachments/assets/a9006a78-838f-45bf-a556-2dba193d3c03)

</details>

## Discussion

[![GitHub Issues](https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)](https://github.com/bin456789/reinstall/issues)
[![Telegram Group](https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/reinstall_os)

## How to Modify the Script

1. Fork this repository.
2. Modify the `confhome` and `confhome_cn` at the beginning of `reinstall.sh` and `reinstall.bat`.
3. Make changes to the other code.

## Thanks

[![Github Sponsors](https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA)](https://github.com/sponsors/bin456789)

Thanks to the following businesses for providing free servers.

[![Oracle Cloud](https://github.com/bin456789/reinstall/assets/7548515/8b430ed4-8344-4f96-b4da-c2bda031cc90)](https://www.oracle.com/cloud/)
[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/435d6740-bcdd-4f3a-a196-2f60ae397f17)](https://dartnode.com/)

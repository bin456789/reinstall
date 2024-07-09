<!-- markdownlint-disable MD028 MD033 MD045 -->

# reinstall

[![Codacy](https://img.shields.io/codacy/grade/dc679a17751448628fe6d8ac35e26eed?logo=Codacy&label=Codacy)](https://app.codacy.com/gh/bin456789/reinstall/dashboard)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/bin456789/reinstall?logo=CodeFactor&logoColor=white&label=CodeFactor)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://aschey.tech/tokei/github/bin456789/reinstall?category=code&label=Lines%20of%20Code)](https://github.com/aschey/vercel-tokei)
<!-- [![Lines of Code](https://tokei.rs/b1/github/bin456789/reinstall?category=code&style=flat&label=Lines%20of%20Code)](https://github.com/XAMPPRocky/tokei_rs) -->

一键重装脚本 [English](README.en.md)

## 亮点

- 支持安装 16 种常见 Linux 发行版
- 支持用官方原版 iso 安装 Windows，并且脚本会自动查找 iso 和驱动
- 支持任意方向重装，也就是支持 `Linux to Linux`、`Linux to Win`、`Win to Win`、`Win to Linux`
- 专门适配低配小鸡，解决内存过少导致无法进行网络安装
- 自动判断动静态 IPv4 / IPv6，无需填写 IP / 掩码 / 网关
- 支持 ARM，支持 BIOS、EFI 引导，原系统支持 LVM、BTRFS
- 不含第三方自制包，所有资源均实时从源站点获得
- 有很多注释

## 配置要求

| 目标系统                                                                                                                                                                                                                                                                                                                                                               | 版本                                  | 内存      | 硬盘         |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | --------- | ------------ |
| <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine                                                                                                                                                                                                                                                                                | 3.17, 3.18, 3.19, 3.20                | 256 MB    | 1 GB         |
| <img width="16" height="16" src="https://www.debian.org/favicon.ico" /> Debian                                                                                                                                                                                                                                                                                         | 11, 12                                | 256 MB    | 1 ~ 1.5 GB ^ |
| <img width="16" height="16" src="https://github.com/bin456789/reinstall/assets/7548515/f74b3d5b-085f-4df3-bcc9-8a9bd80bb16d" /> Kali                                                                                                                                                                                                                                   | 滚动                                  | 256 MB    | 1 ~ 1.5 GB ^ |
| <img width="16" height="16" src="https://netplan.readthedocs.io/en/latest/_static/favicon.png" /> Ubuntu                                                                                                                                                                                                                                                               | 20.04, 22.04, 24.04                   | 512 MB \* | 2 GB         |
| <img width="16" height="16" src="https://www.centos.org/assets/img/favicon.png" /> CentOS                                                                                                                                                                                                                                                                              | 9                                     | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://img.alicdn.com/imgextra/i1/O1CN01oJnJZg1yK4RzI4Rx2_!!6000000006559-2-tps-118-118.png" /> Anolis OS                                                                                                                                                                                                                            | 7, 8                                  | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://www.redhat.com/favicon.ico" /> RedHat &nbsp; <img width="16" height="16" src="https://almalinux.org/fav/favicon.ico" /> Alma &nbsp; <img width="16" height="16" src="https://rockylinux.org/favicon.png" /> Rocky &nbsp; <img width="16" height="16" src="https://www.oracle.com/asset/web/favicons/favicon-32.png" /> Oracle | 8, 9                                  | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://opencloudos.org/qq.ico" /> OpenCloudOS                                                                                                                                                                                                                                                                                        | 8, 9                                  | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://fedoraproject.org/favicon.ico" /> Fedora                                                                                                                                                                                                                                                                                      | 39, 40                                | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://www.openeuler.org/favicon.ico" /> openEuler                                                                                                                                                                                                                                                                                   | 20.03, 22.03, 24.03                   | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://static.opensuse.org/favicon.ico" /> openSUSE                                                                                                                                                                                                                                                                                  | 15.5, 15.6, Tumbleweed (滚动)         | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://archlinux.org/static/favicon.png" /> Arch                                                                                                                                                                                                                                                                                     | 滚动                                  | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://www.gentoo.org/assets/img/logo/gentoo-g.png" /> Gentoo                                                                                                                                                                                                                                                                        | 滚动                                  | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (DD)                                                                                                                                                                                                              | 任何                                  | 512 MB    | 取决于镜像   |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO)                                                                                                                                                                                                             | Vista, 7, 8.x (Server 2008 ~ 2012 R2) | 512 MB    | 25 GB        |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO)                                                                                                                                                                                                             | 10, 11 (Server 2016 ~ 2025)           | 1 GB      | 25 GB        |

(\*) 表示使用云镜像安装，非传统网络安装

(^) 需要 256 MB 内存 + 1.5 GB 硬盘，或 512 MB 内存 + 1 GB 硬盘

> [!WARNING]
> ❌ 本脚本不支持 OpenVZ、LXC 虚拟机
>
> 请改用 <https://github.com/LloydAsp/OsMutation>

## 系统账号

| 系统                                                                                                                                                       | 用户名        | 密码     |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | -------- |
| <img width="16" height="16" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux                                                           | root          | 123@@@   |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO) | administrator | 123@@@   |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (DD)  | 镜像用户名    | 镜像密码 |

> [!TIP]
> 如果远程登录 Windows 失败，尝试使用用户名 `.\administrator`

## 下载（当前系统是 <img width="20" height="20" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux）

国外服务器：

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
```

国内服务器：

```bash
curl -O https://mirror.ghproxy.com/https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
```

## 下载（当前系统是 <img width="20" height="20" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows）

> [!IMPORTANT]
> 请先关闭 `Windows Defender` 的 `实时保护` 功能。该功能会阻止 `certutil` 下载任何文件。

<details>

<summary>😢还是无法下载？</summary>

### 可尝试以下几种方法

1. Windows 7 安装此补丁启用 TLS 1.2

   <https://aka.ms/easyfix51044>

2. 更新 SSL 根证书

   ```batch
   certutil -generateSSTFromWU root.sst
   certutil -addstore Root root.sst
   ```

3. 手动下载，通过 `远程桌面` 复制这两个文件

   <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat>

   <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh>

</details>

国外服务器：

```batch
certutil -urlcache -f -split https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
```

国内服务器：

```batch
certutil -urlcache -f -split https://mirror.ghproxy.com/https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
```

## 使用

> [!TIP]
> 所有功能均可在 Linux / Windows 下使用。
>
> Linux 下运行 `bash reinstall.sh`
>
> Windows 下运行 `reinstall.bat`

### 功能 1: 安装 <img width="16" height="16" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux

- 不输入版本号，则安装最新版
- 不含 boot 分区（Fedora 例外），不含 swap 分区，最大化利用磁盘空间
- 在虚拟机上，会自动安装官方精简内核

> [!TIP]
> 安装 Debian / Kali 时，x86 可通过后台 VNC 查看安装进度，ARM 可通过串行控制台查看安装进度。
>
> 安装其它系统时，可通过多种方式（SSH、HTTP 80 端口、后台 VNC、串行控制台）查看安装进度。

> [!IMPORTANT]
> 安装 Red Hat 需填写以下网站得到的 `qcow2` 镜像链接
>
> <https://access.redhat.com/downloads/content/rhel>

```bash
bash reinstall.sh centos      9
                  anolis      7|8
                  alma        8|9
                  rocky       8|9
                  oracle      8|9
                  redhat      8|9   --img='http://xxx.qcow2'
                  opencloudos 8|9
                  fedora      39|40
                  debian      11|12
                  openeuler   20.03|22.03|24.03
                  ubuntu      20.04|22.04|24.04
                  alpine      3.17|3.18|3.19|3.20
                  opensuse    15.5|15.6|tumbleweed
                  kali
                  arch
                  gentoo
```

### 功能 2: DD

- 支持 gzip、xz 格式
- 静态 IP 的机器 DD Windows，会自动配置好 IP，可能首次开机后几分钟才完成配置

> [!TIP]
> 可通过多种方式（SSH、HTTP 80 端口、后台 VNC、串行控制台）查看安装进度。

```bash
bash reinstall.sh dd --img https://example.com/xxx.xz
```

### 功能 3: 重启到 <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine 救援系统 (Live OS)

- 可用 ssh 连接，进行手动 DD、修改分区、手动安装 Arch / Gentoo 等操作
- 如果没有修改硬盘内容，再次重启将回到原系统

```bash
bash reinstall.sh alpine --hold=1
```

### 功能 4: 重启到 <img width="16" height="16" src="https://netboot.xyz/img/favicon.ico" /> netboot.xyz

- 可使用商家后台 VNC 安装 [更多系统](https://github.com/netbootxyz/netboot.xyz?tab=readme-ov-file#what-operating-systems-are-currently-available-on-netbootxyz)
- 如果没有修改硬盘内容，再次重启将回到原系统

```bash
bash reinstall.sh netboot.xyz
```

![netboot.xyz](https://netboot.xyz/images/netboot.xyz.gif)

### 功能 5: 安装 <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows ISO

- 支持自动查找大部分 iso 链接，需指定语言 `--lang`，默认 `en-us`
- 静态 IP 的机器，安装后会自动配置好 IP
- 能够绕过 Windows 11 安装限制

> [!TIP]
> 脚本以 <https://massgrave.dev/genuine-installation-media.html> 作为 iso 镜像查找源。所有 iso 都是官方原版。

> [!IMPORTANT]
> 注意参数两边有引号。

```bash
bash reinstall.sh windows \
     --image-name 'Windows 10 Enterprise LTSC 2021' \
     --lang zh-cn
```

- 也可以指定 iso 链接

```bash
bash reinstall.sh windows \
     --image-name 'Windows 10 Enterprise LTSC 2021' \
     --iso 'https://drive.massgrave.dev/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso'
```

<details>

<summary>以下网站可找到 iso 链接</summary>

- Massgrave
  - <https://massgrave.dev/genuine-installation-media.html> (推荐，iso 来自官方，每月更新，包含最新补丁)
- 微软
  - <https://www.microsoft.com/software-download/windows8>
  - <https://www.microsoft.com/software-download/windows10> (需用手机 User-Agent 打开)
  - <https://www.microsoft.com/software-download/windows11>
  - <https://www.microsoft.com/software-download/windowsinsiderpreviewiso> (预览版)
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

#### 参数说明

`--image-name` 指定要安装的映像，不区分大小写，常用映像有：

```text
Windows 7 Ultimate
Windows 10 Enterprise LTSC 2021
Windows 11 Pro
Windows Server 2022 SERVERDATACENTER
```

使用 `Dism++` 文件菜单 > 打开映像文件，选择要安装的 iso，可以得到映像名称

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

#### 支持的系统

- Windows (Vista ~ 11)
- Windows Server (2008 ~ 2025)
  - Windows Server Essentials \*
  - Windows Server (Semi) Annual Channel \*
  - Hyper-V Server \*
  - Azure Stack HCI \*

\* 需填写 iso 链接

#### 脚本会按需安装以下驱动

- KVM ([Virtio](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/))
- XEN ([XEN](https://xenproject.org/windows-pv-drivers/)、[Citrix](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/Upgrading_PV_drivers.html#win2008-citrix-upgrade)、[AWS](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/xen-drivers-overview.html))
- AWS ([ENA 网卡](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/enhanced-networking-ena.html)、[NVME 存储控制器](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/aws-nvme-drivers.html))
- GCP ([gVNIC 网卡](https://cloud.google.com/compute/docs/networking/using-gvnic)、[GGA 显卡](https://cloud.google.com/compute/docs/instances/enable-instance-virtual-display))
- Azure ([MANA 网卡](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-windows))

> [!WARNING]
> Vista (Server 2008) 和 32 位系统可能会缺少驱动

> [!WARNING]
> 未开启 CSM 的 EFI 机器，无法安装 Windows 7 (Server 2008 R2)

> [!WARNING]
> 支持 ARM 机器安装 Windows 11，仅限于 Hyper-V (Azure) ，不支持 KVM (甲骨文云)

> [!WARNING]
> Windows 10 LTSC 2021 中文版镜像 `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso` 的 `wsappx` 进程会长期占用 CPU
>
> 解决方法是更新系统补丁，或者手动安装 `VCLibs` 库 <https://www.google.com/search?q=ltsc+wsappx>

## 感谢

感谢以下商家提供白嫖机器

[![Oracle Cloud](https://github.com/bin456789/reinstall/assets/7548515/8b430ed4-8344-4f96-b4da-c2bda031cc90)](https://www.oracle.com/cloud/)
[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/435d6740-bcdd-4f3a-a196-2f60ae397f17)](https://dartnode.com/)

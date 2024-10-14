<!-- markdownlint-disable MD028 MD033 MD045 -->

# reinstall

[![Codacy](https://img.shields.io/codacy/grade/dc679a17751448628fe6d8ac35e26eed?logo=Codacy&label=Codacy&style=flat-square)](https://app.codacy.com/gh/bin456789/reinstall/dashboard)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/bin456789/reinstall?logo=CodeFactor&logoColor=white&label=CodeFactor&style=flat-square)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://aschey.tech/tokei/github/bin456789/reinstall?category=code&label=Lines%20of%20Code&style=flat-square)](https://github.com/aschey/vercel-tokei)
[![Telegram Group](https://img.shields.io/badge/Telegram-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/reinstall_os)
[![Github Sponsors](https://img.shields.io/badge/sponsor-30363D?style=flat-square&logo=GitHub-Sponsors&logoColor=#EA4AAA)](https://github.com/sponsors/bin456789)

一键重装脚本 [English](README.en.md)

![捐赠者](https://raw.githubusercontent.com/bin456789/sponsors/refs/heads/master/sponsors.svg)

## 亮点

- 支持安装 17 种常见 Linux 发行版
- 支持安装官方原版 Windows iso，自动查找 iso 链接、集成虚拟机驱动
- 支持任意方向重装，即 `Linux to Linux`、`Linux to Windows`、`Windows to Windows`、`Windows to Linux`
- 无需填写 IP 参数，自动识别动静态，支持 `/32`、`/128`、`网关不在子网范围内`、`纯 IPv6`、`双网卡` 等特殊网络
- 专门适配低配小鸡，比官方 netboot 需要更少的内存
- 全程用分区表 ID 识别硬盘，确保不会写错硬盘
- 支持 BIOS、EFI 引导，支持 ARM
- 不含自制包，所有资源均实时从源站点获得
- 有很多注释

## 配置要求

| 目标系统                                                                                                                                                                                                                                                   | 版本                                  | 内存      | 硬盘         |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | --------- | ------------ |
| <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine                                                                                                                                                                    | 3.17, 3.18, 3.19, 3.20                | 256 MB    | 1 GB         |
| <img width="16" height="16" src="https://www.debian.org/favicon.ico" /> Debian                                                                                                                                                                             | 9, 10, 11, 12                         | 256 MB    | 1 ~ 1.5 GB ^ |
| <img width="16" height="16" src="https://github.com/bin456789/reinstall/assets/7548515/f74b3d5b-085f-4df3-bcc9-8a9bd80bb16d" /> Kali                                                                                                                       | 滚动                                  | 256 MB    | 1 ~ 1.5 GB ^ |
| <img width="16" height="16" src="https://netplan.readthedocs.io/en/latest/_static/favicon.png" /> Ubuntu                                                                                                                                                   | 16.04, 18.04, 20.04, 22.04, 24.04     | 512 MB \* | 2 GB         |
| <img width="16" height="16" src="https://www.centos.org/assets/img/favicon.png" /> CentOS                                                                                                                                                                  | 9                                     | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://img.alicdn.com/imgextra/i1/O1CN01oJnJZg1yK4RzI4Rx2_!!6000000006559-2-tps-118-118.png" /> Anolis                                                                                                                   | 7, 8                                  | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://www.redhat.com/favicon.ico" /> RedHat &nbsp; <img width="16" height="16" src="https://almalinux.org/fav/favicon.ico" /> Alma &nbsp; <img width="16" height="16" src="https://rockylinux.org/favicon.png" /> Rocky | 8, 9                                  | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://opencloudos.org/qq.ico" /> OpenCloudOS                                                                                                                                                                            | 8, 9                                  | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://www.oracle.com/asset/web/favicons/favicon-32.png" /> Oracle                                                                                                                                                       | 7, 8, 9                               | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://fedoraproject.org/favicon.ico" /> Fedora                                                                                                                                                                          | 39, 40                                | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://www.openeuler.org/favicon.ico" /> openEuler                                                                                                                                                                       | 20.03, 22.03, 24.03                   | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://static.opensuse.org/favicon.ico" /> openSUSE                                                                                                                                                                      | 15.5, 15.6, Tumbleweed (滚动)         | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://nixos.org/_astro/flake-blue.Bf2X2kC4_Z1yqDoT.svg" /> NixOS                                                                                                                                                        | 24.05                                 | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://archlinux.org/static/favicon.png" /> Arch                                                                                                                                                                         | 滚动                                  | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://www.gentoo.org/assets/img/logo/gentoo-g.png" /> Gentoo                                                                                                                                                            | 滚动                                  | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (DD)                                                                                                  | 任何                                  | 512 MB    | 取决于镜像   |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO)                                                                                                 | Vista, 7, 8.x (Server 2008 ~ 2012 R2) | 512 MB    | 25 GB        |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO)                                                                                                 | 10, 11 (Server 2016 ~ 2025)           | 1 GB      | 25 GB        |

(\*) 表示使用云镜像安装，非传统网络安装

(^) 需要 256 MB 内存 + 1.5 GB 硬盘，或 512 MB 内存 + 1 GB 硬盘

> [!WARNING]
> ❌ 本脚本不支持 OpenVZ、LXC 虚拟机
>
> 请改用 <https://github.com/LloydAsp/OsMutation>

## 下载（当前系统是 <img width="20" height="20" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux）

国外服务器：

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O reinstall.sh $_
```

国内服务器：

```bash
curl -O https://jihulab.com/bin456789/reinstall/-/raw/main/reinstall.sh || wget -O reinstall.sh $_
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
certutil -urlcache -f -split https://jihulab.com/bin456789/reinstall/-/raw/main/reinstall.bat
```

## 使用

**所有功能** 都可在 Linux / Windows 下运行

- Linux 下运行 `bash reinstall.sh`
- Windows 下运行 `reinstall.bat`

### 功能 1: 安装 <img width="16" height="16" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux

- 不输入版本号，则安装最新版
- 不含 boot 分区（Fedora 例外），不含 swap 分区，最大化利用磁盘空间
- 在虚拟机上，会自动安装合适的官方精简内核
- 安装 Red Hat 需填写 <https://access.redhat.com/downloads/content/rhel> 得到的 `qcow2` 镜像链接
- 用户名 `root` 默认密码 `123@@@`，密码可能首次开机几分钟后才生效
- 重装后如需修改 SSH 端口 / 改成密钥登录，还要注意修改 `/etc/ssh/sshd_config.d/` 里面的文件
- 可选参数
  - `--password PASSWORD` 设置密码
  - `--ssh-port PORT` 修改 SSH 端口（目标系统 + 安装期间观察日志）
  - `--web-port PORT` 修改 Web 端口（安装期间观察日志）
  - `--hold 2`        安装结束后不进入系统。可连接 SSH 修改系统内容，系统挂载在 `/os` (此功能不支持 Debian / Kali)

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
> 安装 Debian / Kali 时，x86 可通过后台 VNC 查看安装进度，ARM 可通过串行控制台查看安装进度。
>
> 安装其它系统时，可通过多种方式（SSH、HTTP 80 端口、后台 VNC、串行控制台）查看安装进度。
> 即使安装过程出错，也能通过 SSH 运行 `xda=硬盘名 /trans.sh alpine` 安装 Alpine。

<details>

<summary>实验性功能</summary>

用云镜像安装 Debian，适合于 CPU 较慢的机器

```bash
bash reinstall.sh debian --ci
```

用 ISO 安装 CentOS, Alma, Rocky, Fedora ，仅支持内存大于 2G 且为动态 IP 的机器

密码 `123@@@`，SSH 端口 `22`

不支持设置密码、SSH 端口等选项

```bash
bash reinstall.sh centos --installer
```

用 ISO 安装 Ubuntu ，仅支持内存大于 1G 且为动态 IP 的机器

密码 `123@@@`，SSH 端口 `22`

不支持设置密码、SSH 端口等选项

```bash
bash reinstall.sh ubuntu --installer
```

</details>

### 功能 2: DD

- 支持 `raw` `vhd` 或者经过 `xz` `gzip` 压缩的镜像
- DD Windows 镜像时，会扩展系统盘，静态 IP 的机器会配置好 IP，可能首次开机几分钟后才生效
- DD Linux 镜像时，脚本不会修改镜像的任何内容
- 可选参数
  - `--allow-ping`    允许被 Ping (仅限 DD Windows)
  - `--rdp-port PORT` 修改 RDP 端口 (仅限 DD Windows)
  - `--ssh-port PORT` 修改 SSH 端口（安装期间观察日志）
  - `--web-port PORT` 修改 Web 端口（安装期间观察日志）
  - `--hold 2`        DD 结束后不进入系统。可连接 SSH 修改系统内容，系统挂载在 `/os`

```bash
bash reinstall.sh dd --img https://example.com/xxx.xz
```

> [!TIP]
> 可通过多种方式（SSH、HTTP 80 端口、后台 VNC、串行控制台）查看安装进度。
> 即使安装过程出错，也能通过 SSH 运行 `xda=硬盘名 /trans.sh alpine` 安装 Alpine。

### 功能 3: 重启到 <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine 救援系统 (Live OS)

- 可用 ssh 连接，进行手动 DD、修改分区、手动安装 Alpine / Arch / Gentoo 等操作
- 用户名 `root` 默认密码 `123@@@`
- 如果没有修改硬盘内容，再次重启将回到原系统
- 可选参数
  - `--password PASSWORD` 设置密码
  - `--ssh-port PORT` 修改 SSH 端口

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

- 用户名 `administrator` 默认密码 `123@@@`
- 如果远程登录失败，尝试使用用户名 `.\administrator`
- 静态机器会自动配置好 IP，可能首次开机几分钟后才生效
- 可选参数
  - `--password PASSWORD` 设置密码
  - `--allow-ping`    允许被 Ping
  - `--rdp-port PORT` 更改 RDP 端口
  - `--ssh-port PORT` 修改 SSH 端口（安装期间观察日志）
  - `--web-port PORT` 修改 Web 端口（安装期间观察日志）
  - `--hold 2`        在重启进入 Windows 官方安装程序前，可连接 SSH 修改硬盘内容，硬盘挂载在 `/os`

![Windows 安装界面](https://github.com/bin456789/reinstall/assets/7548515/07c1aea2-1ce3-4967-904f-aaf9d6eec3f7)

#### 方法 1: 让脚本自动查找 ISO

- 脚本会从 <https://massgrave.dev/genuine-installation-media.html> 查找 iso，该网站提供的 iso 都是官方原版
- 仅支持自动查找常规 Windows 和 Windows Server 版本

```bash
bash reinstall.sh windows \
     --image-name 'Windows 11 Enterprise LTSC 2024' \
     --lang zh-cn
```

<details>
<summary>支持的语言</summary>

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

#### 方法 2: 自行指定 ISO 连接

- 如果不知道 `--image-name`，可以随便填，重启后连接 SSH ，根据错误提示重新输入

```bash
bash reinstall.sh windows \
     --image-name 'Windows 11 Enterprise LTSC 2024' \
     --iso 'https://drive.massgrave.dev/zh-cn_windows_11_enterprise_ltsc_2024_x64_dvd_cff9cd2d.iso'
```

> [!IMPORTANT]
> 注意参数两边有引号。

<details>

<summary>以下网站可找到 iso 链接</summary>

- <https://massgrave.dev/genuine-installation-media.html> (推荐，iso 来自官方，每月更新，包含最新补丁)
- <https://www.microsoft.com/software-download/windows10> (需用非 Windows User-Agent 打开)
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

#### 参数说明

`--image-name` 指定要安装的映像，不区分大小写，常用映像有：

```text
Windows 7 Ultimate
Windows 11 Pro
Windows 11 Enterprise LTSC 2024
Windows Server 2025 SERVERDATACENTER
```

打开 [DISM++](https://github.com/Chuyu-Team/Dism-Multi-language/releases) 文件菜单 > 打开映像文件，选择要安装的 iso，可以得到映像名称（系统全名），所有映像名称都可安装

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

#### 支持的系统

- Windows (Vista ~ 11)
- Windows Server (2008 ~ 2025)
  - Windows Server Essentials \*
  - Windows Server (Semi) Annual Channel \*
  - Hyper-V Server \*
  - Azure Stack HCI \*

带 \* 表示需要填写 iso 链接

#### 脚本会按需安装以下驱动

- Virtio ([Virtio](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/)、[阿里云](https://www.alibabacloud.com/help/ecs/user-guide/update-red-hat-virtio-drivers-of-windows-instances))
- XEN ([XEN](https://xenproject.org/windows-pv-drivers/)、[Citrix](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Upgrading_PV_drivers.html#win2008-citrix-upgrade)、[AWS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/xen-drivers-overview.html))
- AWS ([ENA 网卡](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ena-driver-releases-windows.html)、[NVME 存储控制器](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/nvme-driver-version-history.html))
- GCP ([gVNIC 网卡](https://cloud.google.com/compute/docs/networking/using-gvnic)、[GGA 显卡](https://cloud.google.com/compute/docs/instances/enable-instance-virtual-display))
- Azure ([MANA 网卡](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-windows))
- Intel ([VMD 存储控制器](https://www.intel.com/content/www/us/en/download/720755/intel-rapid-storage-technology-driver-installation-software-with-intel-optane-memory-11th-up-to-13th-gen-platforms.html))

> [!WARNING]
> Vista (Server 2008) 和 32 位系统可能会缺少驱动

> [!WARNING]
> 未开启 CSM 的 EFI 机器，无法安装 Windows 7 (Server 2008 R2)
>
> Hyper-V (Azure) 需选择合适的虚拟机代系 <https://learn.microsoft.com/windows-server/virtualization/hyper-v/plan/should-i-create-a-generation-1-or-2-virtual-machine-in-hyper-v>

> [!WARNING]
> Windows 10 LTSC 2021 中文版镜像 `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso` 的 `wsappx` 进程会长期占用 CPU
>
> 解决方法是更新系统补丁，或者手动安装 `VCLibs` 库 <https://www.google.com/search?q=ltsc+wsappx>

#### ARM 注意事项

大部分 ARM 机器支持 ISO 安装 Windows 11 24H2

安装过程可能会黑屏，串行控制台可能会显示 `ConvertPages: failed to find range`，均不影响安装

- ✔️Azure     B2pts_v2
- ✔️阿里云    g8y c8y r8y (有几率重启时卡开机 Logo，强制重启即可)
- ✔️阿里云    g6r c6r
- ✔️甲骨文云  A1.Flex     (视乎机器的创建日期，越新的越有可能成功安装，安装后还需要手动加载显卡驱动)
- ✔️AWS       T4g
- ✔️Scaleway  COPARM1
- ✔️Gcore
- ❌谷歌云    t2a         (缺少网卡驱动)

<details>

<summary>甲骨文云加载显卡驱动</summary>

不需要下载驱动，只需打开设备管理器，找到显卡，选择更新驱动，在列表中选择 `Red Hat VirtIO GPU DOD controller`

![virtio-gpu-1](https://github.com/user-attachments/assets/503e1d82-4fa9-4486-917e-73326ad7c988)
![virtio-gpu-2](https://github.com/user-attachments/assets/bf3a9af6-13d8-4f93-9d6c-d3b2dbddb37d)
![virtio-gpu-3](https://github.com/user-attachments/assets/a9006a78-838f-45bf-a556-2dba193d3c03)

</details>

## 讨论

[![GitHub Issues](https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)](https://github.com/bin456789/reinstall/issues)
[![Telegram Group](https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/reinstall_os)

## 如何修改脚本

1. Fork 本仓库
2. 修改 `reinstall.sh` 和 `reinstall.bat` 开头的 `confhome` 和 `confhome_cn`
3. 修改其它代码

## 感谢

[![Github Sponsors](https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA)](https://github.com/sponsors/bin456789)

感谢以下商家提供白嫖机器

[![Oracle Cloud](https://github.com/bin456789/reinstall/assets/7548515/8b430ed4-8344-4f96-b4da-c2bda031cc90)](https://www.oracle.com/cloud/)
[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/435d6740-bcdd-4f3a-a196-2f60ae397f17)](https://dartnode.com/)

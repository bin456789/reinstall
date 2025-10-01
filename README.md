<!-- markdownlint-disable MD028 MD033 MD045 -->

# reinstall

[![Codacy](https://img.shields.io/codacy/grade/dc679a17751448628fe6d8ac35e26eed?logo=Codacy&label=Codacy&style=flat-square)](https://app.codacy.com/gh/bin456789/reinstall/dashboard)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/bin456789/reinstall?logo=CodeFactor&logoColor=white&label=CodeFactor&style=flat-square)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://tokei.rs/b1/github/bin456789/reinstall?category=code&label=Lines%20of%20Code&style=flat-square)](https://github.com/XAMPPRocky/tokei_rs)

一键 VPS 系统重装脚本 [English](README.en.md)

## 介绍

- 一键重装到 Linux，支持 19 种常见发行版
- 一键重装到 Windows，使用官方原版 ISO 而非自制镜像，脚本支持自动查找 ISO 链接、自动安装 `VirtIO` 等公有云驱动
- 支持任意方向重装，即 `Linux to Linux`、`Linux to Windows`、`Windows to Windows`、`Windows to Linux`
- 自动设置 IP，智能设置动静态，支持 `/32`、`/128`、`网关不在子网范围内`、`纯 IPv6`、`IPv4/IPv6 在不同的网卡`
- 专门适配低配小鸡，比官方 netboot 需要更少的内存
- 全程用分区表 ID 识别硬盘，确保不会写错硬盘
- 支持 BIOS、EFI 引导，支持 ARM 服务器
- 不含自制包，所有资源均实时从镜像源获得

如果帮到你，可以请我喝奶茶。
[![Donate](https://img.shields.io/badge/Donate-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA)](https://github.com/sponsors/bin456789)

[![Sponsors](https://raw.githubusercontent.com/bin456789/sponsors/refs/heads/master/sponsors.svg)](https://github.com/sponsors/bin456789)

### 反馈

[![GitHub Issues](https://img.shields.io/badge/GitHub-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)](https://github.com/bin456789/reinstall/issues)
[![Telegram Group](https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/reinstall_os)

## 快速开始

- [下载](#下载当前系统是--linux)
- [功能 1. 一键重装到 Linux](#功能-1-安装--linux)
- [功能 2. 一键 DD Raw 镜像到硬盘](#功能-2-dd-raw-镜像到硬盘)
- [功能 3. 一键引导到 Alpine Live OS 内存系统](#功能-3-重启到--alpine-live-os内存系统)
- [功能 4. 一键引导到 netboot.xyz](#功能-4-重启到--netbootxyz)
- [功能 5. 一键重装到 Windows](#功能-5-安装--windows-iso)

## 系统要求

原系统可以是表格中的任意系统

目标系统的配置要求如下：

| 系统                                                                                                                                                                                                                                                                                                                                                                   | 版本                                  | 内存      | 硬盘         |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | --------- | ------------ |
| <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine                                                                                                                                                                                                                                                                                | 3.19, 3.20, 3.21, 3.22                | 256 MB    | 1 GB         |
| <img width="16" height="16" src="https://www.debian.org/favicon.ico" /> Debian                                                                                                                                                                                                                                                                                         | 9, 10, 11, 12, 13                     | 256 MB    | 1 ~ 1.5 GB ^ |
| <img width="16" height="16" src="https://github.com/bin456789/reinstall/assets/7548515/f74b3d5b-085f-4df3-bcc9-8a9bd80bb16d" /> Kali                                                                                                                                                                                                                                   | 滚动                                  | 256 MB    | 1 ~ 1.5 GB ^ |
| <img width="16" height="16" src="https://documentation.ubuntu.com/server/_static/favicon.png" /> Ubuntu                                                                                                                                                                                                                                                                | 16.04 LTS - 24.04 LTS, 25.04          | 512 MB \* | 2 GB         |
| <img width="16" height="16" src="https://img.alicdn.com/imgextra/i1/O1CN01oJnJZg1yK4RzI4Rx2_!!6000000006559-2-tps-118-118.png" /> Anolis                                                                                                                                                                                                                               | 7, 8, 23                              | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://www.redhat.com/favicon.ico" /> RHEL &nbsp;<img width="16" height="16" src="https://almalinux.org/fav/favicon.ico" /> AlmaLinux &nbsp;<img width="16" height="16" src="https://rockylinux.org/favicon.png" /> Rocky &nbsp;<img width="16" height="16" src="https://www.oracle.com/asset/web/favicons/favicon-32.png" /> Oracle | 8, 9, 10                              | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://opencloudos.org/qq.ico" /> OpenCloudOS                                                                                                                                                                                                                                                                                        | 8, 9, Stream 23                       | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://www.centos.org/assets/icons/favicon.svg" /> CentOS Stream                                                                                                                                                                                                                                                                     | 9, 10                                 | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://fedoraproject.org/favicon.ico" /> Fedora                                                                                                                                                                                                                                                                                      | 41, 42                                | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://www.openeuler.org/favicon.ico" /> openEuler                                                                                                                                                                                                                                                                                   | 20.03 LTS - 24.03 LTS, 25.09          | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://static.opensuse.org/favicon.ico" /> openSUSE                                                                                                                                                                                                                                                                                  | Leap 15.6, Tumbleweed (滚动)          | 512 MB \* | 5 GB         |
| <img width="16" height="16" src="https://nixos.org/favicon.svg" /> NixOS                                                                                                                                                                                                                                                                                               | 25.05                                 | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://archlinux.org/static/favicon.png" /> Arch                                                                                                                                                                                                                                                                                     | 滚动                                  | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://www.gentoo.org/assets/img/logo/gentoo-g.png" /> Gentoo                                                                                                                                                                                                                                                                        | 滚动                                  | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://aosc.io/assets/distros/aosc-os.svg" /> 安同 OS                                                                                                                                                                                                                                                                                | 滚动                                  | 512 MB    | 5 GB         |
| <img width="16" height="16" src="https://www.fnnas.com/favicon.ico" /> 飞牛 fnOS                                                                                                                                                                                                                                                                                       | 公测                                  | 512 MB    | 8 GB         |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (DD)                                                                                                                                                                                                              | 任何                                  | 512 MB    | 取决于镜像   |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO)                                                                                                                                                                                                             | Vista, 7, 8.x (Server 2008 - 2012 R2) | 512 MB    | 25 GB        |
| <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows (ISO)                                                                                                                                                                                                             | 10, 11 (Server 2016 - 2025)           | 1 GB      | 25 GB        |

\* 表示使用云镜像安装，非传统网络安装

^ 表示需要 256 MB 内存 + 1.5 GB 硬盘，或 512 MB 内存 + 1 GB 硬盘

> [!WARNING]
>
> 本脚本理论上支持独服和 PC
>
> 但如果能使用 IPMI 或 U 盘，则不建议使用本脚本

> [!WARNING]
>
> ❌ 本脚本不支持 OpenVZ、LXC 虚拟机
>
> 请改用 <https://github.com/LloydAsp/OsMutation>

## 下载（当前系统是 <img width="20" height="20" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux）

国外服务器：

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_
```

国内服务器：

```bash
curl -O https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh || wget -O ${_##*/} $_
```

## 下载（当前系统是 <img width="20" height="20" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows）

> [!IMPORTANT]
> 请先关闭 `Windows Defender` 的 `实时保护` 功能。该功能会阻止 `certutil` 下载任何文件。

<details>

<summary>解决 Windows 7 下无法下载脚本</summary>

由于不支持 TLS 1.2、SHA-256、根证书没有更新等原因，Vista，7 和 Server 2008 (R2) 可能无法自动下载脚本，因此需要手动下载，具体操作如下：

用 IE 下载 (先在 IE 高级设置里启用 TLS 1.2)，或者通过远程桌面，将这两个文件保存到同一个目录

- <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat>

- <https://www.cygwin.com/setup-x86.exe>

使用时运行下载的 `reinstall.bat`

</details>

国外服务器：

```batch
certutil -urlcache -f -split https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
```

国内服务器：

```batch
certutil -urlcache -f -split https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.bat
```

## 使用

**所有功能** 都可在 Linux / Windows 下运行

- Linux 下运行 `bash reinstall.sh ...`
- Windows 下先运行 `cmd`，再运行 `reinstall.bat ...`
  - 如果参数中的链接包含特殊字符，要用 `""` 将链接包裹起来，不能用 `''`

### 功能 1: 安装 <img width="16" height="16" src="https://www.kernel.org/theme/images/logos/favicon.png" /> Linux

> [!CAUTION]
>
> 此功能会清除当前系统**整个硬盘**的全部数据（包含其它分区）！
>
> 数据无价，请三思而后行！

- 用户名 `root` 默认密码 `123@@@`
- 安装最新版可不输入版本号
- 最大化利用磁盘空间：不含 boot 分区（Fedora 例外），不含 swap 分区
- 自动根据机器类型选择不同的优化内核，例如 `Cloud`、`HWE` 内核
- 安装 Red Hat 时需填写 <https://access.redhat.com/downloads/content/rhel> 得到的 `qcow2` 镜像链接，也可以安装其它类 RHEL 系统，例如 `Alibaba Cloud Linux` 和 `TencentOS Server`
- 重装后如需修改 SSH 端口或者改成密钥登录，注意还要修改 `/etc/ssh/sshd_config.d/` 里面的文件

```bash
bash reinstall.sh anolis      7|8|23
                  rocky       8|9|10
                  oracle      8|9|10
                  almalinux   8|9|10
                  opencloudos 8|9|23
                  centos      9|10
                  fedora      41|42
                  nixos       25.05
                  debian      9|10|11|12|13
                  opensuse    15.6|tumbleweed
                  alpine      3.19|3.20|3.21|3.22
                  openeuler   20.03|22.03|24.03|25.09
                  ubuntu      16.04|18.04|20.04|22.04|24.04|25.04 [--minimal]
                  kali
                  arch
                  gentoo
                  aosc
                  fnos
                  redhat      --img="http://access.cdn.redhat.com/xxx.qcow2"
```

#### 可选参数

- `--password PASSWORD` 设置密码
- `--ssh-key KEY` 设置 SSH 登录公钥，[格式如下](#--ssh-key)。当使用公钥时，密码为空
- `--ssh-port PORT` 修改 SSH 端口（安装期间观察日志用，也作用于新系统）
- `--web-port PORT` 修改 Web 端口（安装期间观察日志用）
- `--frpc-toml /path/to/frpc.toml` 添加 frpc 内网穿透
- `--hold 2` 安装结束后不重启，此时可以 SSH 登录修改系统内容，系统挂载在 `/os` (此功能不支持 Debian/Kali)

> [!TIP]
> 安装 Debian/Kali 时，x86 可通过商家后台 VNC 查看安装进度，ARM 可通过串行控制台查看安装进度。
>
> 安装其它系统时，可通过多种方式（SSH、HTTP 80 端口、商家后台 VNC、串行控制台）查看安装进度。
> <br />即使安装过程出错，也能通过 SSH 运行 `/trans.sh alpine` 安装到 Alpine。

<details>

<summary>实验性功能</summary>

云镜像安装 Debian

- 适合于 CPU 较慢的机器

```bash
bash reinstall.sh debian --ci
```

ISO 安装 CentOS, AlmaLinux, Rocky, Fedora

- 仅支持内存大于 2G 且为动态 IP 的机器
- 密码 `123@@@`，SSH 端口 `22`，不支持用参数修改

```bash
bash reinstall.sh centos --installer
```

ISO 安装 Ubuntu

- 仅支持内存大于 1G 且为动态 IP 的机器
- 密码 `123@@@`，SSH 端口 `22`，不支持用参数修改

```bash
bash reinstall.sh ubuntu --installer
```

</details>

### 功能 2: DD RAW 镜像到硬盘

> [!CAUTION]
>
> 此功能会清除当前系统**整个硬盘**的全部数据（包含其它分区）！
>
> 数据无价，请三思而后行！

- 支持 `raw` `vhd` 格式的镜像（未压缩，或者压缩成 `.gz` `.xz` `.zst` `.tar` `.tar.gz` `.tar.xz` `.tar.zst`）
- DD Windows 镜像时，会自动扩展系统盘，静态 IP 的机器会配置好 IP，可能首次开机几分钟后才生效
- DD Linux 镜像时，**不会**修改镜像的任何内容

```bash
bash reinstall.sh dd --img "https://example.com/xxx.xz"
```

#### 可选参数

- `--allow-ping` 设置 Windows 防火墙允许被 Ping (仅限 DD Windows)
- `--rdp-port PORT` 修改 RDP 端口 (仅限 DD Windows)
- `--ssh-port PORT` 修改 SSH 端口（安装期间观察日志用）
- `--web-port PORT` 修改 Web 端口（安装期间观察日志用）
- `--frpc-toml /path/to/frpc.toml` 添加 frpc 内网穿透（仅限 DD Windows）
- `--hold 2` DD 结束后不重启，此时可以 SSH 登录修改系统内容，Windows 系统会挂载在 `/os`，Linux 系统**不会**自动挂载

> [!TIP]
> 可通过多种方式（SSH、HTTP 80 端口、商家后台 VNC、串行控制台）查看安装进度。
> <br />即使安装过程出错，也能通过 SSH 运行 `/trans.sh alpine` 安装到 Alpine。

### 功能 3: 重启到 <img width="16" height="16" src="https://www.alpinelinux.org/alpine-logo.ico" /> Alpine Live OS（内存系统）

- 可用 ssh 连接，进行备份/恢复硬盘、手动 DD、修改分区、手动安装 Alpine 等操作
- 用户名 `root` 默认密码 `123@@@`

> [!TIP]
>
> 虽然运行的脚本叫 `reinstall`，但是此功能**不会**删除任何数据和进行自动重装，而是要用户手动操作
>
> 如果用户手动操作没有破坏原系统，再次重启将回到原系统

```bash
bash reinstall.sh alpine --hold=1
```

#### 可选参数

- `--password PASSWORD` 设置密码
- `--ssh-port PORT` 修改 SSH 端口
- `--ssh-key KEY` 设置 SSH 登录公钥，[格式如下](#--ssh-key)。当使用公钥时，密码为空
- `--frpc-toml /path/to/frpc.toml` 添加 frpc 内网穿透

### 功能 4: 重启到 <img width="16" height="16" src="https://netboot.xyz/img/favicon.ico" /> netboot.xyz

- 可使用商家后台 VNC 手动安装 [更多系统](https://github.com/netbootxyz/netboot.xyz?tab=readme-ov-file#what-operating-systems-are-currently-available-on-netbootxyz)

> [!TIP]
>
> 虽然运行的脚本叫 `reinstall`，但是此功能**不会**删除任何数据和进行自动重装，而是要用户手动操作
>
> 如果用户手动操作没有破坏原系统，再次重启将回到原系统

```bash
bash reinstall.sh netboot.xyz
```

![netboot.xyz](https://netboot.xyz/images/netboot.xyz.gif)

### 功能 5: 安装 <img width="16" height="16" src="https://blogs.windows.com/wp-content/uploads/prod/2022/09/cropped-Windows11IconTransparent512-32x32.png" /> Windows ISO

![Windows 安装界面](https://github.com/bin456789/reinstall/assets/7548515/07c1aea2-1ce3-4967-904f-aaf9d6eec3f7)

> [!CAUTION]
>
> 此功能会清除当前系统**整个硬盘**的全部数据（包含其它分区）！
>
> 数据无价，请三思而后行！

- 用户名 `administrator` 默认密码 `123@@@`
- 如果远程登录失败，可以尝试使用用户名 `.\administrator`
- 静态机器会自动配置好 IP，可能首次开机几分钟后才生效
- 支持所有语言

#### 支持的系统

- Windows (Vista ~ 11)
- Windows Server (2008 ~ 2025)
  - Windows Server Essentials \*
  - Windows Server (Semi) Annual Channel \*
  - Hyper-V Server \*
  - Azure Local (Azure Stack HCI) \*

#### 方法 1: 让脚本自动查找 ISO

- 脚本会从 <https://massgrave.dev/genuine-installation-media> 查找 ISO，该网站专门提供官方 ISO 下载
- 上面带 \* 的系统不支持自动查找 ISO

```bash
bash reinstall.sh windows \
     --image-name "Windows 11 Enterprise LTSC 2024" \
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

- 如果不知道 `--image-name`，可以随便填，在重启后连接 SSH，根据错误提示重新输入正确的值

```bash
bash reinstall.sh windows \
     --image-name "Windows 11 Enterprise LTSC 2024 Evaluation" \
     --iso "https://go.microsoft.com/fwlink/?linkid=2289029"
```

或者磁力链接

```bash
bash reinstall.sh windows \
     --image-name "Windows 11 Enterprise LTSC 2024" \
     --iso "magnet:?xt=urn:btih:7352bd2db48c3381dffa783763dc75aa4a6f1cff"
```

<details>

<summary>以下网站可找到 ISO 链接</summary>

- 正式版
  - <https://msdl.gravesoft.dev>
  - <https://massgrave.dev/genuine-installation-media>
  - <https://next.itellyou.cn>
  - <https://www.xitongku.com>
  - <https://www.microsoft.com/software-download/windows10> (需用非 Windows User-Agent 打开)
  - <https://www.microsoft.com/software-download/windows11>
  - <https://www.microsoft.com/software-download/windows11arm64>
- 评估版
  - <https://www.microsoft.com/evalcenter/download-windows-10-enterprise>
  - <https://www.microsoft.com/evalcenter/download-windows-11-enterprise>
  - <https://www.microsoft.com/evalcenter/download-windows-11-iot-enterprise-ltsc-eval>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2012-r2>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2016>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2019>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2022>
  - <https://www.microsoft.com/evalcenter/download-windows-server-2025>
- Insider 预览版
  - <https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewiso>
  - <https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewserver>

</details>

#### 可选参数

- `--password PASSWORD` 设置密码
- `--allow-ping` 设置 Windows 防火墙允许被 Ping
- `--rdp-port PORT` 更改 RDP 端口
- `--ssh-port PORT` 修改 SSH 端口（仅安装期间观察日志用）
- `--web-port PORT` 修改 Web 端口（仅安装期间观察日志用）
- `--add-driver INF_OR_DIR` 添加额外驱动，填写 .inf 路径，或者 .inf 所在的文件夹
  - 需先下载驱动到当前系统
  - 可多次设置该参数以添加不同的驱动
- `--frpc-toml /path/to/frpc.toml` 添加 frpc 内网穿透
- `--hold 2` 在进入 Windows 官方安装程序之前，可以 SSH 登录修改硬盘内容，硬盘挂载在 `/os`

#### 以下驱动会自动按需下载安装，无需手动添加

- VirtIO ([社区版][virtio-virtio], [阿里云][virtio-aliyun], [腾讯云][virtio-qcloud], [GCP][virtio-gcp])
- XEN ([~~社区版~~][xen-xen] (未签名), [Citrix][xen-citrix], [AWS][xen-aws])
- AWS ([ENA 网卡][aws-ena], [NVME 存储控制器][aws-nvme])
- GCP ([gVNIC 网卡][gcp-gvnic], [GGA 显卡][gcp-gga])
- Azure ([MANA 网卡][azure-mana])
- Intel ([VMD 存储控制器][intel-vmd], 网卡: [7][intel-nic-7], [8][intel-nic-8], [8.1][intel-nic-8.1], [10][intel-nic-10], [11][intel-nic-11], [2008 R2][intel-nic-2008-r2], [2012][intel-nic-2012], [2012 R2][intel-nic-2012-r2], [2016][intel-nic-2016], [2019][intel-nic-2019], [2022][intel-nic-2022], [2025][intel-nic-2025])

[virtio-virtio]: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/
[virtio-aliyun]: https://www.alibabacloud.com/help/ecs/user-guide/install-the-virtio-driver-1
[virtio-qcloud]: https://cloud.tencent.com/document/product/213/17815#b84b2032-752c-43c4-a509-73530b8f82ff
[virtio-gcp]: https://console.cloud.google.com/storage/browser/gce-windows-drivers-public
[xen-xen]: https://xenproject.org/resources/downloads/
[xen-aws]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/xen-drivers-overview.html
[xen-citrix]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Upgrading_PV_drivers.html#win2008-citrix-upgrade
[aws-ena]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ena-driver-releases-windows.html
[aws-nvme]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/nvme-driver-version-history.html
[gcp-gvnic]: https://cloud.google.com/compute/docs/networking/using-gvnic
[gcp-gga]: https://cloud.google.com/compute/docs/instances/enable-instance-virtual-display
[azure-mana]: https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-windows
[intel-vmd]: https://www.intel.com/content/www/us/en/download/849936/intel-rapid-storage-technology-driver-installation-software-with-intel-optane-memory-12th-to-15th-gen-platforms.html
[intel-nic-7]: https://www.intel.com/content/www/us/en/download/15590/intel-network-adapter-driver-for-windows-7-final-release.html
[intel-nic-8]: https://web.archive.org/web/20250501043104/https://www.intel.com/content/www/us/en/download/16765/intel-network-adapter-driver-for-windows-8-final-release.html
[intel-nic-8.1]: https://www.intel.com/content/www/us/en/download/17479/intel-network-adapter-driver-for-windows-8-1.html
[intel-nic-10]: https://www.intel.com/content/www/us/en/download/18293/intel-network-adapter-driver-for-windows-10.html
[intel-nic-11]: https://www.intel.com/content/www/us/en/download/727998/intel-network-adapter-driver-for-microsoft-windows-11.html
[intel-nic-2008-r2]: https://web.archive.org/web/20250501002542/https://www.intel.com/content/www/us/en/download/15591/intel-network-adapter-driver-for-windows-server-2008-r2-final-release.html
[intel-nic-2012]: https://www.intel.com/content/www/us/en/download/16789/intel-network-adapter-driver-for-windows-server-2012.html
[intel-nic-2012-r2]: https://www.intel.com/content/www/us/en/download/17480/intel-network-adapter-driver-for-windows-server-2012-r2.html
[intel-nic-2016]: https://www.intel.com/content/www/us/en/download/18737/intel-network-adapter-driver-for-windows-server-2016.html
[intel-nic-2019]: https://www.intel.com/content/www/us/en/download/19372/intel-network-adapter-driver-for-windows-server-2019.html
[intel-nic-2022]: https://www.intel.com/content/www/us/en/download/706171/intel-network-adapter-driver-for-windows-server-2022.html
[intel-nic-2025]: https://www.intel.com/content/www/us/en/download/838943/intel-network-adapter-driver-for-windows-server-2025.html

#### 如何填写映像名称 `--image-name`

一个 ISO 通常包含多个系统版本，例如家庭版、专业版。因此需要用 `--image-name` 指定要安装的系统版本（映像名称），不区分大小写

可以用 DISM、DISM++、Wimlib 等工具查询 ISO 包含的映像名称

常用的映像名称有：

```text
Windows 7 Ultimate
Windows 11 Pro
Windows 11 Enterprise LTSC 2024
Windows Server 2025 SERVERDATACENTER
```

#### 如何用 [DISM++](https://github.com/Chuyu-Team/Dism-Multi-language/releases) 查询 ISO 包含的映像名称

打开文件菜单 > 打开映像文件，选择要安装的 iso，即可得到映像名称，所有映像名称都可以安装

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

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

#### ARM 安装 Windows 的注意事项

大部分 ARM 机器都支持安装最新版 Windows 11

安装过程可能会黑屏，串行控制台可能会显示 `ConvertPages: failed to find range`，均不影响正常安装

| 兼容性 | 云服务商 | 实例类型      | 问题                                                                         |
| ------ | -------- | ------------- | ---------------------------------------------------------------------------- |
| ✔️     | Azure    | B2pts_v2      |                                                                              |
| ✔️     | 阿里云   | g6r, c6r      |                                                                              |
| ✔️     | 阿里云   | g8y, c8y, r8y | 有几率重启时卡开机 Logo，强制重启即可                                        |
| ✔️     | AWS      | T4g           |                                                                              |
| ✔️     | Scaleway | COPARM1       |                                                                              |
| ✔️     | Gcore    |               |                                                                              |
| ❔     | 甲骨文云 | A1.Flex       | 不一定能安装成功，越新创建的实例越容易成功<br />安装后还需要手动加载显卡驱动 |
| ❌     | 谷歌云   | t2a           | 缺少网卡驱动                                                                 |

<details>

<summary>甲骨文云加载显卡驱动</summary>

使用远程桌面登录到服务器，打开设备管理器，找到显卡，选择更新驱动，在列表中选择 `Red Hat VirtIO GPU DOD controller` 即可。不需要提前下载驱动。

![virtio-gpu-1](https://github.com/user-attachments/assets/503e1d82-4fa9-4486-917e-73326ad7c988)
![virtio-gpu-2](https://github.com/user-attachments/assets/bf3a9af6-13d8-4f93-9d6c-d3b2dbddb37d)
![virtio-gpu-3](https://github.com/user-attachments/assets/a9006a78-838f-45bf-a556-2dba193d3c03)

</details>

## 参数格式

### --ssh-key

- `--ssh-key "ssh-rsa ..."`
- `--ssh-key "ssh-ed25519 ..."`
- `--ssh-key "ecdsa-sha2-nistp256/384/521 ..."`
- `--ssh-key http://path/to/public_key`
- `--ssh-key github:your_username`
- `--ssh-key gitlab:your_username`
- `--ssh-key /path/to/public_key`
- `--ssh-key C:\path\to\public_key`

## 如何修改脚本自用

1. Fork 本仓库
2. 修改 `reinstall.sh` 和 `reinstall.bat` 开头的 `confhome` 和 `confhome_cn`
3. 修改其它代码

## 感谢

感谢以下商家提供白嫖机器

[![Oracle Cloud](https://github.com/bin456789/reinstall/assets/7548515/8b430ed4-8344-4f96-b4da-c2bda031cc90)](https://www.oracle.com/cloud/)
[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/435d6740-bcdd-4f3a-a196-2f60ae397f17)](https://dartnode.com/)

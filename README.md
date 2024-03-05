# reinstall

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/dc679a17751448628fe6d8ac35e26eed)](https://app.codacy.com/gh/bin456789/reinstall/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![CodeFactor](https://www.codefactor.io/repository/github/bin456789/reinstall/badge)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://tokei.rs/b1/github/bin456789/reinstall?category=code&style=flat)](https://github.com/XAMPPRocky/tokei_rs)

一键重装脚本

中文 | [English](README.en.md)

## 亮点

- 默认使用官方安装程序，不满足安装程序内存要求时，将使用官方云镜像 (Cloud Image)
- 不含第三方链接和自制包，所有资源均实时从源站点获得
- 适配 512M + 5G 小鸡，并支持 256M 小鸡安装 Alpine
- 支持用官方 iso 安装 Windows
- 支持 Windows 重装成 Linux，也可重装 Windows
- 支持 BIOS、EFI、ARM
- 原系统分区支持 LVM、Btrfs
- 支持安装 Alpine、Arch、openSUSE、Gentoo，也可从这些系统安装
- 可通过 SSH、浏览器、串行控制台、后台 VNC 查看 DD、云镜像安装进度
- 有很多注释

## 下载（当前系统是 Linux）

国外：

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
```

国内：

```bash
curl -O https://raw.gitmirror.com/bin456789/reinstall/main/reinstall.sh
```

## 下载（当前系统是 Windows）

[无法下载？](#如果-windows-下无法下载脚本)

请先关闭 `Windows Defender` 的 `实时保护` 功能。该功能会阻止 `certutil` 下载任何文件

国外：

```batch
certutil -urlcache -f -split https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
```

国内：

```batch
certutil -urlcache -f -split https://raw.gitmirror.com/bin456789/reinstall/main/reinstall.bat
```

## 使用

所有功能均可在 Linux / Windows 下使用

- Linux 下运行 `bash reinstall.sh`
- Windows 下运行 `reinstall.bat`

### 功能 1: 安装 Linux

- 静态 IP 的机器安装 CentOS、Alma、Rocky、Fedora、Debian、Ubuntu，必须添加参数 `--ci`
- 如果不清楚机器是静态 IP 还是动态 IP，也可添加参数 `--ci`，增加安装成功率

```bash
bash reinstall.sh centos   7|8|9  (8|9 为 stream 版本)
                  alma     8|9
                  rocky    8|9
                  fedora   38|39
                  debian   10|11|12
                  ubuntu   20.04|22.04
                  alpine   3.16|3.17|3.18|3.19
                  opensuse 15.5|tumbleweed (只支持云镜像)
                  arch     (只支持 amd64 云镜像)
                  gentoo   (只支持 amd64 云镜像)

                  不输入版本号，则安装最新版
```

参数:

```bash
--ci              强制使用云镜像
```

### 功能 2: DD

- 支持 gzip、xz 格式

- 静态 IP 的机器 DD Windows，会自动配置好 IP

```bash
bash reinstall.sh dd --img https://example.com/xxx.xz
```

### 功能 3: 重启到 Alpine 救援系统 (Live OS)

- 可用 ssh 连接，进行手动 DD、修改分区、手动安装 Arch / Gentoo 等操作

- 如果没有修改硬盘内容，再次重启将回到原系统

```bash
bash reinstall.sh alpine --hold=1
```

### 功能 4: 重启到 netboot.xyz

- 可使用后台 VNC 安装 [更多系统](https://github.com/netbootxyz/netboot.xyz?tab=readme-ov-file#what-operating-systems-are-currently-available-on-netbootxyz)

```bash
bash reinstall.sh netboot.xyz
```

![netboot.xyz](https://netboot.xyz/images/netboot.xyz.gif)

### 功能 5: 安装 Windows ISO

- 注意参数两边的引号

```bash
bash reinstall.sh windows \
     --iso 'https://drive.massgrave.dev/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso' \
     --image-name 'Windows 10 Enterprise LTSC 2021'
```

![Installing Windows](https://github.com/bin456789/reinstall/assets/7548515/07c1aea2-1ce3-4967-904f-aaf9d6eec3f7)

参数:

`--iso` 原版镜像链接

`--image-name` 指定要安装的映像，不区分大小写，例如：

```text
Windows 7 Ultimate
Windows 10 Enterprise LTSC 2021
Windows 11 Pro
Windows Server 2022 SERVERDATACENTER
```

使用 `Dism++` 文件菜单 > 打开映像文件，选择要安装的 iso，可以得到映像名称

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

1. 支持的系统：
    - Windows Vista 到 11
    - Windows Server 2008 到 2022，包括以下衍生版
        - Windows Server Essentials
        - Windows Server Annual Channel
        - Hyper-V Server
        - Azure Stack HCI
2. 脚本会按需安装以下驱动：
    - KVM ([Virtio](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/))
    - XEN ([XEN PV](https://xenproject.org/windows-pv-drivers/)、[AWS PV](https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/xen-drivers-overview.html))
    - AWS ([ENA 网卡](https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/enhanced-networking-ena.html)、[NVME 存储控制器](https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/WindowsGuide/aws-nvme-drivers.html))
    - GCP ([gVNIC 网卡](https://cloud.google.com/compute/docs/networking/using-gvnic)、[GGA 显卡](https://cloud.google.com/compute/docs/instances/enable-instance-virtual-display))
    - Azure ([MANA 网卡](https://learn.microsoft.com/zh-cn/azure/virtual-network/accelerated-networking-mana-windows))
3. Vista (Server 2008) 和 32 位系统可能会缺少驱动
4. 静态 IP 的机器，安装后会自动配置好 IP
5. 可绕过 Windows 11 硬件限制
6. 支持 Azure ARM (Hyper-V)，不支持甲骨文 ARM (KVM)
7. `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso` 此镜像安装后 `wsappx` 进程会长期占用 CPU

   这是镜像的问题，解决方法是安装 `VCLibs` 库

   <https://www.google.com/search?q=ltsc+wsappx>

8. 以下网站可找到 iso 链接

   <https://massgrave.dev/genuine-installation-media.html>

## 内存要求

| 系统                                | 传统安装 | 云镜像 |
| ----------------------------------- | -------- | ------ |
| Debian                              | 384M     | 512M   |
| Ubuntu                              | 1G       | 512M   |
| CentOS / Alma / Rocky / Fedora      | 1G       | 512M   |
| Alpine                              | 256M     | -      |
| openSUSE                            | -        | 512M   |
| Arch                                | -        | 512M   |
| Gentoo                              | -        | 512M   |
| Windows 8.1 (Server 2012 R2) 或以下 | 512M     | -      |
| Windows 10 (Server 2016) 或以上     | 1G       | -      |

## 网络要求

用`安装模式`安装 Linux 要求能自动获取 IP 地址

其他情况支持静态 IP、IPv6（包括安装 Alpine、Linux 云镜像、Windows iso、dd）

运行脚本时不需要填写静态 IP 地址

## 虚拟化要求

不支持 OpenVZ、LXC 虚拟机

请使用 <https://github.com/LloydAsp/OsMutation>

## 默认密码

| 系统          | 用户名        | 密码     |
| ------------- | ------------- | -------- |
| Linux         | root          | 123@@@   |
| Windows (iso) | administrator | 123@@@   |
| Windows (dd)  | 镜像用户名    | 镜像密码 |

如果远程登录 Windows 提示密码错误，尝试用户名 `.\administrator`

## 如果 Windows 下无法下载脚本

可尝试以下几种方法

1. 关闭 Windows Defender 实时保护

2. Windows 7 安装此补丁启用 TLS 1.2

   <https://aka.ms/easyfix51044>

3. 更新 SSL 根证书

   ```batch
   certutil -generateSSTFromWU root.sst
   certutil -addstore Root root.sst
   ```

4. 手动下载，通过 `远程桌面` 复制这两个文件

   <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat>

   <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh>

## TODO

- 安装模式：静态 IP、IPv6、多网卡

## 感谢

感谢以下商家提供白嫖机器

[![Oracle Cloud](https://github.com/bin456789/reinstall/assets/7548515/8b430ed4-8344-4f96-b4da-c2bda031cc90)](https://www.oracle.com/cloud/)
[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/435d6740-bcdd-4f3a-a196-2f60ae397f17)](https://dartnode.com/)

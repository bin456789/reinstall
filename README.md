# reinstall

又一个重装脚本

## 亮点

- 不含第三方链接和自制包，所有资源均实时从各发行版的镜像站点获得
- 默认使用官方安装程序，不满足安装程序内存要求时，将使用官方云镜像 (Cloud Image)
- 使用云镜像安装时，配置要求低至 512M 内存 + 5G 硬盘
- 支持 BIOS / EFI / ARM
- 支持使用官方 iso 重装到 Windows (不支持 ARM)
- 支持从 Windows 重装到 Linux
- 原系统分区支持 lvm / btrfs
- 自动选择国内外安装源
- 使用 dd 或云镜像时有高贵的进度条，可通过 ssh/web/vnc/串行控制台 查看
- 有很多注释

## Linux 下使用

### 下载

    curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh

### 下载 (国内)

    curl -O https://ghps.cc/https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh

### 安装 Linux

    bash reinstall.sh centos   7|8|9 (8|9 为 stream 版本)
                      alma     8|9
                      rocky    8|9
                      fedora   37|38
                      debian   10|11|12
                      ubuntu   20.04|22.04
                      alpine   3.16|3.17|3.18
                      opensuse 15.4|15.5|tumbleweed (只支持云镜像)
                      arch     (只支持云镜像)
                      gentoo   (只支持 amd64 云镜像)

    可选参数:         --ci     强制使用云镜像

### 安装 Windows

    bash reinstall.sh windows \
         --iso=https://example.com/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso \
         --image-name='Windows 10 Enterprise LTSC 2021'

### DD（支持 gzip xz 格式）

    bash reinstall.sh dd --img=https://example.com/xxx.xz

## Windows 下使用

下载（链接另存为）放到同一目录

<https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat>

<https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh>

管理员权限打开 `cmd` / `powershell` 窗口，先运行 `cmd`（重要），再运行：

    reinstall.bat centos-7 (或其他操作，所有功能均可在 Windows 下使用)

## Windows iso 安装说明

    bash reinstall.sh windows \
        --iso=https://example.com/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso \
        --image-name='Windows 10 Enterprise LTSC 2021'

### 参数

`--iso` 官方原版镜像，无需集成 virtio/xen/aws nitro 驱动

`--image-name` 一个 iso 里会有一个或多个映像，此参数用于指定要安装的映像。不区分大小写，但两边要有引号，例如：

    'Windows 7 Ultimate'
    'Windows 10 Enterprise LTSC 2021'
    'Windows 11 Pro'
    'Windows Server 2022 SERVERDATACENTER'

使用 Dism++ 文件菜单 > 打开映像文件，选择要安装的 iso，可以得到映像名称

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

### 其它说明

1. 测试成功的系统有 7 10 11 2022，测试平台为 vultr (bios)、甲骨文 (efi)、aws t2 (xen)、aws t3 (nitro)
2. 支持 32/64 位系统，UEFI 机器只支持 64 位
3. 不支持 ARM 机器
4. `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso`
   此镜像安装后 `wsappx` 进程会长期占用 CPU

   <https://www.google.com/search?q=ltsc+wsappx>

   这是镜像的问题，解决方法是安装 `VCLibs` 库

5. iso 链接可以到 `https://archive.org` 上面找

## 内存要求

| 系统                           | 传统安装 | 云镜像 |
| ------------------------------ | -------- | ------ |
| Debian                         | 384M     | 512M   |
| Ubuntu                         | 1G       | 512M   |
| CentOS / Alma / Rocky / Fedora | 1G       | 512M   |
| Alpine                         | 256M     | -      |
| openSUSE                       | 暂不支持 | 512M   |
| Arch                           | 暂不支持 | 512M   |
| Gentoo                         | 暂不支持 | 512M   |
| Windows                        | 1G       | -      |

## 网络要求

要求有 IPv4、DHCPv4 !!!!!

要求有 IPv4、DHCPv4 !!!!!

要求有 IPv4、DHCPv4 !!!!!

## 默认密码

| 系统    | 用户名        | 密码   |
| ------- | ------------- | ------ |
| Linux   | root          | 123@@@ |
| Windows | administrator | 123@@@ |

## TODO

- 静态 IP / IPV6

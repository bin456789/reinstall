# reinstall
一个一键重装脚本

#### 亮点:
```
使用官方安装方式，非第三方 dd 镜像，更安全（也提供 dd 功能）
支持 BIOS/EFI 机器，支持 ARM 机器
可能是第一个支持在 1g 内存上安装 红帽 7/8/9 系列的脚本
可能是第一个支持重装到 ubuntu 22.04 的脚本
可能是第一个支持重装到 alpine 的脚本
可能是第一个支持用官方 iso 重装到 Windows 的脚本
支持从 Windows 重装到 Linux
有高贵的 dd 进度条
有很多注释
```
#### 使用（当前系统是 Linux）:
```
下载:
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh

安装 Linux: 
bash reinstall.sh centos-7 (或其他系统)

安装 Windows:
bash reinstall.sh windows \
    --iso=https://example.com/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso \
    --image-name='Windows 10 Enterprise LTSC 2021'

dd:
bash reinstall.sh dd --img=https://example.com/xxx.gz

重启:
reboot
```
#### 使用（当前系统是 Windows）:
```
下载
https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
放到同一目录

管理员权限打开 cmd/powershell 窗口
运行 reinstall.bat centos-7 (或其他系统)

本脚本所有功能皆可在 Windows 下使用，包括重装到 Linux/Windows/dd
```
#### 支持重装到:
```
centos-7/8/9 (centos 8/9 为 stream 版本)
alma-8/9
rocky-8/9
fedora-37/38
ubuntu-20.04/22.04
alpine-3.16/3.17/3.18
debian-10/11/12
windows (见下方注意事项)
dd
```
#### Windows 注意事项:
```
支持 32 位系统 (BIOS)、64 位系统 (BIOS/UEFI)，测试成功的系统有 7 10 11 2022
安装 Windows 需要以下参数
--iso           iso 链接，不需要提前添加 virtio 驱动
--image-name    系统全名，不区分大小写，两边要有引号，例如：
                'Windows 7 Ultimate'
                'Windows 10 Enterprise LTSC 2021'
                'Windows 11 Pro'
                'Windows Server 2022 SERVERDATACENTER' 

暂不支持 Xen 虚拟化的机器重装到 Windows
经测试不支持甲骨文云的 ARM
不推荐用这种方法安装 zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso，此镜像有“wsappx占用cpu”的问题，需要自行解决
                
提示：iso 链接可以到 https://archive.org 上面找
```
#### 内存要求:
```
debian 384M
centos/alma/rocky/fedora 1G
alpine ?
ubuntu ?
windows 1G
```
#### 网络要求:
```
要求有 IPv4、DHCPv4
```
#### 默认用户名 / 密码:
```
root            123@@@
administrator   123@@@
````
#### todo:
```
测试 Xen / AWS Xen
使用 Cloud Images
静态 IP / IPV6
````

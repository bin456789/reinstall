# reinstall
一个一键重装脚本

#### 亮点:
```
使用官方安装方式，非第三方 dd 镜像，更安全
支持 BIOS/EFI 机器，支持 ARM 机器
可能是第一个支持在 1g 内存上安装 红帽 7/8/9 系列的脚本
可能是第一个支持重装到 ubuntu 22.04 的脚本
可能是第一个支持重装到 alpine 的脚本
可能是第一个支持重装到 Windows 的脚本（不算 dd 的话）
```
#### 使用:
```
下载:
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh

安装 Linux: 
bash reinstall.sh centos-7 (或其他系统)

安装 Windows:
bash reinstall.sh windows --iso=https://archive.org/download/xxx/zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso --image-name='Windows 10 Enterprise LTSC 2021' (或其他系统)

重启:
reboot
```
#### 支持重装到:
```
centos-7/8/9    # centos 8/9 为 stream 版本
alma-8/9
rocky-8/9
fedora-36/37/38
ubuntu-20.04/22.04
alpine-3.16/3.17/3.18
debian-10/11
windows (见下方注意事项)
```
#### Windows 注意事项:
```
只支持 UEFI 引导的机器，已测试成功的系统有 7 10 11，其他系统不保证成功
安装 Windows 需要以下参数
--iso           iso 链接，不需要提前添加 virtio 驱动
--image-name    系统全名，两边要有引号，例如：
                'Windows 7 Ultimate'
                'Windows 10 Enterprise LTSC 2021'
                'Windows 11 Pro'
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
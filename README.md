# reinstall
一个一键重装脚本

#### 亮点:
```
使用官方安装方式，非第三方 DD 镜像，更安全
支持 BIOS/EFI 机器，支持 ARM 机器
可能是第一个支持在 1g 内存上安装 红帽 7/8/9 系列的脚本
可能是第一个支持重装到 ubuntu 22.04 的脚本
可能是第一个支持重装到 alpine 的脚本
```
#### 使用:
```
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
bash reinstall.sh centos-7 或其他系统
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
```
#### 内存要求:
```
debian 384m
centos/alma/rocky/fedora 1g
alpine ?
ubuntu ?
```
#### 网络要求:
```
要求有 IPv4、DHCPv4
```
#### 默认用户名 / 密码:
 ```
 root   123@@@
 ````
# reinstall

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/dc679a17751448628fe6d8ac35e26eed)](https://app.codacy.com/gh/bin456789/reinstall/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![CodeFactor](https://www.codefactor.io/repository/github/bin456789/reinstall/badge)](https://www.codefactor.io/repository/github/bin456789/reinstall)
[![Lines of Code](https://tokei.rs/b1/github/bin456789/reinstall?category=code)](#reinstall)

One-click Reinstallation Script

[中文](README.md) | [English](README.en.md)

## Highlights

- Default usage of official installation programs. In cases where the memory requirements of the installation program are not met, the official cloud image will be used.
- Excludes third-party links and self-made packages; all resources are fetched in real-time from the source site.
- Adapted for 512M + 5G small VPS, and supports installing Alpine on 256M VPS.
- Supports installing Windows using the official ISO (does not support ARM).
- Supports reinstalling Windows as Linux and vice versa.
- Supports BIOS, EFI, ARM (Windows installation not supported on ARM).
- Supports original system partition with LVM, Btrfs.
- Supports installing Alpine, Arch, openSUSE, Gentoo, and installing from these systems.
- Progress of DD and cloud image installation can be viewed through SSH, a browser, serial console, or background VNC.
- Contains extensive comments.

## Usage on Linux

### Download

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
```

### Download (from within China)

```bash
curl -O https://raw.fgit.cf/bin456789/reinstall/main/reinstall.sh
```

### Usage 1: Install Linux

Note: For machines with static IP, installing centos, alma, rocky, fedora, debian, ubuntu, requires adding the --ci parameter to force the use of the cloud mirror.

```bash
bash reinstall.sh centos   7|8|9  (8|9 for stream versions)
                  alma     8|9
                  rocky    8|9
                  fedora   38|39
                  debian   10|11|12
                  ubuntu   20.04|22.04
                  alpine   3.16|3.17|3.18|3.19
                  opensuse 15.5|tumbleweed (supports cloud mirror only)
                  arch     (supports only amd64 cloud mirror)
                  gentoo   (supports only amd64 cloud mirror)

                  If no version number is entered, it installs the latest version.

Optional parameters: --ci     Force the use of the cloud mirror.
```

### Usage 2: DD

Supports gzip, xz formats.

Supports automatic configuration of static IP, system disk expansion.

```bash
bash reinstall.sh dd --img=https://example.com/xxx.xz
```

### Usage 3: Restart to Alpine Rescue System (Live OS)

Can be connected via SSH to perform manual DD, modify partitions, manually install Arch Linux, and other operations.

```bash
bash reinstall.sh alpine --hold=1
```

### Usage 4: Restart to netboot.xyz

```bash
bash reinstall.sh netboot.xyz
```

### Usage 5: Install Windows ISO

```bash
bash reinstall.sh windows \
     --iso='https://example.com/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso' \
     --image-name='Windows 10 Enterprise LTSC 2021'
```

#### Parameter Description

`--iso` Original image link without integrating VirtIO, Xen, AWS, GCP drivers.

`--image-name` Specifies the image to install, case insensitive, enclosed in quotes, for example:

```text
'Windows 7 Ultimate'
'Windows 10 Enterprise LTSC 2021'
'Windows 11 Pro'
'Windows Server 2022 SERVERDATACENTER'
```

Use `Dism++` File menu > Open image file, select the iso to get the image name.

![image-name](https://github.com/bin456789/reinstall/assets/7548515/5aae0a9b-61e2-4f66-bb98-d470a6beaac2)

#### Other Notes

1. Successfully tested systems: 7, 10, 11, 2022. Tested platforms: vultr (bios), oracle (efi), aws t2 (xen), aws t3 (nitro).
2. Supports 32/64-bit systems; UEFI machines only support 64-bit.
3. Can bypass Windows 11 hardware restrictions.
4. Tested not to support ARM.
5. `zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso`: After installing this image, the `wsappx` process may occupy CPU for an extended period.

   This is an issue with the image, and the solution is to install the `VCLibs` library.

   <https://www.google.com/search?q=ltsc+wsappx>

6. The following websites contain iso links:

   <https://archive.org>

   <https://massgrave.dev/genuine-installation-media.html>

## Usage on Windows

Run `cmd` with administrator privileges.

If running `powershell`, switch to `cmd` first.

### Download

```batch
certutil -urlcache -f -split https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat
```

### Download (from within China)

```batch
certutil -urlcache -f -split https://raw.fgit.cf/bin456789/reinstall/main/reinstall.bat
```

### If unable to download

- Disable Windows Defender real-time protection.

- Update SSL root certificate.

  ```batch
  certutil -generateSSTFromWU root.sst
  certutil -addstore Root root.sst
  ```

- Save the following two files via 'Save link as' or use 'Remote Desktop' to copy:

  <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.bat>

  <https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh>

### Usage

All functionalities available in Linux can be used on Windows, using parameters similar to those in Linux.

For example, to install centos 7:

```batch
reinstall.bat centos-7
```

## Memory Requirements

| System                           | Traditional Install | Cloud Image |
| -------------------------------- | ------------------- | ------------|
| Debian                           | 384M                | 512M        |
| Ubuntu                           | 1G                  | 512M        |
| CentOS / Alma / Rocky / Fedora   | 1G                  | 512M        |
| Alpine                           | 256M                | -           |
| openSUSE                         | -                   | 512M        |
| Arch                             | -                   | 512M        |
| Gentoo                           | -                   | 512M        |
| Windows                          | 1G                  | -           |

## Network Requirements

For 'Installation Mode' installing Linux, DHCPv4 is required.

Other cases support static IP, IPv6 (including installing Alpine, cloud mirror, Windows iso, dd).

No need to fill in the static IP address when running the script.

## Virtualization Requirements

Does not support OpenVZ, LXC virtual machines.

Please use <https://github.com/LloydAsp/OsMutation>.

## Default Passwords

| System               | Username       | Password |
| -------------------- | -------------- | -------- |
| Linux                | root           | 123@@@   |
| Windows (ISO install) | administrator  | 123@@@   |

## TODO

- Installation modes: Static IP, IPv6, multiple NICs.

## Sponsor

[![DartNode](https://github.com/bin456789/reinstall/assets/7548515/7531e443-4069-4bf1-a40e-2e965f311e3f)](https://dartnode.com/)

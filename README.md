# CXL-Emulator-QEMU
If you prefer to skip the background details and jump straight into the setup process, click me [Get started right away](#install-prerequisite-packages)

Setting up a kernel development workflow for CXL can be tricky for beginners. Installing the Linux kernel on bare metal is slow and risky, as crashes can break the system. A better approach is using QEMU to emulate CXL hardware in a virtual machine (VM), enabling faster boot times and safer testing. This guide explains how to set up QEMU on Ubuntu to develop and test CXL without prior kernel development experience.

- [CXL-Emulator-QEMU](#cxl-emulator-qemu)
  - [CXL emulation in QEMU](#cxl-emulation-in-qemu)
  - [Setup CXL Testing/Development environment with QEMU Emulation](#setup-cxl-testingdevelopment-environment-with-qemu-emulation)
    - [Install prerequisite packages](#install-prerequisite-packages)
    - [Build QEMU from source code](#build-qemu-from-source-code)
    - [Steps to build QEMU emulator:](#steps-to-build-qemu-emulator)
    - [Build Kernel with CXL support enabled](#build-kernel-with-cxl-support-enabled)
    - [Creating Root File System for Guest VM](#creating-root-file-system-for-guest-vm)
    - [Bringing up the guest VM](#bringing-up-the-guest-vm)
    - [Bringing up network](#bringing-up-network)
    - [List CXL device](#list-cxl-device)
  - [Access CXL memory device emulated with QEMU](#access-cxl-memory-device-emulated-with-qemu)
    - [Install ndctl from source code](#install-ndctl-from-source-code)
    - [Load cxl drivers and show CXL memory device](#load-cxl-drivers-and-show-cxl-memory-device)
    - [To convert CXL memory into system ram, we need extra steps.](#to-convert-cxl-memory-into-system-ram-we-need-extra-steps)
  - [References:](#references)

CXL (Compute Express Link) is an open standard for high-speed, high capacity central processing unit (CPU)-to-device and CPU-to-memory connections, designed for high performance data center computers. CXL is built on the serial PCI Express (PCIe) physical and electrical interface and includes PCIe-based block input/output protocol ([CXL.io](http://cxl.io/)) and new cache-coherent protocols for accessing system memory (CXL.cache) and device memory (CXL.mem).--From ([wikipedia](https://en.wikipedia.org/wiki/Compute_Express_Link))

CXL hardware design follows the open specification from CXL consortium ([link](https://computeexpresslink.org/)). The CXL specification is under active development and has evolved from 1.1, 2.0, to 3.0 and as of now the 3.1 specification. The last specification was released August 2023 as the CXL 3.1 specification. Since CXL hardware is not currently widely accessible on the market at the moment, software developers rely on emulation of CXL hardware for debugging and testing CXL code including the CXL Linux kernel drivers. As far as I know, QEMU is the only emulator that supports CXL hardware emulation at the moment.

QEMU is a generic and open-source machine emulator and virtualizer. It can simulate systems with different hardware configurations, including CPUs with different ISA, memory configurations, and peripheral devices. It is noted that QEMU is defined for simulating system functionalities not for timing models, so it is not suitable for performance related simulation and evaluation.

## CXL emulation in QEMU

The mainstream QEMU source code can be found ([here](https://github.com/qemu/qemu/releases/tag/v9.0.0-rc2)). CXL related code is located in the following locations in the QEMU source tree:

* hw/cxl/
* include/hw/cxl/
* hw/mem/cxl_type3.c
* qapi/cxl.json

QEMU currently can emulate the following CXL 2.0 compliant CXL system components ([Qemu CXL doc](https://www.qemu.org/docs/master/system/devices/cxl.html)):

* CXL Host Bridge (CXL HB): equivalent to PCIe host bridge.
* CXL Root Ports (CXL RP): serves the same purpose as a PCIe Root Port. There are a number of CXL specific Designated Vendor Specific Extended Capabilities (DVSEC) in PCIe Configuration Space and associated component register access via PCI bars.
* CXL Switch: has a similar architecture to those in PCIe, with a single upstream port, internal PCI bus and multiple downstream ports.
* CXL Type 3 memory devices as memory expansion: the device can act as a system RAM or Dax device. Currently, volatile and non-volatile memory emulation has been merged to mainstream. CXL 3.0 introduces a new CXL memory device that implements dynamic capacity-DCD (dynamic capacity device). The support of DCD emulation in QEMU has been posted to the mailing list and will be merged soon.
* CXL Fixed Memory Windows (CFMW): A CFMW consists of a particular range of Host Physical Address space which is routed to particular CXL Host Bridges. At time of generic software initialization it will have a particularly interleaving configuration and associated Quality of Service Throttling Group (QTG). This information is available to system software, when making decisions about how to configure interleave across available CXL memory devices. It is provide as CFMW Structures (CFMWS) in the CXL Early Discovery Table, an ACPI table.

## Setup CXL Testing/Development environment with QEMU Emulation

To test a CXL device with QEMU emulation, we need to have the following prerequisites:

* A QEMU emulator either compiled from source code or preinstalled with CXL emulation support;
* A Kernel image with CXL support (compiled in or as modules);
* A file system that serves as the root fs for booting the guest VM.

### Install prerequisite packages

My Ubuntu:
<pre>
kz@kz-HP-EliteBook:~/cxl/linux-kernel-dcd-2024-03-24$ lsb_release -a
No LSB modules are available.
Distributor ID: Ubuntu
Description:    Ubuntu 22.04.3 LTS
Release:        22.04
Codename:       jammy
</pre>

Building QEMU and the Linux kernel rely on some preinstalled packages.

<pre>
sudo apt-get install libglib2.0-dev libgcrypt20-dev zlib1g-dev \
    autoconf automake libtool bison flex libpixman-1-dev bc QEMU-kvm \
    make ninja-build libncurses-dev libelf-dev libssl-dev debootstrap \
    libcap-ng-dev libattr1-dev libslirp-dev libslirp0
</pre>
Just in case, install more.
<pre>
sudo apt-get install git fakeroot build-essential ncurses-dev xz-utils libssl-dev bc flex libelf-dev bison
</pre>

### Build QEMU from source code

It is recommended to build the QEMU from source code for two reason:

1. The pre-compiled binary can be old and lack the latest features that are supported by QEMU;
1. Building QEMU from source code allows us to customize QEMU based on our needs, including development debugging, applying specific patches to test some un-merged features, or modifying QEMU to test some ideas or fixes, etc.

### Steps to build QEMU emulator:

**We can download QEMU source code from different sources, for example:**

* Mainstream QEMU: https://github.com/qemu/qemu
* QEMU CXL Maintainer Jonathan's local tree for To-be-Merged patches: https://gitlab.com/jic23/qemu
* Fan Ni's local github tree for Latest DCD emulation: https://github.com/moking/qemu/tree/dcd-v6

Below we will use DCD emulation setup as an example.

**Step 1: download QEMU source code**

git clone https://github.com/moking/QEMU/tree/dcd-v6

**Step 2: configure QEMU**

For example, configure QEMU with x86_64 CPU architecture and debug support:
<pre>
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6$ ./configure --target-list=x86_64-softmmu --enable-debug
</pre>

**Step 3: Compile QEMU**

<pre>
make -j$(nproc)
</pre>
or
<pre>
make -j32 
</pre>
or
<pre>
make -j16
</pre>

If compile succeed, a new QEMU binary will be generated under build directory:
<pre>
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ ls qemu-system-x86_64 -lh
-rwxrwxr-x 1 kz kz 56M  2-р сар 23 22:16 qemu-system-x86_64
</pre>

### Build Kernel with CXL support enabled
You have two options here:
Note: build cxl drivers as modules and load/unload them on demand._
Note: build CXL drivers directly into the kernel, making them always available without the need for manual loading or unloading.

**Step 1: download Linux Kernel source code**

Linux source code can be downloaded from different sources:

* https://git.kernel.org/
* CXL related development repository: https://git.kernel.org/pub/scm/linux/kernel/git/cxl/cxl.git/?h=fixes
* Kernel with DCD drivers:https://github.com/weiny2/linux-kernel/tree/dcd-2024-03-24

Below we will use DCD kernel code as an example.
<pre>
git clone https://github.com/weiny2/linux-kernel/tree/dcd-2024-03-24
</pre>

**Step 2: configure kernel**

After we downloaded the source code, we need to configure the kernel features we want to pick up in the following compile step.
<pre>
make menuconfig
</pre>
or,
<pre>
make kconfig
</pre>

After the kernel is configured, a .config file will be generated under the root directory of linux kernel source code.

Note:
You can use my .config directly, in case you meet any problems while execute the command below to bootup qemu/kernel
With my config, all CXL are built to kernel bzImage, there is no need to load modules after QEMU kernel is loaded.
<pre>
put .config to folder below:
kz@kz-HP-EliteBook:~/cxl/linux-kernel-dcd-2024-03-24$ ls .config -lh
-rw-rw-r-- 1 kz kz 279K  3-р сар  1 23:02 .config
</pre>

If you want to understand the change I made, please diff two files by
<pre>
diff .config.old .config
Note: I didn't spend time to narrow down the minium change, but the workable change :)
</pre>

To enable CXL related code support, we need to enable following configurations in .config file.
(This way supports modules loading way by command modprobe in below sections, if you use my .config file, please ignore this step, jump to [**Step 3: Compile Kernel**](#**Step 3: Compile Kernel**))
<pre>
kz@kz-HP-EliteBook:~/cxl/linux-kernel-dcd-2024-03-24$ cat .config | egrep  "CXL|DAX|_ND_"
CONFIG_ARCH_WANT_OPTIMIZE_DAX_VMEMMAP=y
CONFIG_CXL_BUS=m
CONFIG_CXL_PCI=m
CONFIG_CXL_MEM_RAW_COMMANDS=y
CONFIG_CXL_ACPI=m
CONFIG_CXL_PMEM=m
CONFIG_CXL_MEM=m
CONFIG_CXL_PORT=m
CONFIG_CXL_SUSPEND=y
CONFIG_CXL_REGION=y
CONFIG_CXL_REGION_INVALIDATION_TEST=y
CONFIG_CXL_PMU=m
CONFIG_ND_CLAIM=y
CONFIG_ND_BTT=m
CONFIG_ND_PFN=m
CONFIG_NVDIMM_DAX=y
CONFIG_DAX=m
CONFIG_DEV_DAX=m
CONFIG_DEV_DAX_PMEM=m
CONFIG_DEV_DAX_HMEM=m
CONFIG_DEV_DAX_CXL=m
CONFIG_DEV_DAX_HMEM_DEVICES=y
CONFIG_DEV_DAX_KMEM=m
</pre>

**Step 3: Compile Kernel**
<pre>
make -j$(nproc)
</pre>
or
<pre>
make -j32 
</pre>
or
<pre>
make -j16
</pre>

After a successful compile, a new file vmlinux will be generated under kernel root directory. A compressed kernel image will also be available.
<pre>
ls arch/x86_64/boot/bzImage -lh

e.g.
kz@kz-HP-EliteBook:~/cxl/linux-kernel-dcd-2024-03-24$ ls arch/x86_64/boot/bzImage -lh
lrwxrwxrwx 1 kz kz 22  3-р сар  1 19:12 arch/x86_64/boot/bzImage -> ../../x86/boot/bzImage
kz@kz-HP-EliteBook:~/cxl/linux-kernel-dcd-2024-03-24$ ls arch/x86/boot/bzImage -lh
-rwxrwxrwx 1 kz kz 13M  3-р сар  1 19:12 arch/x86/boot/bzImage
</pre>

Step 4: Install kernel modules
This will install to host machine, not qemu, but it will be used by mounting host machine's directory /lib/modules to qemu's local folder.
<pre>
sudo make modules_install
</pre>
### Creating Root File System for Guest VM

To create a disk image as root file system of the guest VM, we need to leverage the tools generated by compiling QEMU source code.
<pre>
find . -name "qemu-img"

e.g.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6$ find . -name "qemu-img"
./build/qemu-img
./build/qemu-bundle/usr/local/bin/qemu-img
</pre>

1. Create a QEMU image with QEMU-image (e.g., 16G). 
<pre>
./qemu-img create qemu.img 16G

e.g.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ ./qemu-img create qemu.img 16G
Formatting 'qemu.img', fmt=raw size=17179869184
</pre>

2. Create a file system for the image.
<pre>
sudo mkfs.ext4 qemu.img

e.g.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo mkfs.ext4 qemu.img
mke2fs 1.46.5 (30-Dec-2021)
Discarding device blocks: done
Creating filesystem with 4194304 4k blocks and 1048576 inodes
Filesystem UUID: bd521f70-5c9b-4a33-bd51-f58ad962cc43
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208,
        4096000

Allocating group tables: done
Writing inode tables: done
Creating journal (32768 blocks): done
Writing superblocks and filesystem accounting information: done

kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$

</pre>
1. Mount the file system to a directory.
<pre>
mkdir mntdir
sudo mount -o loop qemu.img mntdir
</pre>
1. Install the debian distribution to the file system.
<pre>
sudo debootstrap --arch amd64 stable mntdir
or you want a specific Ubuntu version, use
sudo debootstrap --arch amd64 jammy mntdir

e.g.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo debootstrap --arch amd64 stable mntdir
I: Keyring file not available at /usr/share/keyrings/debian-archive-keyring.gpg; switching to https mirror https://deb.debian.org/debian
I: Retrieving Packages
I: Validating Packages
I: Resolving dependencies of required packages...
I: Resolving dependencies of base packages...
I: Checking component main on https://deb.debian.org/debian...
I: Retrieving adduser 3.134
I: Validating adduser 3.134
I: Retrieving apt 2.6.1
I: Validating apt 2.6.1
...
I: Configuring nftables...
I: Configuring iproute2...
I: Configuring isc-dhcp-client...
I: Configuring ifupdown...
I: Configuring tasksel...
I: Configuring tasksel-data...
I: Configuring libc-bin...
I: Configuring ca-certificates...
I: Base system installed successfully.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$
</pre>

1. Setup host and guest VM directory sharing
<pre>
echo "#! /bin/bash
mount -t 9p -o trans=virtio homeshare /home/kz
mount -t 9p -o trans=virtio modshare /lib/modules
" > ./rc.local
chmod a+x ./rc.local
sudo mv ./rc.local mntdir/etc/
sudo mkdir -p ./mntdir/home/kz
sudo mkdir -p ./mntdir/lib/modules/

e.g.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ echo "#! /bin/bash
mount -t 9p -o trans=virtio homeshare /home/kz
mount -t 9p -o trans=virtio modshare /lib/modules
" > ./rc.local
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ chmod a+x ./rc.local
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo mv ./rc.local mntdir/etc/
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo mkdir -p ./mntdir/home/kz
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo mkdir -p ./mntdir/lib/modules/
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$
</pre>

1. Setup network for guest VM

Create a config.yaml file with following content under ./mntdir/etc/netplan.
<pre>
network:
    version: 2
    renderer: networkd
    ethernets:
        enp0s2:
            dhcp4: true

e.g.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo mkdir -p ./mntdir/etc/netplan/
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo vi -p ./mntdir/etc/netplan/config.yaml
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ ll ./mntdir/etc/netplan/config.yaml
-rw-r--r-- 1 root root 102  3-р сар  2 09:13 ./mntdir/etc/netplan/config.yaml
</pre>

7. set the password up
<pre>
sudo chroot mntdir
passwd
exit

e.g.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo chroot mntdir
root@kz-HP-EliteBook:/# passwd
New password:
Retype new password:
passwd: password updated successfully
root@kz-HP-EliteBook:/# exit
exit
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$
</pre>

1. Umount mntdir
<pre>
sudo umount mntdir

e.g.
kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ sudo umount mntdir
</pre>

### Bringing up the guest VM
Note: 
1. You can also use start_qemu_dcd.sh and start_qemu_pmem.sh directly from git.
2. Username is root, password is what you set in step 7 above.
3. Exit qemu by ctrl+a, x

Example 1: boot up VM with a CXL persistent memory sized 512MiB, directly attached to the root port of a host bridge.
<pre>
~/cxl/qemu-dcd-v6/build/qemu-system-x86_64 \
    -s \
    -kernel ~/cxl/linux-kernel-dcd-2024-03-24/arch/x86/boot/bzImage \
    -append "root=/dev/sda rw console=ttyS0,115200 ignore_loglevel nokaslr \
             cxl_acpi.dyndbg=+fplm cxl_pci.dyndbg=+fplm cxl_core.dyndbg=+fplm \
             cxl_mem.dyndbg=+fplm cxl_pmem.dyndbg=+fplm cxl_port.dyndbg=+fplm \
             cxl_region.dyndbg=+fplm cxl_test.dyndbg=+fplm cxl_mock.dyndbg=+fplm \
             cxl_mock_mem.dyndbg=+fplm dax.dyndbg=+fplm dax_cxl.dyndbg=+fplm \
             device_dax.dyndbg=+fplm" \
    -smp 1 \
    -accel kvm \
    -serial mon:stdio \
    -nographic \
    -qmp tcp:localhost:4444,server,wait=off \
    -netdev user,id=network0,hostfwd=tcp::2024-:22 \
    -device e1000,netdev=network0 \
    -monitor telnet:127.0.0.1:12345,server,nowait \
    -drive file=~/cxl/qemu-dcd-v6/build/qemu.img,index=0,media=disk,format=raw \
    -machine q35,cxl=on -m 8G,maxmem=32G,slots=8 \
    -virtfs local,path=/lib/modules,mount_tag=modshare,security_model=mapped \
    -virtfs local,path=/home/kz,mount_tag=homeshare,security_model=mapped \
    -object memory-backend-file,id=cxl-mem1,share=on,mem-path=/tmp/cxltest.raw,size=512M \
    -object memory-backend-file,id=cxl-lsa1,share=on,mem-path=/tmp/lsa.raw,size=512M \
    -device pxb-cxl,bus_nr=12,bus=pcie.0,id=cxl.1 \
    -device cxl-rp,port=0,bus=cxl.1,id=root_port13,chassis=0,slot=2 \
    -device cxl-type3,bus=root_port13,memdev=cxl-mem1,lsa=cxl-lsa1,id=cxl-pmem0 \
    -M cxl-fmw.0.targets.0=cxl.1,cxl-fmw.0.size=4G,cxl-fmw.0.interleave-granularity=8k

e.g.
kz@kz-HP-EliteBook:~/cxl/linux-kernel-dcd-2024-03-24$ ~/cxl/qemu-dcd-v6/build/qemu-system-x86_64 \
    -s \
    -kernel ~/cxl/linux-kernel-dcd-2024-03-24/arch/x86/boot/bzImage \
    -append "root=/dev/sda rw console=ttyS0,115200 ignore_loglevel nokaslr \
             cxl_acpi.dyndbg=+fplm cxl_pci.dyndbg=+fplm cxl_core.dyndbg=+fplm \
             cxl_mem.dyndbg=+fplm cxl_pmem.dyndbg=+fplm cxl_port.dyndbg=+fplm \
             cxl_region.dyndbg=+fplm cxl_test.dyndbg=+fplm cxl_mock.dyndbg=+fplm \
             cxl_mock_mem.dyndbg=+fplm dax.dyndbg=+fplm dax_cxl.dyndbg=+fplm \
             device_dax.dyndbg=+fplm" \
    -smp 1 \
    -accel kvm \
    -serial mon:stdio \
    -nographic \
    -qmp tcp:localhost:4444,server,wait=off \
    -netdev user,id=network0,hostfwd=tcp::2024-:22 \
    -device e1000,netdev=network0 \
    -monitor telnet:127.0.0.1:12345,server,nowait \
    -drive file=~/cxl/qemu-dcd-v6/build/qemu.img,index=0,media=disk,format=raw \
    -machine q35,cxl=on -m 8G,maxmem=32G,slots=8 \
    -virtfs local,path=/lib/modules,mount_tag=modshare,security_model=mapped \
    -virtfs local,path=/home/kz,mount_tag=homeshare,security_model=mapped \
    -object memory-backend-file,id=cxl-mem1,share=on,mem-path=/tmp/cxltest.raw,size=512M \
    -object memory-backend-file,id=cxl-lsa1,share=on,mem-path=/tmp/lsa.raw,size=512M \
    -device pxb-cxl,bus_nr=12,bus=pcie.0,id=cxl.1 \
    -device cxl-rp,port=0,bus=cxl.1,id=root_port13,chassis=0,slot=2 \
    -device cxl-type3,bus=root_port13,memdev=cxl-mem1,lsa=cxl-lsa1,id=cxl-pmem0 \
    -M cxl-fmw.0.targets.0=cxl.1,cxl-fmw.0.size=4G,cxl-fmw.0.interleave-granularity=8k
SeaBIOS (version rel-1.16.3-0-ga6ed6b701f0a-prebuilt.qemu.org)


iPXE (http://ipxe.org) 00:02.0 CA00 PCI2.10 PnP PMM+7EFD0890+7EF30890 CA00



Booting from ROM..
[    0.000000] Linux version 6.8.0 (kz@kz-HP-EliteBook) (gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0, GNU ld (GN5
[    0.000000] Command line: root=/dev/sda rw console=ttyS0,115200 ignore_loglevel nokaslr              cxl_acm
[    0.000000] KERNEL supported cpus:
[    0.000000]   Intel GenuineIntel
[    0.000000]   AMD AuthenticAMD
[    0.000000]   Hygon HygonGenuine
[    0.000000]   Centaur CentaurHauls
[    0.000000]   zhaoxin   Shanghai
[    0.000000] BIOS-provided physical RAM map:
[    0.000000] BIOS-e820: [mem 0x0000000000000000-0x000000000009fbff] usable
[    0.000000] BIOS-e820: [mem 0x000000000009fc00-0x000000000009ffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000000f0000-0x00000000000fffff] reserved

...

[    1.888950] cxl_core:devm_cxl_setup_hdm:159: cxl_port port1: HDM decoder registers not implemented
[    1.888951] cxl_port:cxl_switch_port_probe:84: cxl_port port1: Fallback to passthrough decoder
[    1.889009] cxl_core:add_hdm_decoder:37: cxl decoder1.0: Added to port port1
[    1.889010] cxl_core:cxl_bus_probe:2077: cxl_port port1: probe: 0
[    1.895118] cxl_core:cxl_bus_probe:2077: cxl_nvdimm_bridge nvdimm-bridge0: probe: 0
[    1.925898] [drm] Found bochs VGA, ID 0xb0c5.
[    1.926157] [drm] Framebuffer size 16384 kB @ 0xfd000000, mmio @ 0x80000000.
[    1.927458] [drm] Found EDID data blob.
[    1.927804] [drm] Initialized bochs-drm 1.0.0 20130925 for 0000:00:01.0 on minor 0
[    1.929917] ppdev: user-space parallel port driver
[    1.932479] fbcon: bochs-drmdrmfb (fb0) is primary device
[    1.936465] Console: switching to colour frame buffer device 160x50
[    1.937759] bochs-drm 0000:00:01.0: [drm] fb0: bochs-drmdrmfb frame buffer device
[    1.945678] Error: Driver 'pcspkr' is already registered, aborting...

Debian GNU/Linux 12 kz-HP-EliteBook ttyS0

kz-HP-EliteBook login: root
Password:
Linux kz-HP-EliteBook 6.8.0 #5 SMP PREEMPT_DYNAMIC Sat Mar  1 19:11:50 +08 2025 x86_64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
Last login: Sun Mar  2 03:37:17 UTC 2025 on ttyS0
root@kz-HP-EliteBook:~#

</pre>

Example 2: boot up VM with CXL DCD setup: the device is directly attached to the only root port of a host bridge. The device has two dynamic capacity regions, with each region being 2GiB in size.
<pre>
~/cxl/qemu-dcd-v6/build/qemu-system-x86_64 \
    -s \
    -kernel ~/cxl/linux-kernel-dcd-2024-03-24/arch/x86/boot/bzImage \
    -append "root=/dev/sda rw console=ttyS0,115200 ignore_loglevel nokaslr \
             cxl_acpi.dyndbg=+fplm cxl_pci.dyndbg=+fplm cxl_core.dyndbg=+fplm \
             cxl_mem.dyndbg=+fplm cxl_pmem.dyndbg=+fplm cxl_port.dyndbg=+fplm \
             cxl_region.dyndbg=+fplm cxl_test.dyndbg=+fplm cxl_mock.dyndbg=+fplm \
             cxl_mock_mem.dyndbg=+fplm dax.dyndbg=+fplm dax_cxl.dyndbg=+fplm \
             device_dax.dyndbg=+fplm" \
    -smp 1 \
    -accel kvm \
    -serial mon:stdio \
    -nographic \
    -qmp tcp:localhost:4444,server,wait=off \
    -netdev user,id=network0,hostfwd=tcp::2024-:22 \
    -device e1000,netdev=network0 \
    -monitor telnet:127.0.0.1:12345,server,nowait \
    -drive file=~/cxl/qemu-dcd-v6/build/qemu.img,index=0,media=disk,format=raw \
    -machine q35,cxl=on -m 8G,maxmem=32G,slots=8 \
    -virtfs local,path=/lib/modules,mount_tag=modshare,security_model=mapped \
    -virtfs local,path=/home/kz,mount_tag=homeshare,security_model=mapped \
    -device pxb-cxl,bus_nr=12,bus=pcie.0,id=cxl.1 \
    -device cxl-rp,port=13,bus=cxl.1,id=root_port13,chassis=0,slot=2 \
    -object memory-backend-file,id=dhmem0,share=on,mem-path=/tmp/dhmem0.raw,size=4G \
    -object memory-backend-file,id=lsa0,share=on,mem-path=/tmp/lsa0.raw,size=512M \
    -device cxl-type3,bus=root_port13,volatile-dc-memdev=dhmem0,num-dc-regions=2,id=cxl-memdev0 \
    -M cxl-fmw.0.targets.0=cxl.1,cxl-fmw.0.size=4G,cxl-fmw.0.interleave-granularity=8K

e.g.

kz@kz-HP-EliteBook:~/cxl/qemu-dcd-v6/build$ ~/cxl/qemu-dcd-v6/build/qemu-system-x86_64 \
    -s \                                    ~/cxl/qemu-dcd-v6/build/qemu-system-x86_64 \
    -s \nel ~/cxl/linux-kernel-dcd-2024-03-24/arch/x86/boot/bzImage \
    -kernel ~/cxl/linux-kernel-dcd-2024-03-24/arch/x86/boot/bzImage \kaslr \
    -append "root=/dev/sda rw console=ttyS0,115200 ignore_loglevel nokaslr \m \
             cxl_acpi.dyndbg=+fplm cxl_pci.dyndbg=+fplm cxl_core.dyndbg=+fplm \
             cxl_mem.dyndbg=+fplm cxl_pmem.dyndbg=+fplm cxl_port.dyndbg=+fplm \m \
             cxl_region.dyndbg=+fplm cxl_test.dyndbg=+fplm cxl_mock.dyndbg=+fplm \
             cxl_mock_mem.dyndbg=+fplm dax.dyndbg=+fplm dax_cxl.dyndbg=+fplm \
             device_dax.dyndbg=+fplm" \
    -smp 1 \vm \
    -accel kvm \stdio \
    -serial mon:stdio \
    -nographic \alhost:4444,server,wait=off \
    -qmp tcp:localhost:4444,server,wait=off \4-:22 \
    -netdev user,id=network0,hostfwd=tcp::2024-:22 \
    -device e1000,netdev=network0 \,server,nowait \
    -monitor telnet:127.0.0.1:12345,server,nowait \dex=0,media=disk,format=raw \
    -drive file=~/cxl/qemu-dcd-v6/build/qemu.img,index=0,media=disk,format=raw \
    -machine q35,cxl=on -m 8G,maxmem=32G,slots=8 \hare,security_model=mapped \
    -virtfs local,path=/lib/modules,mount_tag=modshare,security_model=mapped \
    -virtfs local,path=/home/kz,mount_tag=homeshare,security_model=mapped \
    -device pxb-cxl,bus_nr=12,bus=pcie.0,id=cxl.1 \,chassis=0,slot=2 \
    -device cxl-rp,port=13,bus=cxl.1,id=root_port13,chassis=0,slot=2 \0.raw,size=4G \
    -object memory-backend-file,id=dhmem0,share=on,mem-path=/tmp/dhmem0.raw,size=4G \
    -object memory-backend-file,id=lsa0,share=on,mem-path=/tmp/lsa0.raw,size=512M \=cxl-memdev0 \
    -device cxl-type3,bus=root_port13,volatile-dc-memdev=dhmem0,num-dc-regions=2,id=cxl-memdev0 \
    -M cxl-fmw.0.targets.0=cxl.1,cxl-fmw.0.size=4G,cxl-fmw.0.interleave-granularity=8K
SeaBIOS (version rel-1.16.3-0-ga6ed6b701f0a-prebuilt.qemu.org)


iPXE (http://ipxe.org) 00:02.0 CA00 PCI2.10 PnP PMM+7EFD0890+7EF30890 CA00



Booting from ROM..
[    0.000000] Linux version 6.8.0 (kz@kz-HP-EliteBook) (gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0, G5
[    0.000000] Command line: root=/dev/sda rw console=ttyS0,115200 ignore_loglevel nokaslr           m
[    0.000000] KERNEL supported cpus:
[    0.000000]   Intel GenuineIntel
[    0.000000]   AMD AuthenticAMD
[    0.000000]   Hygon HygonGenuine
[    0.000000]   Centaur CentaurHauls
[    0.000000]   zhaoxin   Shanghai
[    0.000000] BIOS-provided physical RAM map:
[    0.000000] BIOS-e820: [mem 0x0000000000000000-0x000000000009fbff] usable
[    0.000000] BIOS-e820: [mem 0x000000000009fc00-0x000000000009ffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000000f0000-0x00000000000fffff] reserved
[    0.000000] BIOS-e820: [mem 0x0000000000100000-0x000000007ffdefff] usable
[    0.000000] BIOS-e820: [mem 0x000000007ffdf000-0x000000007fffffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000b0000000-0x00000000bfffffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000fed1c000-0x00000000fed1ffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000feffc000-0x00000000feffffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000fffc0000-0x00000000ffffffff] reserved
[    0.000000] BIOS-e820: [mem 0x0000000100000000-0x000000027fffffff] usable
[    0.000000] printk: debug: ignoring loglevel setting.
[    0.000000] NX (Execute Disable) protection: active
[    0.000000] APIC: Static calls initialized

...

[    1.968583] cxl_core:devm_cxl_add_port:907: cxl_mem mem0: endpoint2 added to port1
[    1.969198] cxl_core:cxl_bus_probe:2077: cxl_mem mem0: probe: 0

Debian GNU/Linux 12 kz-HP-EliteBook ttyS0

kz-HP-EliteBook login: root
Password:
Linux kz-HP-EliteBook 6.8.0 #5 SMP PREEMPT_DYNAMIC Sat Mar  1 19:11:50 +08 2025 x86_64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
root@kz-HP-EliteBook:~#

</pre>

### Bringing up network

Note: My friend Lv, Pingjie told me, with my .config setup, there is no E1000 device in the QEMU
Even with lspci, E1000 is not displayed, then there is no need to do the following operations.
in this case, you could have a try:

<pre>
replace
-device e1000,netdev=network0 \
to
-device virtio-net-pci,netdev=network0 \
</pre>

in the command example 1 and example 2 above.
As far as they say, virtio-net-pci has Better compatibility.

<pre>
ip link set dev enp0s2 up
dhclient enp0s2

e.g.
root@kz-HP-EliteBook:~# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: enp0s2: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff
root@kz-HP-EliteBook:~# ip link set dev enp0s2 up
root@kz-HP-EliteBook:~# [   64.192558] e1000: enp0s2 NIC Link is Up 1000 Mbps Full Duplex, Flow ContrX

root@kz-HP-EliteBook:~# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: enp0s2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 100
    link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff
    inet6 fec0::5054:ff:fe12:3456/64 scope site dynamic mngtmpaddr
       valid_lft 86393sec preferred_lft 14393sec
    inet6 fe80::5054:ff:fe12:3456/64 scope link
       valid_lft forever preferred_lft forever
root@kz-HP-EliteBook:~# ping www.baidu.com
ping: www.baidu.com: Temporary failure in name resolution
root@kz-HP-EliteBook:~# dhclient enp0s2
root@kz-HP-EliteBook:~# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: enp0s2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 100
    link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff
    inet 10.0.2.15/24 brd 10.0.2.255 scope global dynamic enp0s2
       valid_lft 86323sec preferred_lft 86323sec
    inet6 fec0::5054:ff:fe12:3456/64 scope site dynamic mngtmpaddr
       valid_lft 86300sec preferred_lft 14300sec
    inet6 fe80::5054:ff:fe12:3456/64 scope link
       valid_lft forever preferred_lft forever
root@kz-HP-EliteBook:~# ping www.baidu.com
PING www.baidu.com (36.152.44.132) 56(84) bytes of data.
64 bytes from 36.152.44.132 (36.152.44.132): icmp_seq=1 ttl=255 time=11.6 ms
64 bytes from 36.152.44.132 (36.152.44.132): icmp_seq=2 ttl=255 time=14.6 ms
^C
--- www.baidu.com ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 11.574/13.084/14.594/1.510 ms
root@kz-HP-EliteBook:~#

</pre>

### List CXL device

```
apt install pciutils
lspci
lspci | grep CXL
lspci -vvv
lspci -vvv -s 0d:00.0

e.g.
root@kz-HP-EliteBook:~# lspci
-bash: lspci: command not found
root@kz-HP-EliteBook:~# apt install pciutils
Reading package lists... Done
Building dependency tree... Done
The following additional packages will be installed:
  libpci3 pci.ids
Suggested packages:
  bzip2 wget | curl | lynx
The following NEW packages will be installed:
  libpci3 pci.ids pciutils
0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded.
Need to get 415 kB of archives.
After this operation, 1717 kB of additional disk space will be used.
Do you want to continue? [Y/n]
Get:1 https://deb.debian.org/debian stable/main amd64 pci.ids all 0.0~2023.04.11-1 [243 kB]
Get:2 https://deb.debian.org/debian stable/main amd64 libpci3 amd64 1:3.9.0-4 [67.4 kB]
Get:3 https://deb.debian.org/debian stable/main amd64 pciutils amd64 1:3.9.0-4 [104 kB]
Progress: [ 92%] [#####################################################.....]
root@kz-HP-EliteBook:~# lspci
00:00.0 Host bridge: Intel Corporation 82G33/G31/P35/P31 Express DRAM Controller
00:01.0 VGA compatible controller: Device 1234:1111 (rev 02)
00:02.0 Ethernet controller: Intel Corporation 82540EM Gigabit Ethernet Controller (rev 03)
00:03.0 Unclassified device [0002]: Red Hat, Inc. Virtio filesystem
00:04.0 Unclassified device [0002]: Red Hat, Inc. Virtio filesystem
00:05.0 Host bridge: Red Hat, Inc. QEMU PCIe Expander bridge
00:1f.0 ISA bridge: Intel Corporation 82801IB (ICH9) LPC Interface Controller (rev 02)
00:1f.2 SATA controller: Intel Corporation 82801IR/IO/IH (ICH9R/DO/DH) 6 port SATA Controller [AHCI mode] (rev 02)
00:1f.3 SMBus: Intel Corporation 82801I (ICH9 Family) SMBus Controller (rev 02)
0c:00.0 PCI bridge: Intel Corporation Device 7075
0d:00.0 CXL: Intel Corporation Device 0d93 (rev 01)
root@kz-HP-EliteBook:~# lspci | grep CXL
0d:00.0 CXL: Intel Corporation Device 0d93 (rev 01)
root@kz-HP-EliteBook:~# lspci -vvv -s 0d:00.0
0d:00.0 CXL: Intel Corporation Device 0d93 (rev 01) (prog-if 10 [CXL Memory Device (CXL 2.x)])
        Subsystem: Red Hat, Inc. Device 1100
        Physical Slot: 2
        Control: I/O+ Mem+ BusMaster+ SpecCycle- MemWINV- VGASnoop- ParErr- Stepping- SERR+ FastB2B- DisINTx+
        Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR- <PERR- INTx-
        Latency: 0
        Region 0: Memory at fe800000 (64-bit, non-prefetchable) [size=64K]
        Region 2: Memory at fe810000 (64-bit, non-prefetchable) [size=4K]
        Region 4: Memory at fe811000 (32-bit, non-prefetchable) [size=4K]
        Capabilities: [40] MSI-X: Enable+ Count=6 Masked-
                Vector table: BAR=4 offset=00000000
                PBA: BAR=4 offset=00000800
        Capabilities: [80] Express (v2) Endpoint, MSI 00
                DevCap: MaxPayload 128 bytes, PhantFunc 0, Latency L0s <64ns, L1 <1us
                        ExtTag- AttnBtn- AttnInd- PwrInd- RBE+ FLReset- SlotPowerLimit 0W
                DevCtl: CorrErr+ NonFatalErr+ FatalErr+ UnsupReq+
                        RlxdOrd- ExtTag- PhantFunc- AuxPwr- NoSnoop-
                        MaxPayload 128 bytes, MaxReadReq 128 bytes
                DevSta: CorrErr- NonFatalErr- FatalErr- UnsupReq- AuxPwr- TransPend-
                LnkCap: Port #0, Speed 2.5GT/s, Width x1, ASPM L0s, Exit Latency L0s <64ns
                        ClockPM- Surprise- LLActRep- BwNot- ASPMOptComp-
                LnkCtl: ASPM Disabled; RCB 64 bytes, Disabled- CommClk-
                        ExtSynch- ClockPM- AutWidDis- BWInt- AutBWInt-
                LnkSta: Speed 2.5GT/s, Width x1
                        TrErr- Train- SlotClk- DLActive- BWMgmt- ABWMgmt-
                DevCap2: Completion Timeout: Not Supported, TimeoutDis- NROPrPrP- LTR-
                         10BitTagComp- 10BitTagReq- OBFF Not Supported, ExtFmt+ EETLPPrefix+, MaxEETLPPrefixes 4
                         EmergencyPowerReduction Not Supported, EmergencyPowerReductionInit-
                         FRS- TPHComp- ExtTPHComp-
                         AtomicOpsCap: 32bit- 64bit- 128bitCAS-
                DevCtl2: Completion Timeout: 50us to 50ms, TimeoutDis- LTR- 10BitTagReq- OBFF Disabled,
                         AtomicOpsCtl: ReqEn-
                LnkCtl2: Target Link Speed: 2.5GT/s, EnterCompliance- SpeedDis-
                         Transmit Margin: Normal Operating Range, EnterModifiedCompliance- ComplianceSOS-
                         Compliance Preset/De-emphasis: -6dB de-emphasis, 0dB preshoot
                LnkSta2: Current De-emphasis Level: -6dB, EqualizationComplete- EqualizationPhase1-
                         EqualizationPhase2- EqualizationPhase3- LinkEqualizationRequest-
                         Retimer- 2Retimers- CrosslinkRes: unsupported
        Capabilities: [100 v1] Designated Vendor-Specific: Vendor=1e98 ID=0000 Rev=3 Len=60: CXL
                CXLCap: Cache- IO+ Mem+ Mem HW Init+ HDMCount 1 Viral-
                CXLCtl: Cache- IO+ Mem+ Cache SF Cov 0 Cache SF Gran 0 Cache Clean- Viral-
                CXLSta: Viral-
                CXLSta2:        ResetComplete+ ResetError- PMComplete-
                Cache Size Not Reported
                Range1: 0000000000000000-00000000ffffffff
                        Valid+ Active+ Type=CDAT Class=CDAT interleave=0 timeout=1s
                Range2: 0000000000000000-ffffffffffffffff
                        Valid- Active- Type=Volatile Class=DRAM interleave=0 timeout=1s
        Capabilities: [13c v1] Designated Vendor-Specific: Vendor=1e98 ID=0008 Rev=0 Len=36: CXL
                Block1: BIR: bar0, ID: component registers, offset: 0000000000000000
                Block2: BIR: bar2, ID: CXL device registers, offset: 0000000000000000
        Capabilities: [160 v1] Designated Vendor-Specific: Vendor=1e98 ID=0005 Rev=0 Len=16: CXL
                GPF Phase 2 Duration: 3s
                GPF Phase 2 Power: 51mW
        Capabilities: [170 v1] Designated Vendor-Specific: Vendor=1e98 ID=0007 Rev=2 Len=32: CXL
                FBCap:  Cache- IO+ Mem+ 68BFlit+ MltLogDev- 256BFlit- PBRFlit-
                FBCtl:  Cache- IO+ Mem- SynHdrByp- DrftBuf- 68BFlit- MltLogDev- RCD- Retimer1- Retimer2- 256BFlit- PBRFlit-
                FBSta:  Cache- IO+ Mem+ SynHdrByp- DrftBuf- 68BFlit+ MltLogDev- 256BFlit- PBRFlit-
                FBModTS:        Received FB Data: 0000ef
                FBCap2: NOPHint-
                FBCtl2: NOPHint-
                FBSta2: NOPHintInfo: 0
        Capabilities: [190 v1] Data Object Exchange
                DOECap: IntSup+
                        Interrupt Message Number 000
                DOECtl: IntEn-
                DOESta: Busy- IntSta- Error- ObjectReady-
        Capabilities: [200 v2] Advanced Error Reporting
                UESta:  DLP- SDES- TLP- FCP- CmpltTO- CmpltAbrt- UnxCmplt- RxOF- MalfTLP- ECRC- UnsupReq- ACSViol-
                UEMsk:  DLP- SDES- TLP- FCP- CmpltTO- CmpltAbrt- UnxCmplt- RxOF- MalfTLP- ECRC- UnsupReq- ACSViol-
                UESvrt: DLP+ SDES+ TLP- FCP+ CmpltTO- CmpltAbrt- UnxCmplt- RxOF+ MalfTLP+ ECRC- UnsupReq- ACSViol-
                CESta:  RxErr- BadTLP- BadDLLP- Rollover- Timeout- AdvNonFatalErr-
                CEMsk:  RxErr- BadTLP- BadDLLP- Rollover- Timeout- AdvNonFatalErr+
                AERCap: First Error Pointer: 00, ECRCGenCap+ ECRCGenEn- ECRCChkCap+ ECRCChkEn-
                        MultHdrRecCap- MultHdrRecEn- TLPPfxPres- HdrLogCap-
                HeaderLog: 00000000 00000000 00000000 00000000
        Kernel driver in use: cxl_pci
        Kernel modules: cxl_pci

root@kz-HP-EliteBook:~#
```

## Access CXL memory device emulated with QEMU

After the guest VM is started, we can install ndctl tool for managing the CXL device.

_**note: Following steps happen in QEMU VM.**_

### Install ndctl from source code
<pre>
apt install git
git clone https://github.com/pmem/ndctl.git
if command above does not work, try cmd below.
ssh-keygen -t rsa -b 4096 -C "liukezhao@gmail.com"
cat ~/.ssh/id_rsa.pub
copy whole content to ssh key of your github account
(github: setting->SSH and GPG keys->SSH keys->New SSH keys)
git clone https://github.com/pmem/ndctl.git
cd ndctl

For Ubuntu (e.g. jammy used in debootstrap command above):
Please do additional two steps:
1. sudo apt install software-properties-common
2. sudo add-apt-repository universe

sudo apt update
apt install meson pkg-config libkmod-dev libudev-dev uuid-dev libjson-c-dev libtraceevent-dev libtracefs-dev asciidoctor libkeyutils-dev libiniparser-dev bash-completion

meson setup build
meson compile -C build
meson install -C build

e.g.

root@kz-HP-EliteBook:~# ssh-keygen -t rsa -b 4096 -C "liukezhao@gmail.com"
Generating public/private rsa key pair.
Enter file in which to save the key (/root/.ssh/id_rsa):
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /root/.ssh/id_rsa
Your public key has been saved in /root/.ssh/id_rsa.pub
The key fingerprint is:
SHA256:pUfaB/DMdF/aCbgrb91ssuesY0QmvIbnkeTD5fearSA liukezhao@gmail.com
The key's randomart image is:
+---[RSA 4096]----+
|        . . o.  .|
|         * o ..+.|
|          O . o..|
|         * * +   |
|        S B @    |
|         + % o . |
|          E * + .|
|           = *.B.|
|          . .o%=.|
+----[SHA256]-----+
root@kz-HP-EliteBook:~#
root@kz-HP-EliteBook:~# cat ~/.ssh/id_rsa.pub
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDtqeEqnp9lGlaQs9......
root@kz-HP-EliteBook:~# git clone git@github.com:pmem/ndctl.git
Cloning into 'ndctl'...
remote: Enumerating objects: 11782, done.
remote: Counting objects: 100% (1096/1096), done.
remote: Compressing objects: 100% (208/208), done.
remote: Total 11782 (delta 963), reused 886 (delta 870), pack-reused 10686 (from 3)
Receiving objects: 100% (11782/11782), 3.79 MiB | 408.00 KiB/s, done.
Resolving deltas: 100% (8664/8664), done.
root@kz-HP-EliteBook:~/ndctl# meson setup build
The Meson build system
Version: 1.0.1
Source dir: /root/ndctl
Build dir: /root/ndctl/build
Build type: native build
Project name: ndctl
Project version: 80
C compiler for the host machine: cc (gcc 12.2.0 "cc (Debian 12.2.0-14) 12.2.0")
C linker for the host machine: cc ld.bfd 2.40
Host machine cpu family: x86_64
Host machine cpu: x86_64
Compiler for C supports arguments -Wchar-subscripts: YES
Compiler for C supports arguments -Wformat-security: YES
Compiler for C supports arguments -Wmissing-declarations: YES
Compiler for C supports arguments -Wmissing-prototypes: YES
Compiler for C supports arguments -Wnested-externs : NO
Compiler for C supports arguments -Wshadow: YES
Compiler for C supports arguments -Wsign-compare: YES
Compiler for C supports arguments -Wstrict-prototypes: YES
Compiler for C supports arguments -Wtype-limits: YES
Compiler for C supports arguments -Wmaybe-uninitialized: YES
Compiler for C supports arguments -Wdeclaration-after-statement: YES
Compiler for C supports arguments -Wunused-result: YES
Program git found: YES (/usr/bin/git)
Program env found: YES (/usr/bin/env)
Found pkg-config: /usr/bin/pkg-config (1.8.1)
Run-time dependency libkmod found: YES 30
Run-time dependency libudev found: YES 252
Run-time dependency uuid found: YES 2.38.1
Run-time dependency json-c found: YES 0.16
Run-time dependency libtraceevent found: YES 1.7.1
Run-time dependency libtracefs found: YES 1.6.4
Program asciidoctor found: YES (/usr/bin/asciidoctor)
Run-time dependency systemd found: YES 252
Run-time dependency udev found: YES 252
Library keyutils found: YES
Message: Looking for iniparser include headers ['iniparser.h', 'dictionary.h']
Has header "iniparser.h" : NO
Has header "iniparser.h" : YES
Has header "dictionary.h" : YES
Library iniparser found: YES
Has header "dlfcn.h" : YES
Has header "inttypes.h" : YES
Has header "keyutils.h" : YES
Has header "linux/version.h" : YES
Has header "memory.h" : YES
Has header "stdint.h" : YES
Has header "stdlib.h" : YES
Has header "strings.h" : YES
Has header "string.h" : YES
Has header "sys/stat.h" : YES
Has header "sys/types.h" : YES
Has header "unistd.h" : YES
Header "signal.h" has symbol "BUS_MCEERR_AR" : YES
Header "linux/mman.h" has symbol "MAP_SHARED_VALIDATE" : YES
Header "linux/mman.h" has symbol "MAP_SYNC" : YES
Checking for function "secure_getenv" : YES
Checking for function "__secure_getenv" : NO
Checking for function "json_object_new_uint64" with dependency json-c: YES
Configuring config.h using configuration
Program create.sh found: YES (/root/ndctl/test/create.sh)
Program clear.sh found: YES (/root/ndctl/test/clear.sh)
Program pmem-errors.sh found: YES (/root/ndctl/test/pmem-errors.sh)
Program daxdev-errors.sh found: YES (/root/ndctl/test/daxdev-errors.sh)
Program multi-dax.sh found: YES (/root/ndctl/test/multi-dax.sh)
Program btt-check.sh found: YES (/root/ndctl/test/btt-check.sh)
Program label-compat.sh found: YES (/root/ndctl/test/label-compat.sh)
Program sector-mode.sh found: YES (/root/ndctl/test/sector-mode.sh)
Program inject-error.sh found: YES (/root/ndctl/test/inject-error.sh)
Program btt-errors.sh found: YES (/root/ndctl/test/btt-errors.sh)
Program btt-pad-compat.sh found: YES (/root/ndctl/test/btt-pad-compat.sh)
Program firmware-update.sh found: YES (/root/ndctl/test/firmware-update.sh)
Program rescan-partitions.sh found: YES (/root/ndctl/test/rescan-partitions.sh)
Program inject-smart.sh found: YES (/root/ndctl/test/inject-smart.sh)
Program monitor.sh found: YES (/root/ndctl/test/monitor.sh)
Program max_available_extent_ns.sh found: YES (/root/ndctl/test/max_available_extent_ns.sh)
Program pfn-meta-errors.sh found: YES (/root/ndctl/test/pfn-meta-errors.sh)
Program track-uuid.sh found: YES (/root/ndctl/test/track-uuid.sh)
Program cxl-topology.sh found: YES (/bin/bash /root/ndctl/test/cxl-topology.sh)
Program cxl-region-sysfs.sh found: YES (/bin/bash /root/ndctl/test/cxl-region-sysfs.sh)
Program cxl-labels.sh found: YES (/bin/bash /root/ndctl/test/cxl-labels.sh)
Program cxl-create-region.sh found: YES (/bin/bash /root/ndctl/test/cxl-create-region.sh)
Program cxl-xor-region.sh found: YES (/bin/bash /root/ndctl/test/cxl-xor-region.sh)
Program cxl-update-firmware.sh found: YES (/root/ndctl/test/cxl-update-firmware.sh)
Program cxl-events.sh found: YES (/bin/bash /root/ndctl/test/cxl-events.sh)
Program cxl-sanitize.sh found: YES (/bin/bash /root/ndctl/test/cxl-sanitize.sh)
Program cxl-destroy-region.sh found: YES (/bin/bash /root/ndctl/test/cxl-destroy-region.sh)
Program cxl-qos-class.sh found: YES (/root/ndctl/test/cxl-qos-class.sh)
Program cxl-poison.sh found: YES (/bin/bash /root/ndctl/test/cxl-poison.sh)
Program nfit-security.sh found: YES (/root/ndctl/test/nfit-security.sh)
Program cxl-security.sh found: YES (/root/ndctl/test/cxl-security.sh)
Run-time dependency bash-completion found: YES 2.11
Build targets in project: 104

Found ninja-1.11.1 at /usr/bin/ninja
root@kz-HP-EliteBook:~/ndctl#
root@kz-HP-EliteBook:~/ndctl# meson compile -C build
INFO: autodetecting backend as ninja
INFO: calculating backend command to run: /usr/bin/ninja -C /root/ndctl/build
ninja: Entering directory `/root/ndctl/build'
[245/245] Generating sles/ndctl.spec.sles.in with a custom command
root@kz-HP-EliteBook:~/ndctl#
root@kz-HP-EliteBook:~/ndctl# meson compile -C build
INFO: autodetecting backend as ninja
INFO: calculating backend command to run: /usr/bin/ninja -C /root/ndctl/build
ninja: Entering directory `/root/ndctl/build'
[245/245] Generating sles/ndctl.spec.sles.in with a custom command
root@kz-HP-EliteBook:~/ndctl# meson install -C build
ninja: Entering directory `/root/ndctl/build'
[3/3] Generating sles/ndctl.spec.sles.in with a custom command
Installing daxctl/lib/libdaxctl.so.1.0.6 to /usr/lib
Installing daxctl/lib/libdaxctl.pc to /usr/lib/pkgconfig
Installing ndctl/lib/libndctl.so.6.4.21 to /usr/lib
Installing ndctl/lib/libndctl.pc to /usr/lib/pkgconfig
Installing cxl/lib/libcxl.so.1.0.7 to /usr/lib
Installing cxl/lib/libcxl.pc to /usr/lib/pkgconfig
Installing ndctl/ndctl to /usr/bin
Installing daxctl/daxctl to /usr/bin
Installing cxl/cxl to /usr/bin
Installing Documentation/ndctl/ndctl.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-wait-scrub.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-start-scrub.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-zero-labels.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-read-labels.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-write-labels.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-init-labels.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-check-labels.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-enable-region.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-disable-region.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-enable-dimm.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-disable-dimm.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-enable-namespace.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-disable-namespace.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-create-namespace.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-destroy-namespace.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-check-namespace.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-clear-errors.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-inject-error.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-inject-smart.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-update-firmware.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-list.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-monitor.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-setup-passphrase.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-update-passphrase.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-remove-passphrase.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-freeze-security.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-sanitize-dimm.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-load-keys.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-wait-overwrite.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-read-infoblock.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-write-infoblock.1 to /usr/share/man/man1
Installing Documentation/ndctl/ndctl-activate-firmware.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-list.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-migrate-device-model.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-reconfigure-device.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-online-memory.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-offline-memory.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-disable-device.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-enable-device.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-create-device.1 to /usr/share/man/man1
Installing Documentation/daxctl/daxctl-destroy-device.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-list.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-read-labels.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-write-labels.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-zero-labels.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-enable-memdev.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-disable-memdev.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-enable-port.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-disable-port.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-disable-bus.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-set-partition.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-reserve-dpa.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-free-dpa.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-create-region.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-disable-region.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-enable-region.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-destroy-region.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-monitor.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-update-firmware.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-set-alert-config.1 to /usr/share/man/man1
Installing Documentation/cxl/cxl-wait-sanitize.1 to /usr/share/man/man1
Installing Documentation/cxl/lib/libcxl.3 to /usr/share/man/man3
Installing Documentation/cxl/lib/cxl_new.3 to /usr/share/man/man3
Installing /root/ndctl/ndctl/libndctl.h to /usr/include/ndctl/
Installing /root/ndctl/ndctl/ndctl.h to /usr/include/ndctl/
Installing /root/ndctl/daxctl/libdaxctl.h to /usr/include/daxctl/
Installing /root/ndctl/cxl/libcxl.h to /usr/include/cxl/
Installing /root/ndctl/daxctl/lib/daxctl.conf to /usr/share/daxctl
Installing /root/ndctl/ndctl/ndctl-monitor.service to /lib/systemd/system
Installing /root/ndctl/ndctl/monitor.conf to /etc/ndctl.conf.d
Installing /root/ndctl/ndctl/ndctl.conf to /etc/ndctl.conf.d
Installing /root/ndctl/ndctl/keys.readme to /etc/ndctl/keys
Installing /root/ndctl/daxctl/daxctl.example.conf to /etc/daxctl.conf.d
Installing /root/ndctl/daxctl/90-daxctl-device.rules to /lib/udev/rules.d
Installing /root/ndctl/daxctl/daxdev-reconfigure@.service to /lib/systemd/system
Installing /root/ndctl/cxl/cxl-monitor.service to /lib/systemd/system
Installing /root/ndctl/contrib/ndctl to /usr/share/bash-completion/completions
Installing /root/ndctl/contrib/ndctl to /usr/share/bash-completion/completions
Installing /root/ndctl/contrib/ndctl to /usr/share/bash-completion/completions
Installing /root/ndctl/contrib/nvdimm-security.conf to /etc/modprobe.d
Installing symlink pointing to libdaxctl.so.1.0.6 to /usr/lib/libdaxctl.so.1
Installing symlink pointing to libdaxctl.so.1 to /usr/lib/libdaxctl.so
Installing symlink pointing to libndctl.so.6.4.21 to /usr/lib/libndctl.so.6
Installing symlink pointing to libndctl.so.6 to /usr/lib/libndctl.so
Installing symlink pointing to libcxl.so.1.0.7 to /usr/lib/libcxl.so.1
Installing symlink pointing to libcxl.so.1 to /usr/lib/libcxl.so
root@kz-HP-EliteBook:~/ndctl#

</pre>

After a successful compile, three tools will be generated under the build directory.
<pre>
root@kz-HP-EliteBook:~/ndctl# ls build/daxctl/daxctl -lh
-rwxr-xr-x 1 root root 181K Mar  2 02:26 build/daxctl/daxctl
root@kz-HP-EliteBook:~/ndctl# ls build/cxl/cxl -lh
-rwxr-xr-x 1 root root 351K Mar  2 02:26 build/cxl/cxl
root@kz-HP-EliteBook:~/ndctl# ls build/daxctl/daxctl -lh
-rwxr-xr-x 1 root root 181K Mar  2 02:26 build/daxctl/daxctl
root@kz-HP-EliteBook:~/ndctl#
</pre>

How to uninstall
<pre>
ninja -C build uninstall
</pre>
or
<pre>
meson uninstall
</pre>

### Load cxl drivers and show CXL memory device
Note: No need to do modprobe, if you use my .config, as they are all compiled to kernel bzImage
<pre>
modprobe -a cxl_acpi cxl_core cxl_pci cxl_port cxl_mem cxl_pmem

e.g. (output based onstart_qemu_dcd.sh)
root@kz-HP-EliteBook:~/ndctl# cxl list -u
{
  "memdev":"mem0",
  "serial":"0",
  "host":"0000:0d:00.0",
  "firmware_version":"BWFW VERSION 00"
}
root@kz-HP-EliteBook:~/ndctl#

e.g. (output based start_qemu_pmem.sh)
root@kz-HP-EliteBook:~# cxl list -Mu
{
  "memdev":"mem0",
  "pmem_size":"512.00 MiB (536.87 MB)",
  "pmem_qos_class":0,
  "serial":"0",
  "host":"0000:0d:00.0",
  "firmware_version":"BWFW VERSION 00"
}
root@kz-HP-EliteBook:~#

</pre>

Output below are all based on start_qemu_pmem.sh (Example 1, not Example 2)

### To convert CXL memory into system ram, we need extra steps.
**Create a cxl region:**
<pre>
cxl create-region -m -d decoder0.0 -w 1 mem0 -s 512M

e.g.
root@kz-HP-EliteBook:~# cxl create-region -m -d decoder0.0 -w 1 mem0 -s 512M
[   40.955891] cxl_core:cxl_region_probe:3269: cxl_region region0: config state: 0
[   40.956308] cxl_core:cxl_bus_probe:2077: cxl_region region0: probe: -6
[   40.956662] cxl_core:devm_cxl_add_region:2429: cxl_acpi ACPI0017:00: decoder0.0: created region0
[   40.963211] cxl_core:cxl_dpa_alloc:685: cxl decoder2.0: DPA Allocation start: 0x0000000000000000 l0
[   40.963882] cxl_core:__cxl_dpa_reserve:450: cxl_port endpoint2: decoder2.0: [mem 0x00000000-0x1fff2
[   40.964512] cxl_core:cxl_port_attach_region:1010: cxl region0: mem0:endpoint2 decoder2.0 add: mem01
[   40.965502] cxl_core:cxl_port_attach_region:1010: cxl region0: pci0000:0c:port1 decoder1.0 add: me1
[   40.966236] cxl_core:cxl_port_setup_targets:1267: cxl region0: pci0000:0c:port1 iw: 1 ig: 256
[   40.966691] cxl_core:cxl_port_setup_targets:1291: cxl region0: pci0000:0c:port1 target[0] = 0000:00
[   40.967309] cxl_core:cxl_calc_interleave_pos:1847: cxl_mem mem0: decoder:decoder2.0 parent:0000:0d0
[   40.968041] cxl_core:cxl_region_attach:2048: cxl decoder2.0: Test cxl_calc_interleave_pos(): succe0
[   40.969041] cxl region0: Bypassing cpu_cache_invalidate_memregion() for testing!
[   40.970478] cxl_core:cxl_bus_probe:2077: cxl_pmem_region pmem_region0: probe: 0
[   40.971443] cxl_core:devm_cxl_add_pmem_region:2946: cxl_region region0: region0: register pmem_reg0
[   40.972540] cxl_core:cxl_bus_probe:2077: cxl_region region0: probe: 0
{
  "region":"region0",
  "resource":"0xa90000000",
  "size":"512.00 MiB (536.87 MB)",
  "type":"pmem",
  "interleave_ways":1,
  "interleave_granularity":256,
  "decode_state":"commit",
  "mappings":[
    {
      "position":0,
      "memdev":"mem0",
      "decoder":"decoder2.0"
    }
  ]
}
cxl region: cmd_create_region: created 1 region
root@kz-HP-EliteBook:~#

</pre>

**Create a namespace for the region:**

<pre>
ndctl create-namespace -m dax -r region0

(This command is very instable, most of the time it will show an error like
e.g.
root@kz-HP-EliteBook:~# ndctl create-namespace -m dax -r region0
failed to create namespace: No space left on device
I have no idea about it, but tested many times, seems use start_qemu_pmem.sh has less chance to succeed, instead run the command directly has chance to be successful as below. will you good luck, if you know the root case, please send me message via liukezhao@gmail.com, thanks.
)

e.g.
root@kz-HP-EliteBook:~# ndctl create-namespace -m dax -r region0
[   87.577281] cxl_pci:__cxl_pci_mbox_send_cmd:259: cxl_pci 0000:0d:00.0: Sending command: 0x4103
[   87.577708] cxl_pci:cxl_pci_mbox_wait_for_doorbell:73: cxl_pci 0000:0d:00.0: Doorbell wait took 0ms
[   87.579829] cxl_pci:__cxl_pci_mbox_send_cmd:259: cxl_pci 0000:0d:00.0: Sending command: 0x4103
[   87.580259] cxl_pci:cxl_pci_mbox_wait_for_doorbell:73: cxl_pci 0000:0d:00.0: Doorbell wait took 0ms
[   87.582226] cxl_pci:__cxl_pci_mbox_send_cmd:259: cxl_pci 0000:0d:00.0: Sending command: 0x4103
[   87.582647] cxl_pci:cxl_pci_mbox_wait_for_doorbell:73: cxl_pci 0000:0d:00.0: Doorbell wait took 0ms
[   87.584531] cxl_pci:__cxl_pci_mbox_send_cmd:259: cxl_pci 0000:0d:00.0: Sending command: 0x4103
...

[   90.096851] cxl_pci:cxl_pci_mbox_wait_for_doorbell:73: cxl_pci 0000:0d:00.0: Doorbell wait took 0ms
[   90.098805] cxl_pci:__cxl_pci_mbox_send_cmd:259: cxl_pci 0000:0d:00.0: Sending command: 0x4103
[   90.099242] cxl_pci:cxl_pci_mbox_wait_for_doorbell:73: cxl_pci 0000:0d:00.0: Doorbell wait took 0ms
[   90.101217] cxl_pci:__cxl_pci_mbox_send_cmd:259: cxl_pci 0000:0d:00.0: Sending command: 0x4103
[   90.101636] cxl_pci:cxl_pci_mbox_wait_for_doorbell:73: cxl_pci 0000:0d:00.0: Doorbell wait took 0ms
[   90.102942] cxl_pci:__cxl_pci_mbox_send_cmd:259: cxl_pci 0000:0d:00.0: Sending command: 0x4103
[   90.103382] cxl_pci:cxl_pci_mbox_wait_for_doorbell:73: cxl_pci 0000:0d:00.0: Doorbell wait took 0ms
[   90.108989] dax:alloc_dev_dax_range:1036:  dax0.0: alloc range[0]: 0x0000000a90a00000:0x0000000aaff

{
  "dev":"namespace0.0",
  "mode":"devdax",
  "map":"dev",
  "size":"502.00 MiB (526.39 MB)",
  "uuid":"c59c01e0-ed57-415f-8f62-bcffa7b2b459",
  "daxregion":{
    "id":0,
    "size":"502.00 MiB (526.39 MB)",
    "align":2097152,
    "devices":[
      {
        "chardev":"dax0.0",
        "size":"502.00 MiB (526.39 MB)",
        "target_node":1,
        "align":2097152,
        "mode":"devdax"
      }
    ]
  },
  "align":2097152
}
root@kz-HP-EliteBook:~#

</pre>

**Converting a regular devdax mode device to system-ram mode with daxctl:**

<pre>
echo offline > /sys/devices/system/memory/auto_online_blocks
daxctl reconfigure-device --mode=system-ram --no-online dax0.0

e.g.
Note: auto_online_blockes must be disabled.

root@kz-HP-EliteBook:~# cat /sys/devices/system/memory/auto_online_blocks
online                  daxctl reconfigure-device --mode=system-ram --no-online dax0.0
root@kz-HP-EliteBook:~# echo offline > /sys/devices/system/memory/auto_online_blocks
root@kz-HP-EliteBook:~# cat /sys/devices/system/memory/auto_online_blocks
offline                 daxctl reconfigure-device --mode=system-ram --no-online dax0.0
[ 1135.826950] Fallback order for Node 1: 0 evice --mode=system-ram --no-online dax0.0
[ 1135.826953] Built 1 zonelists, mobility grouping on.  Total pages: 2009453
[ 1135.827439] Policy zone: Normal
[
  {
    "chardev":"dax0.0",
    "size":526385152,
    "target_node":1,
    "align":2097152,
    "mode":"system-ram",
    "online_memblocks":0,
    "total_memblocks":3
  }
]
reconfigured 1 device
root@kz-HP-EliteBook:~#

</pre>

**Show system memory:**

<pre>
root@kz-HP-EliteBook:~# lsmem
RANGE                                  SIZE   STATE REMOVABLE   BLOCK
0x0000000000000000-0x000000007fffffff    2G  online       yes    0-15
0x0000000100000000-0x000000027fffffff    6G  online       yes   32-79
0x0000000a98000000-0x0000000aafffffff  384M offline           339-341

Memory block size:       128M
Total online memory:       8G
Total offline memory:    384M
root@kz-HP-EliteBook:~#

</pre>

After that, we can see a new 128M memory block has shown up.

## References:

1. [Wiki](https://en.wikipedia.org/wiki/Compute_Express_Link)
2. [Compute Express Link (CXL)](https://qemu-project.gitlab.io/qemu/system/devices/cxl.html)
3. [CXL mailing list](https://lore.kernel.org/linux-cxl/)
4. [Setting up QEMU emulation of CXL](https://sunfishho.github.io/jekyll/update/2022/07/07/setting-up-qemu-cxl.html#:~:text=Setting%20up%20QEMU%20emulation%20of%20CXL%201%20Introduction,rootfs%20...%206%20Booting%20up%20the%20Kernel%20)
5. [Basic: CXL Test with CXL emulation in QEMU](https://github.com/moking/moking.github.io/wiki/Basic:-CXL-test-with-CXL-emulation-in-QEMU)



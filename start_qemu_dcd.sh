#!/bin/bash

QEMU_BIN="$HOME/cxl/qemu-dcd-v6/build/qemu-system-x86_64"
KERNEL_IMG="$HOME/cxl/linux-kernel-dcd-2024-03-24/arch/x86/boot/bzImage"
DISK_IMG="$HOME/cxl/qemu-dcd-v6/build/qemu.img"

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

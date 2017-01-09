# ansible-playbook -i ./vagrant.py --limit fedora_upstream build_kpatch.yml

#!/bin/bash

KERNEL_TAG=${KERNEL_TAG:-v4.8}


# Install pre-requisites
#
sudo dnf builddep -y kernel
sudo dnf install -y ccache
ccache --max-size=5G
sudo dnf install -y git patchutils
sudo dnf install -y curl jq

# Boot loader hack :(
sudo dnf install -y grub2
sudo grub2-mkconfig -o /etc/grub2.cfg
sudo grub2-install /dev/vda

# Determine latest tag and download a tarball
#
KERNEL_TAG=${KERNEL_TAG:-$(curl -s 'https://api.github.com/repos/torvalds/linux/tags' | jq --raw-output ".[0] | .name")}
curl -L https://github.com/torvalds/linux/archive/$KERNEL_TAG.tar.gz | tar zxv
mv linux-${KERNEL_TAG#v} linux

# Steal the distribution configuration and assume defaults for new options
#
cd linux
cp /boot/config-$(uname -r) .config
yes "" | make oldconfig

# Build and install the kernel
#
make -j$(nproc) && \
  make -j$(nproc) modules && \
  sudo make modules_install && \
  sudo make install
KVER=$(make -s kernelversion)

# Set the default kernel for SYSLINUX bootloader
#
#if [[ -e /etc/extlinux.conf ]]; then
#  LABEL=$(sudo grep "^label.*$KVER" /etc/extlinux.conf | cut -d' ' -f2-)
#  sudo cp /boot/extlinux/extlinux.conf{,.bak}
#  sudo sed -i "s/^default.*/default $LABEL/" /boot/extlinux/extlinux.conf
#fi

# Set the default kernel for GRUB bootloader
#
sudo grubby --set-default /boot/vmlinuz-$KVER

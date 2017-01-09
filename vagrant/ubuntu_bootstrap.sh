sudo apt-get install -y make gcc libelf-dev

sudo apt-get install -y dpkg-dev
sudo apt-get build-dep -y linux

# optional, but highly recommended
sudo apt-get install -y ccache
ccache --max-size=5G

# Add ddebs repository
codename=$(lsb_release -sc)
sudo tee /etc/apt/sources.list.d/ddebs.list << EOF
deb http://ddebs.ubuntu.com/ ${codename} main restricted universe multiverse
deb http://ddebs.ubuntu.com/ ${codename}-security main restricted universe multiverse
deb http://ddebs.ubuntu.com/ ${codename}-updates main restricted universe multiverse
deb http://ddebs.ubuntu.com/ ${codename}-proposed main restricted universe multiverse
EOF

# add APT key
wget -Nq http://ddebs.ubuntu.com/dbgsym-release-key.asc -O- | sudo apt-key add -
sudo apt-get update && sudo apt-get install -y linux-image-$(uname -r)-dbgsym

sudo apt-get install -y git patchutils

# Upgrade the kernel to 4.4
sudo apt-get install --install-recommends linux-generic-lts-xenial

# diff --git a/kpatch-build/kpatch-build b/kpatch-build/kpatch-build
# index 7ebf41c..44aed98 100755
# --- a/kpatch-build/kpatch-build
# +++ b/kpatch-build/kpatch-build
# @@ -432,7 +432,9 @@ else
#                 # The linux-source packages are formatted like the following for:
#                 # ubuntu: linux-source-3.13.0_3.13.0-24.46_all.deb
#                 # debian: linux-source-3.14_3.14.7-1_all.deb
# -               pkgver="${KVER}_$(dpkg-query -W -f='${Version}' linux-image-$ARCHVERSION)"
# +               ver=$(dpkg-query -W -f='${Version}' linux-image-$ARCHVERSION)
# +               ver=${ver%~*}
# +               pkgver="${KVER}_$ver"
#                 pkgname="linux-source-${pkgver}_all"
#  
#                 cd $TEMPDIR

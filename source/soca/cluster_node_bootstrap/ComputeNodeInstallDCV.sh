#!/bin/bash -xe

# This script is called by ImageBuilder to install packages required by Linux Desktop instances
# It is also called when a desktop instance starts so needs to detect if packages have already
# been installed.
# GPU support is enabled and DCV is configured by ComputeNodeStartDCV.sh

function on_exit {
    rc=$?
    info "Exiting with rc=$rc"
    exit $rc
}
trap on_exit EXIT

function info {
    echo "$(date):INFO: $1"
}

function error {
    echo "$(date):ERROR: $1"
}

info "Starting $0"

source /etc/environment
source /root/config.cfg
if [ -e /etc/profile.d/profile ]; then
    source /etc/profile.d/proxy.sh
fi

AWS=$(which aws)
INSTANCE_FAMILY=`curl --silent  http://169.254.169.254/latest/meta-data/instance-type | cut -d. -f1`
echo "Detected Instance family $INSTANCE_FAMILY"
GPU_INSTANCE_FAMILY=(g3 g4 g4dn)

scriptdir=$(dirname $(readlink -f $0))
export SOCA_BASE_OS=$($scriptdir/get-base-os.sh)

# Install Gnome or  Mate Desktop
if [[ $SOCA_BASE_OS == "rhel7" ]]
then
  yum groupinstall "Server with GUI" -y
elif [[ $SOCA_BASE_OS == "amazonlinux2" ]]
then
  yum install -y $(echo ${DCV_AMAZONLINUX_PKGS[*]})
  amazon-linux-extras install -y mate-desktop1.x
  bash -c 'echo PREFERRED=/usr/bin/mate-session > /etc/sysconfig/desktop'
else
  # Centos7
  if ! yum groupinstall -y "GNOME Desktop"; then
    error "Failed to install GNOME Desktop"
    yum grouplist
    yum grouplist -y "gnome-desktop"
  fi
fi

# Install latest NVIDIA driver if GPU instance is detected
# This isn't installed by ImageBuilder because I don't know if it causes problems if it is installed on a non-GPU instance
if [[ "${GPU_INSTANCE_FAMILY[@]}" =~ "${INSTANCE_FAMILY}" ]];
then
    # clean previously installed drivers
    echo "Detected GPU instance .. installing NVIDIA Drivers"
    cd /root
    rm -f /root/NVIDIA-Linux-x86_64*.run
    $AWS s3 cp --quiet --recursive s3://ec2-linux-nvidia-drivers/latest/ .
    rm -rf /tmp/.X*
    /bin/sh /root/NVIDIA-Linux-x86_64*.run -q -a -n -X -s
    NVIDIAXCONFIG=$(which nvidia-xconfig)
    $NVIDIAXCONFIG --preserve-busid --enable-all-gpus
fi

# Download and Install DCV
cd /root
if [ ! -e $DCV_TGZ ]; then
    wget $DCV_URL
    if [[ $(md5sum $DCV_TGZ | awk '{print $1}') != $DCV_HASH ]];  then
        echo -e "FATAL ERROR: Checksum for DCV failed. File may be compromised." > /etc/motd
        exit 1
    fi
    tar zxvf $DCV_TGZ
    rm $DCV_TGZ
fi

# Install DCV server and Xdcv
cd nice-dcv-$DCV_VERSION
if ! yum list installed nice-dcv-server; then
    yum install -y nice-dcv-server*.rpm
fi
if ! yum list installed nice-xdcv; then
    yum install -y nice-xdcv-*.rpm
fi

# Enable DCV support for USB remotization
if ! yum list installed epel-release; then
    yum install -y epel-release || amazon-linux-extras install -y epel
fi
if ! yum list installed dkms; then
    yum install -y dkms
fi
#DCVUSBDRIVERINSTALLER=$(which dcvusbdriverinstaller)
#$DCVUSBDRIVERINSTALLER --quiet || true

# Enable GPU support
if ! yum list installed nice-dcv-gl; then
    yum -y install nice-dcv-gl-*.rpm
fi

echo -e "\nPassed"
exit 0

#!/bin/bash -ex

echo -e "\nInstall packages for Linux desktop"

source /etc/environment

cd ${IMAGE_BUILDER_WORKDIR}/source
cp scripts/config.cfg /root
chmod +x soca/cluster_node_bootstrap/*.sh
./soca/cluster_node_bootstrap/ComputeNodeInstallDCV.sh

mkdir -p /root/sem
touch /root/sem/dcv-installed

echo -e "\nPassed"

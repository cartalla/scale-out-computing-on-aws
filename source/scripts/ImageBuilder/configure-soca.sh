#!/bin/bash -ex

scriptdir=$(dirname $(readlink -f $0))
scriptsdir=$(readlink -f $scriptdir/..)
socadir=$(readlink -f $scriptdir/../..)

source /etc/environment

function info {
    echo "$(date):INFO: $1"
}

if grep -q 'Amazon Linux release 2' /etc/system-release; then
    BASE_OS=amazonlinux2
elif grep -q 'CentOS Linux release 7' /etc/system-release; then
    BASE_OS=centos7
else
    BASE_OS=rhel7
fi
export BaseOS=$BASE_OS
info "BaseOS=$BaseOS"

# Install epel
info "Installing epel"
if [ $BaseOS == "amazonlinux2" ]; then
    amazon-linux-extras install -y epel
elif [ $BaseOS == "centos7" ]; then
    yum -y install epel-release
elif [ $BaseOS == "rhel7" ]; then
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
fi

# Install ansible
info "Installing ansible"
if [ $BaseOS == "amazonlinux2" ]; then
    amazon-linux-extras install -y ansible2
else
    yum -y install ansible
fi

# Install pip
info "Installing pip"
if ! which pip2.7; then
    echo "Installing pip2.7"
    if [ "$BaseOS" == "centos7" ] || [ "$BaseOS" == "rhel7" ]; then
        EASY_INSTALL=$(which easy_install-2.7)
        $EASY_INSTALL pip
    fi
fi
PIP=$(which pip2.7)

# awscli is installed by the aws-cli-version-2-linux component
AWS=$(which aws)

# Download Ansible Playbooks
info "Downloading ansible playbooks"
rm -rf /root/playbooks
aws s3 cp --recursive s3://${SOCA_INSTALL_BUCKET}/${SOCA_INSTALL_BUCKET_FOLDER}/playbooks/ /root/playbooks/
cd /root/playbooks

# Configure Repository
if [ ":$SOCA_REPOSITORY_BUCKET" = ":" ]; then
    info "Repository bucket not configured"
else
    info "Configuring repository mirror"
    ansible-playbook configure-repo-mirror.yml -e Region=${AWS_DEFAULT_REGION} -e Domain=${SOCA_DOMAIN} -e S3InstallBucket=${SOCA_INSTALL_BUCKET} -e S3InstallFolder=${SOCA_INSTALL_BUCKET_FOLDER} -e ClusterId=${SOCA_CONFIGURATION} -e NoProxy=${NO_PROXY} -e RepositoryBucket=${SOCA_REPOSITORY_BUCKET} -e RepositoryFolder=${SOCA_REPOSITORY_FOLDER} >> /root/ansible-configure-repo.log 2>&1
fi

# Install Lustre client
if [ "$BaseOS" == "amazonlinux2" ]; then
    sudo amazon-linux-extras install -y lustre2.10
elif [ "$BaseOS" == "centos7" ] || [ "$BaseOS" == "rhel7" ]; then
    curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc
    rpm --import /tmp/fsx-rpm-public-key.asc
    #curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo
    yum install -y kmod-lustre-client lustre-client
fi

# Don't configure file system mounts so that image can be used by different VPCs
# Can't mount them in the public subnet
#echo -e "\nConfiguring mount of $EFS_DATA at /data"
#mkdir -p /data
#echo "$EFS_DATA:/ /data nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0" >> /etc/fstab
#echo -e "\nConfiguring mount of $EFS_APPS at /apps"
#mkdir -p /apps
#echo "$EFS_APPS:/ /apps nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0" >> /etc/fstab

source $scriptsdir/config.cfg
if [ "$BaseOS" == "rhel7" ]; then
    yum-config-manager --enable rhel-7-server-rhui-optional-rpms
    yum-config-manager --enable rhel-7-server-rhui-rpms
fi

mkdir -p /root/logs
info "Installing SYSTEM_PKGS"
if ! yum install -y $(echo ${SYSTEM_PKGS[*]}) &> /root/logs/system_pkgs.log; then
    cat /root/logs/system_pkgs.log
    exit 1
fi
info "Installing SCHEDULER_PKGS"
if ! yum install -y $(echo ${SCHEDULER_PKGS[*]}) &> /root/logs/scheduler_pkgs.log; then
    cat /root/logs/scheduler_pkgs.log
    exit 1
fi
info "Installing OPENLDAP_SERVER_PKGS"
if ! yum install -y $(echo ${OPENLDAP_SERVER_PKGS[*]}) &> /root/logs/openldap_server_pkgs.log; then
    cat /root/logs/openldap_server_pkgs.log
    exit 1
fi
info "Installing SSSD_PKGS"
if ! yum install -y $(echo ${SSSD_PKGS[*]}) &> /root/logs/sssd_pkgs.log; then
    cat /root/logs/sssd_pkgs.log
    exit 1
fi
mkdir -p /root/sem
touch /root/sem/soca-packages-installed

# Install PBS Pro
cd /root
wget $OPENPBS_URL
tar zxvf $OPENPBS_TGZ
cd openpbs-$OPENPBS_VERSION
./autogen.sh
./configure --prefix=/opt/pbs
if ! make -j6 &> openpbs_build.log; then
    cat openpbs_build.log
    exit 1
fi
if ! make install -j6 &> openpbs_install.log; then
    cat openpbs_install.log
    exit 1
fi
/opt/pbs/libexec/pbs_postinstall
chmod 4755 /opt/pbs/sbin/pbs_iff /opt/pbs/sbin/pbs_rcp
systemctl disable pbs
touch /root/sem/pbs-installed

systemctl disable libvirtd.service || true
if ifconfig virbr0; then
    ip link set virbr0 down
    brctl delbr virbr0
fi
systemctl disable firewalld || true
systemctl stop firewalld || true

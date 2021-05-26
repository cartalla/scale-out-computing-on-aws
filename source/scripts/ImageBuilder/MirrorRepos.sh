#!/bin/bash -ex

function on_exit {
    rc=$?
    set +e
    if [[ $rc -ne 0 ]]; then
        echo Failed
        echo "Saving intermediate results"
        aws s3 sync --quiet $full_repo_dir s3://${SOCA_REPOSITORY_BUCKET}/${SOCA_REPOSITORY_FOLDER}/$repo_dir
    fi
}
trap on_exit EXIT

echo -e "\nMirror repos and source code for SOCA"

scriptdir=$(dirname $(readlink -f $0))

install_packages=${scriptdir}/install_packages.sh

function info {
    echo "$(date):INFO: $1"
}

function error {
    echo "$(date):ERROR: $1"
}

# For some reason whoami says root but USER and USERNAME aren't set.
export LOGNAME=$(whoami)
export HOME=/$(whoami)
export USER=$(whoami)
export USERNAME=$(whoami)

source /etc/environment

source ${IMAGE_BUILDER_WORKDIR}/source/scripts/config.cfg

if grep -q 'Amazon Linux release 2' /etc/system-release; then
    BASE_OS=amazonlinux2
elif grep -q 'CentOS Linux release 7' /etc/system-release; then
    BASE_OS=centos7
else
    BASE_OS=rhel7
fi
info $BASE_OS
export BaseOS=$BASE_OS
info "BaseOS=$BaseOS"

export build_dir=/tmp/MirrorRepos
export repo_dir=$(date +%Y-%m-%d-%H-%M-%S)
export full_repo_dir=$build_dir/$repo_dir
export s3_repo_url=s3://${SOCA_REPOSITORY_BUCKET}/${SOCA_REPOSITORY_FOLDER}/$repo_dir
export os_repo_dir=$repo_dir/yum/$BASE_OS
export full_os_repo_dir=$build_dir/$os_repo_dir
export s3_os_repo_url=$s3_repo_url/yum/$BASE_OS

rm -rf $build_dir
mkdir -p $full_repo_dir
cd $build_dir

mkdir -p $os_repo_dir

if ! yum list installed epel-release &> /dev/null; then
    if [ $BASE_OS == "centos7" ]; then
        yum install -y epel-release
    else
        yum install -y  https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    fi
fi

$install_packages "yum list installed" "yum install -y" createrepo make rpm-build wget which yum-utils python2-pip

if [ $BASE_OS == "centos7" ]; then
    $install_packages "yum list installed" "yum install -y" groff
else
    $install_packages "yum list installed" "yum install -y" groff-base
fi

which pip

pip install mock

# awscli is installed by previous component

ls /etc/pki/rpm-gpg
#rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
#rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7

aws s3 sync /etc/pki/rpm-gpg ${s3_os_repo_url}/rpm-gpg

# Install fsx lustre client
curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc
aws s3 cp --quiet /tmp/fsx-rpm-public-key.asc ${s3_os_repo_url}/fsx-rpm-public-key.asc
rpm --import /tmp/fsx-rpm-public-key.asc
curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo
#yum install -y kmod-lustre-client lustre-client
yum --disablerepo="*" --enablerepo="aws-fsx" list available
yum --disablerepo="*" --enablerepo="aws-fsx-src" list available
#yumdownloader --source kmod-lustre-client

# Copy config and source it
source $scriptdir/../config.cfg

echo $BASE_OS

if [ "$BASE_OS" == "rhel7" ]; then
    yum-config-manager --enable rhui-REGION-rhel-server-optional
    yum-config-manager --enable rhel-7-server-rhui-optional-rpms
    yum-config-manager --enable rhel-7-server-rhui-rpms
fi

$install_packages "yum list installed" "yum install -y" ${SYSTEM_PKGS[@]}
$install_packages "yum list installed" "yum install -y" ${SCHEDULER_PKGS[@]}
$install_packages "yum list installed" "yum install -y" ${OPENLDAP_SERVER_PKGS[*]}
$install_packages "yum list installed" "yum install -y" ${SSSD_PKGS[*]}

# Copy PBSPRO tarball
wget -q $OPENPBS_URL
aws s3 cp --quiet $OPENPBS_TGZ ${s3_repo_url}/source/openpbs/$OPENPBS_TGZ
# Copy Python tarball
wget -q $PYTHON_URL
if [[ $(md5sum $PYTHON_TGZ | awk '{print $1}') != $PYTHON_HASH ]];  then
    echo -e "FATAL ERROR: Checksum for Python failed. File may be compromised." > /etc/motd
    exit 1
fi
aws s3 cp --quiet $PYTHON_TGZ ${s3_repo_url}/source/python/$PYTHON_TGZ
# Copy OpenMPI tarball
wget -q $OPENMPI_URL
aws s3 cp --quiet $OPENMPI_TGZ ${s3_repo_url}/source/openmpi/$OPENMPI_TGZ
# Copy Metric Beat tarball
wget -q $METRICBEAT_URL
aws s3 cp --quiet $METRICBEAST_RPM ${s3_repo_url}/source/metricbeat/$METRICBEAST_RPM

# For some reason whoami says root but USER and USERNAME aren't set.
export LOGNAME=$(whoami)
export HOME=/$(whoami)
export USER=$(whoami)
export USERNAME=$(whoami)

env | sort > /root/env.txt
rpm --eval '%{_topdir}'
aws s3 cp --quiet --recursive s3://${SOCA_INSTALL_BUCKET}/${SOCA_INSTALL_BUCKET_FOLDER}/MirrorRepos/yum-s3-iam ${s3_repo_url}/source/yum-s3-iam
aws s3 cp --quiet --recursive s3://${SOCA_INSTALL_BUCKET}/${SOCA_INSTALL_BUCKET_FOLDER}/MirrorRepos/yum-s3-iam yum-s3-iam
cd yum-s3-iam
make rpm
#make test || true
aws s3 cp /root/rpmbuild/RPMS/noarch/yum-plugin-s3-iam-1.2.2-1.noarch.rpm ${s3_repo_url}/yum/yum-plugin-s3-iam-1.2.2-1.noarch.rpm
cd ..

# Sync the intermediate results
cd $build_dir
aws s3 sync --quiet $repo_dir ${s3_repo_url}
    
echo "List of yum repos:"
yum repolist

# Build Python and install required packages
# This is so that a PyPi mirror isn't required.
mkdir -p /apps/soca/$SOCA_CONFIGURATION/python/installer
cd /apps/soca/$SOCA_CONFIGURATION/python/installer
tar xzf $build_dir/$PYTHON_TGZ
cd Python-$PYTHON_VERSION
logfile=/var/log/Python-build.log
echo "Configuring python build"
if ! ./configure LDFLAGS="-L/usr/lib64/openssl" CPPFLAGS="-I/usr/include/openssl" -enable-loadable-sqlite-extensions --prefix=/apps/soca/$SOCA_CONFIGURATION/python/$PYTHON_VERSION >> $logfile 2>1; then
    cat $logfile
    echo "Python configure failed"
    exit 1
fi
echo "Building Python"
if ! make >> $logfile 2>1; then
    cat $logfile
    echo "Python build failed"
    exit 1
fi
echo "Installing Python"
if ! make install >> $logfile 2>1; then
    cat $logfile
    echo "Python install failed"
    exit 1
fi
cd /apps/soca/$SOCA_CONFIGURATION/python
compiled_python_tgz=Python-$PYTHON_VERSION-compiled.tgz

echo "Install Python required libraries"
aws s3 cp --quiet s3://${SOCA_INSTALL_BUCKET}/${SOCA_INSTALL_BUCKET_FOLDER}/scripts/requirements.txt /root/
if ! /apps/soca/$SOCA_CONFIGURATION/python/$PYTHON_VERSION/bin/pip3 install -r /root/requirements.txt >> $logfile 2>1; then
    cat $logfile
    echo "Python requirements install failed"
    exit 1
fi

compiled_python_tgz=Python-${PYTHON_VERSION}-compiled.tgz
tar -czf $compiled_python_tgz $PYTHON_VERSION
aws s3 cp --quiet $compiled_python_tgz ${s3_repo_url}/source/python/$compiled_python_tgz
cd $build_dir

if [ "$BASE_OS" == "centos7" ]; then
    export required_repos=( \
        base updates extras centosplus \
        epel epel-debuginfo epel-source \
        aws-fsx \
        aws-fsx-src \
    )
    export optional_repos=( \
        base-debuginfo \
        cr \
        fasttrack \
        base-source updates-source extras-source centosplus-source \
        centos-kernel centos-kernel-experimental \
        epel-testing epel-testing-debuginfo epel-testing-source \
    )
elif [ "$BASE_OS" == "rhel7" ]; then
    export required_repos=( \
        rhel-7-server-rhui-optional-rpms \
        rhel-7-server-rhui-rh-common-rpms \
        rhel-7-server-rhui-rpms \
        rhui-client-config-server-7 \
        epel \
        aws-fsx \
        aws-fsx-src \
    )
    export optional_repos=( \
    )
fi
echo ${required_repos[@]}

echo ${optional_repos[@]}

export repos=( \
    ${required_repos[@]} \
    #${optional_repos[@]} \
)
echo ${repos[@]}

# Save successes so can rerun after fails without redoing work
sem_dir=$build_dir/sems
mkdir -p $sem_dir
for repo in ${repos[@]}; do
    reposync_sem=$sem_dir/${repo}.reposync_done.txt
    createrepo_sem=$sem_dir/${repo}.createrepo_done.txt
    s3_cp_sem=$sem_dir/${repo}.s3_cp_done.txt
    if [ -e $reposync_sem ]; then
        echo "reposync already passed for $repo"
    else
        info "Syncing $repo"
        rm -f $createrepo_sem
        rm -f $s3_cp_sem
        echo -e "\nreposync --quiet -g -l -p $os_repo_dir --source --downloadcomps --download-metadata -r $repo"
        if ! reposync --quiet -g -l -p $os_repo_dir --source --downloadcomps --download-metadata -r $repo; then
            rc=$?
            echo -e "warning: reposync failed with rc=$rc but trying to continue. GPC may have failed on a package."''
        fi
        echo "df -h ."; df -h .
        touch $reposync_sem
    fi


    if [ -e $createrepo_sem ]; then
        echo "createrepo already passed for $repo"
    else
        rm -f $s3_cp_sem
        if [ -e $os_repo_dir/$repo/comps.xml ]; then
            groups_arg="-g comps.xml"
        else
            groups_arg=""
        fi

        echo -e "\ncreaterepo $os_repo_dir/$repo $groups_arg"
        createrepo $os_repo_dir/$repo $groups_arg
        date; echo "df -h ."; df -h .
        touch $createrepo_sem
    fi

    if [ -e $s3_cp_sem ]; then
        echo "s3 cp already passed for $repo"
    else
        echo "aws s3 sync --quiet $os_repo_dir/$repo ${s3_os_repo_url}/$repo"
        aws s3 sync --quiet $os_repo_dir/$repo ${s3_os_repo_url}/$repo
        echo "Sync to S3 completed"
        touch $s3_cp_sem
    fi
done

aws s3 sync --quiet $repo_dir ${s3_repo_url}
echo repo_dir=${repo_dir}

aws s3 sync --quiet $repo_dir ${s3_repo_url}

echo "Yum repo: ${s3_repo_url}"

echo -e "\nPassed"

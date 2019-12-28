#!/bin/bash -xe

source /etc/environment
source /root/config.cfg

# First flush the current crontab to prevent this script to run on the next reboot
crontab -r

# Copy  Aligo scripts file structure
AWS=$(which aws)
# Retrieve SOCA configuration under soca.tar.gz and extract it on /apps/
$AWS s3 cp s3://$SOCA_INSTALL_BUCKET/$SOCA_INSTALL_BUCKET_FOLDER/soca.tar.gz /root
mkdir -p /apps/soca
tar -xvf /root/soca.tar.gz -C /apps/soca --no-same-owner

mkdir -p /apps/soca/cluster_manager/logs
chmod +x /apps/soca/cluster_manager/aligoqstat.py

# Generate default queue_mapping file based on default AMI choosen by customer
cat <<EOT >> /apps/soca/cluster_manager/settings/queue_mapping.yml
# This manage automatic provisioning for your queues
# These are default values. Users can override them at job submission
# https://awslabs.github.io/scale-out-computing-on-aws/tutorials/create-your-own-queue/
queue_type:
  compute:
    queues: ["high", "normal", "low"]
    # Queue ACLs:  https://awslabs.github.io/scale-out-computing-on-aws/tutorials/manage-queue-acls/
    allowed_users: [] # empty list = all users can submit job
    excluded_users: [] # empty list = no restriction, ["*"] = only allowed_users can submit job
    # Default job parameters: https://awslabs.github.io/scale-out-computing-on-aws/tutorials/integration-ec2-job-parameters/
    instance_ami: "$SOCA_INSTALL_AMI"
    instance_type: "c5.large"
    ht_support: "false"
    root_size: "10"
    #scratch_size: "100"
    #scratch_iops: "3600"
    #efa_support: "false"
    # .. Refer to the doc for more supported parameters
  desktop:
    queues: ["desktop"]
    # Queue ACLs:  https://awslabs.github.io/scale-out-computing-on-aws/tutorials/manage-queue-acls/
    allowed_users: [] # empty list = all users can submit job
    excluded_users: [] # empty list = no restriction, ["*"] = only allowed_users can submit job
    # Default job parameters: https://awslabs.github.io/scale-out-computing-on-aws/tutorials/integration-ec2-job-parameters/
    instance_ami: "$SOCA_INSTALL_AMI"
    instance_type: "c5.large"
    ht_support: "false"
    root_size: "10"
    # .. Refer to the doc for more supported parameters
  test:
    queues: ["test"]
    # Queue ACLs:  https://awslabs.github.io/scale-out-computing-on-aws/tutorials/manage-queue-acls/
    allowed_users: [] # empty list = all users can submit job
    excluded_users: [] # empty list = no restriction, ["*"] = only allowed_users can submit job
    # Default job parameters: https://awslabs.github.io/scale-out-computing-on-aws/tutorials/integration-ec2-job-parameters/
    instance_ami: "$SOCA_INSTALL_AMI"
    instance_type: "c5.large"
    ht_support: "false"
    root_size: "10"
    #spot_price: "auto"
    #placement_group: "false"
    # .. Refer to the doc for more supported parameters
EOT

# Generate 10 years internal SSL certificate for Soca Web UI
cd /apps/soca/cluster_web_ui
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=California/L=Sunnyvale/CN=internal.soca.webui.cert" \
    -keyout cert.key -out cert.crt

# Wait for PBS to restart
sleep 60

# Create Default PBS hooks
qmgr -c "create hook soca_aws_infos event=execjob_begin"
qmgr -c "import hook soca_aws_infos application/x-python default /apps/soca/cluster_hooks/execjob_begin/soca_aws_infos.py"
qmgr -c "create hook check_queue_acl event=queuejob"
qmgr -c "import hook check_queue_acl application/x-python default /apps/soca/cluster_hooks/queuejob/check_queue_acl.py"

# Reload config
systemctl restart pbs

# Create crontabs
echo "
## Cluster Analytics
* * * * * source /etc/environment; /apps/python/latest/bin/python3 /apps/soca/cluster_analytics/cluster_nodes_tracking.py >> /apps/soca/cluster_analytics/cluster_nodes_tracking.log 2>&1
@hourly source /etc/environment; /apps/python/latest/bin/python3 /apps/soca/cluster_analytics/job_tracking.py >> /apps/soca/cluster_analytics/job_tracking.log 2>&1

## Cluster Log Management
@daily  source /etc/environment; /bin/bash /apps/soca/cluster_logs_management/send_logs_s3.sh >>/apps/soca/cluster_logs_management/send_logs_s3.log 2>&1

## Cluster Management
* * * * * source /etc/environment;  /apps/python/latest/bin/python3  /apps/soca/cluster_manager/nodes_manager.py >> /apps/soca/cluster_manager/nodes_manager.py.log 2>&1

## Cluster Web UI
@reboot /apps/soca/cluster_web_ui/socawebui.sh start

## Automatic Host Provisioning
*/3 * * * * source /etc/environment;  /apps/python/latest/bin/python3 /apps/soca/cluster_manager/dispatcher.py -c /apps/soca/cluster_manager/settings/queue_mapping.yml -t compute
*/3 * * * * source /etc/environment;  /apps/python/latest/bin/python3 /apps/soca/cluster_manager/dispatcher.py -c /apps/soca/cluster_manager/settings/queue_mapping.yml -t desktop
*/3 * * * * source /etc/environment;  /apps/python/latest/bin/python3 /apps/soca/cluster_manager/dispatcher.py -c /apps/soca/cluster_manager/settings/queue_mapping.yml -t test

# Add/Remove DCV hosts and configure ALB
*/5 * * * * source /etc/environment; /apps/python/latest/bin/python3 /apps/soca/cluster_manager/dcv_alb_manager.py >> /apps/soca/cluster_manager/dcv_alb_manager.py.log 2>&1
" | crontab -


# Re-enable access
if [ "$SOCA_BASE_OS" == "amazonlinux2" ] || [ "$SOCA_BASE_OS" == "rhel7" ];
     then
     usermod --shell /bin/bash ec2-user
fi

if [ "$SOCA_BASE_OS" == "centos7" ];
     then
     usermod --shell /bin/bash centos
fi

# Check if the Cluster is fully operational

# Verify PBS
if [ -z "$(pgrep pbs)" ]
    then
    echo -e "
    /!\ /!\ /!\ /!\ /!\ /!\ /!\ /!\
    ERROR WHILE CREATING ALIGO HPC
    *******************************
    PBS SERVICE NOT DETECTED
    ********************************
    The USER-DATA did not run properly
    Please look for any errors on /var/log/message | grep cloud-init
    " > /etc/motd
    exit 1
fi

# Verify OpenLDAP
if [ -z "$(pgrep slapd)" ]
    then
    echo -e "
    /!\ /!\ /!\ /!\ /!\ /!\ /!\ /!\
    ERROR WHILE CREATING ALIGO HPC
    *******************************
    LDAP SERVICE NOT DETECTED
    ********************************
    The USER-DATA did not run properly
    Please look for any errors on /var/log/message | grep cloud-init
    " > /etc/motd
    exit 1
fi
# Verify SSSD
if [ -z "$(pgrep sssd)" ]
    then
    echo -e "
    /!\ /!\ /!\ /!\ /!\ /!\ /!\ /!\
    ERROR WHILE CREATING ALIGO HPC
    *******************************
    SSSD SERVICE NOT DETECTED
    ********************************
    The USER-DATA did not run properly
    Please look for any errors on /var/log/message | grep cloud-init
    " > /etc/motd
    exit 1
fi

# Start Web UI
chmod +x /apps/soca/cluster_web_ui/socawebui.sh
/apps/soca/cluster_web_ui/socawebui.sh start

# Cluster is ready
echo -e "
   _____  ____   ______ ___
  / ___/ / __ \ / ____//   |
  \__ \ / / / // /    / /| |
 ___/ // /_/ // /___ / ___ |
/____/ \____/ \____//_/  |_|
Cluster: $SOCA_CONFIGURATION
> source /etc/environment to load SOCA paths
" > /etc/motd

# Create default LDAP user
/apps/python/latest/bin/python3 /apps/soca/cluster_manager/ldap_manager.py add-user -u "$3" -p "$4" --admin

# Clean directories
rm -rf /root/pbspro-18.1.4*
rm -rf /root/*.sh
rm -rf /root/config.cfg

# Install OpenMPI
# This will take a while and is not system blocking, so adding at the end of the install process
mkdir -p /apps/openmpi/installer
cd /apps/openmpi/installer

wget $OPENMPI_URL
if [[ $(md5sum $OPENMPI_TGZ | awk '{print $1}') != $OPENMPI_HASH ]];  then
    echo -e "FATAL ERROR: Checksum for OpenMPI failed. File may be compromised." > /etc/motd
    exit 1
fi

tar xvf $OPENMPI_TGZ
cd openmpi-$OPENMPI_VERSION
./configure --prefix=/apps/openmpi/$OPENMPI_VERSION
make
make install

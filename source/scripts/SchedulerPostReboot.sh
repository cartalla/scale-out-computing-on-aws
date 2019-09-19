#!/bin/bash -xe

source /etc/environment
source /root/config.cfg

# First flush the current crontab to prevent this script to run on the next reboot
crontab -r

# Copy  Aligo scripts file structure
# NOTE: THIS REQUIRE PERMISSION ON THE SOURCE BUCKET
AWS=$(which aws)
$AWS s3 sync s3://$SOCA_INSTALL_BUCKET/$SOCA_INSTALL_BUCKET_FOLDER/soca/cluster_manager/ /apps/soca/cluster_manager
$AWS s3 sync s3://$SOCA_INSTALL_BUCKET/$SOCA_INSTALL_BUCKET_FOLDER/soca/cluster_analytics/ /apps/soca/cluster_analytics
$AWS s3 sync s3://$SOCA_INSTALL_BUCKET/$SOCA_INSTALL_BUCKET_FOLDER/soca/cluster_logs_management/ /apps/soca/cluster_logs_management
$AWS s3 sync s3://$SOCA_INSTALL_BUCKET/$SOCA_INSTALL_BUCKET_FOLDER/soca/cluster_web_ui/ /apps/soca/cluster_web_ui
$AWS s3 sync s3://$SOCA_INSTALL_BUCKET/$SOCA_INSTALL_BUCKET_FOLDER/soca/cluster_hooks/ /apps/soca/cluster_hooks
mkdir -p /apps/soca/cluster_manager/logs

# Generate default queue_mapping file based on default AMI choosen by customer
cat <<EOT >> /apps/soca/cluster_manager/settings/queue_mapping.yml
# This manage automatic provisioning for your queues
queue_type:
  compute:
    queues: ["high", "normal", "low"]
    default_ami: "$SOCA_INSTALL_AMI"
    default_instance: "c5.large"
    scratch_size: "100"
  desktop:
    queues: ["desktop"]
    default_ami: "$SOCA_INSTALL_AMI"
    default_instance: "c5.large"
EOT

# Generate 10 years internal SSL certificate for Soca Web Ui
cd /apps/soca/cluster_web_ui
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=California/L=Sunnyvale/CN=internal.soca.webui.cert" \
    -keyout cert.key -out cert.crt

# Wait for PBS to restart
sleep 60

# Finalize PBS configuration
#/opt/pbs/bin/qmgr -c "set queue cpus default_chunk.compute_node=tbd"

# Create Default PBS hooks
qmgr -c "create hook soca_aws_infos event=execjob_begin"
qmgr -c "import hook soca_aws_infos application/x-python default /apps/soca/cluster_hooks/execjob_begin/soca_aws_infos.py"

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

## Automatic Host Provisioning
*/3 * * * * source /etc/environment;  /apps/python/latest/bin/python3 /apps/soca/cluster_manager/dispatcher.py -c /apps/soca/cluster_manager/settings/queue_mapping.yml -t compute
*/3 * * * * source /etc/environment;  /apps/python/latest/bin/python3 /apps/soca/cluster_manager/dispatcher.py -c /apps/soca/cluster_manager/settings/queue_mapping.yml -t desktop

# Add/Remove DCV hosts and configure ALB
*/5 * * * * source /etc/environment; /apps/python/latest/bin/python3 /apps/soca/cluster_manager/dcv_alb_manager.py >> /apps/soca/cluster_manager/dcv_alb_manager.py.log 2>&1
" | crontab -


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

if [ "$SOCA_BASE_OS" == "AmazonLinux2" ] || [ "$SOCA_BASE_OS" == "Rhel7" ];
     then
     usermod --shell /bin/bash ec2-user
fi

if [ "$SOCA_BASE_OS" == "Centos7" ];
     then
     usermod --shell /bin/bash centos
fi


# Create default LDAP user
/apps/python/latest/bin/python3 /apps/soca/cluster_manager/ldap_manager.py -u $3 -p $4 --admin

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


export AWS_DEFAULT_REGION=us-east-1
export SSH_KEY_PAIR=${USER}-${AWS_DEFAULT_REGION}

# VCS SOCA Workshop
export STACK_NAME=VcsLicenseServer
export S3_LICENSE_SERVER_BUCKET=${USER}-soca-${AWS_DEFAULT_REGION}
export S3_LICENSE_SERVER_FOLDER=LicenseServer/${STACK_NAME}
export VPC_ID=vpc-0f58e0213d07c842f
# Private1
export SUBNET_ID=subnet-089c11b0c5d17cbed
# ComputeNodeSecurityGroup
export SECURITY_GROUP=sg-0dc190225f74924f5
# Centos 7
export IMAGE_ID=ami-0be2609ba883822ec
export INSTANCE_TYPE=m5.2xlarge
# AL2
export AMI_ID=ami-0be2609ba883822ec
export FSX_ID=fs-09af2b5b77b11707c
export FsxMountOrigin="fs-09af2b5b77b11707c.fsx.us-east-1.amazonaws.com@tcp:/zqmjdbmv"
export SynopsysInstallerFsxPath="/fsx/data/synopsys_spf/installer/5.1"
export SynopsysSCLFsxPath="/fsx/data/synopsys_spf/scl/2021.03"

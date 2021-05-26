
ifeq ($(strip ${S3_LICENSE_SERVER_BUCKET}),)
$(error Must define S3_LICENSE_SERVER_BUCKET)
endif
ifeq ($(strip ${S3_LICENSE_SERVER_FOLDER}),)
$(error Must define S3_LICENSE_SERVER_FOLDER)
endif
ifneq ($(or $(findstring create,${MAKECMDGOALS}), $(findstring update,${MAKECMDGOALS})),)
  ifeq ($(strip ${STACK_NAME}),)
    $(error Must define STACK_NAME)
  endif
endif

template_url = https://${S3_LICENSE_SERVER_BUCKET}.s3.amazonaws.com/${S3_LICENSE_SERVER_FOLDER}/source/LicenseServer/LicenseServer.template.yml

.PHONY: upload create create_only update update_only

upload:
	rm -rf ../dist
	aws s3 sync .             s3://${S3_LICENSE_SERVER_BUCKET}/${S3_LICENSE_SERVER_FOLDER}/source/LicenseServer/
	@echo "CloudFormation template: ${template_url}"

create: upload create_only

create_only:
	aws cloudformation create-stack --stack-name ${STACK_NAME} \
	--template-url ${template_url} \
	--parameters \
		ParameterKey=VpcId,ParameterValue=${VPC_ID} \
		ParameterKey=SubnetId,ParameterValue=${SUBNET_ID} \
		ParameterKey=SecurityGroup,ParameterValue=${SECURITY_GROUP} \
		ParameterKey=ImageId,ParameterValue=${IMAGE_ID} \
		ParameterKey=InstanceType,ParameterValue=${INSTANCE_TYPE} \
		ParameterKey=SSHKeyPair,ParameterValue=${SSH_KEY_PAIR} \
		ParameterKey=FsxId,ParameterValue=${FSX_ID} \
		ParameterKey=FsxMountOrigin,ParameterValue=${FsxMountOrigin} \
		ParameterKey=SynopsysInstallerFsxPath,ParameterValue=${SynopsysInstallerFsxPath} \
		ParameterKey=SynopsysSCLFsxPath,ParameterValue=${SynopsysSCLFsxPath} \
	--disable-rollback \
	--capabilities CAPABILITY_IAM

update: upload update_only

update_only:
	aws cloudformation update-stack --stack-name ${STACK_NAME} \
	--template-url ${template_url} \
	--parameters \
		ParameterKey=VpcId,ParameterValue=${VPC_ID} \
		ParameterKey=SubnetId,ParameterValue=${SUBNET_ID} \
		ParameterKey=SecurityGroup,ParameterValue=${SECURITY_GROUP} \
		ParameterKey=ImageId,ParameterValue=${IMAGE_ID} \
		ParameterKey=InstanceType,ParameterValue=${INSTANCE_TYPE} \
		ParameterKey=SSHKeyPair,ParameterValue=${SSH_KEY_PAIR} \
		ParameterKey=FsxId,ParameterValue=${FSX_ID} \
		ParameterKey=FsxMountOrigin,ParameterValue=${FsxMountOrigin} \
		ParameterKey=SynopsysInstallerFsxPath,ParameterValue=${SynopsysInstallerFsxPath} \
		ParameterKey=SynopsysSCLFsxPath,ParameterValue=${SynopsysSCLFsxPath} \
	--capabilities CAPABILITY_IAM


ifeq ($(strip ${S3_MIRROR_REPO_BUCKET}),)
$(error Must define S3_MIRROR_REPO_BUCKET)
endif
ifeq ($(strip ${S3_MIRROR_REPO_FOLDER}),)
$(error Must define S3_MIRROR_REPO_FOLDER)
endif
ifneq ($(or $(findstring create,${MAKECMDGOALS}), $(findstring update,${MAKECMDGOALS})),)
  ifeq ($(strip ${STACK_NAME}),)
    $(error Must define STACK_NAME)
  endif
endif

template_url = https://${S3_MIRROR_REPO_BUCKET}.s3.amazonaws.com/${S3_MIRROR_REPO_FOLDER}/source/MirrorRepos/MirrorRepos.template.yml

upload:
	aws s3 cp --recursive .             s3://${S3_MIRROR_REPO_BUCKET}/${S3_MIRROR_REPO_FOLDER}/source/MirrorRepos/
	aws s3 cp --recursive ../scripts    s3://${S3_MIRROR_REPO_BUCKET}/${S3_MIRROR_REPO_FOLDER}/source/scripts
	@echo "CloudFormation template: ${template_url}"

create:
	aws cloudformation create-stack --stack-name ${STACK_NAME} \
	--template-url ${template_url} \
	--parameters \
		ParameterKey=S3MirrorRepoBucket,ParameterValue=${S3_MIRROR_REPO_BUCKET} \
		ParameterKey=S3MirrorRepoFolder,ParameterValue=${S3_MIRROR_REPO_FOLDER} \
	--disable-rollback \
	--capabilities CAPABILITY_IAM

update:
	aws cloudformation update-stack --stack-name ${STACK_NAME} \
	--template-url ${template_url} \
	--parameters \
		ParameterKey=S3MirrorRepoBucket,ParameterValue=${S3_MIRROR_REPO_BUCKET} \
		ParameterKey=S3MirrorRepoFolder,ParameterValue=${S3_MIRROR_REPO_FOLDER} \
	--capabilities CAPABILITY_IAM


export AWS_DEFAULT_REGION=us-east-1
export SSH_KEY_PAIR=${USER}-${AWS_DEFAULT_REGION}
export TerminateBuildInstanceOnFailure=false
#export TerminateBuildInstanceOnFailure=true

# export STACK_NAME=ImageBuilder
# export S3_IMAGE_BUILDER_BUCKET=${USER}-soca-${AWS_DEFAULT_REGION}
# export S3_IMAGE_BUILDER_FOLDER=ImageBuilder/${STACK_NAME}
# export S3_REPOSITORY_BUCKET=${USER}-soca-${AWS_DEFAULT_REGION}
# export S3_REPOSITORY_FOLDER=repositories

export STACK_NAME=ImageBuilder5
export S3_IMAGE_BUILDER_BUCKET=soca-collaboration-chambers-${AWS_DEFAULT_REGION}
export S3_IMAGE_BUILDER_FOLDER=ImageBuilder
export S3_REPOSITORY_BUCKET=soca-collaboration-chambers-${AWS_DEFAULT_REGION}
export S3_REPOSITORY_FOLDER=repositories

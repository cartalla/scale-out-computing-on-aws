
export AWS_DEFAULT_REGION=us-east-1
export SSH_KEY_PAIR=${USER}-${AWS_DEFAULT_REGION}

# export STACK_NAME=MirrorRepos
# export S3_MIRROR_REPO_BUCKET=${USER}-soca-${AWS_DEFAULT_REGION}
# export S3_MIRROR_REPO_FOLDER=ImageBuilder/${STACK_NAME}

export STACK_NAME=MirrorReposCollab2
export S3_MIRROR_REPO_BUCKET=soca-collaboration-chambers-${AWS_DEFAULT_REGION}
export S3_MIRROR_REPO_FOLDER=ImageBuilder/${STACK_NAME}

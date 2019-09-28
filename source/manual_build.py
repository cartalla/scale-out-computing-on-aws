import sys
import os
import re
from shutil import make_archive, copy, copytree
import random
import string
import fileinput
if __name__ == "__main__":
    build_path = os.path.dirname(sys.argv[0])
    os.chdir(build_path)
    # Make sure build ID is > 3 chars and does not start with a number
    unique_id = ''.join(random.choice(string.ascii_lowercase) + random.choice(string.digits) for i in range(2))
    build_folder = 'dist/' + unique_id
    output_prefix = "soca-installer-" + unique_id  # prefix for the output artifact
    print("====== SOCA Build ======\n")
    print(" > Generated unique ID for build: " + unique_id)
    print(" > Creating temporary build folder ... ")
    print(" > Copying required files ... ")
    targets = ['soca', 'scripts', 'templates', 'solution-for-scale-out-computing-on-aws.template']

    for target in targets:
        if os.path.isdir(target):
            copytree(target, build_folder + '/' + target)
        else:
            copy(target, build_folder + '/' + target)

    # Replace Placeholder
    for line in fileinput.input([build_folder + '/solution-for-scale-out-computing-on-aws.template'], inplace=True):
        print(line.replace('%%BUCKET_NAME%%', 'your-s3-bucket-name-here').replace('%%SOLUTION_NAME%%/%%VERSION%%', 'your-s3-folder-name-here').replace('\n', ''))

    print(" > Creating archive for build id: " + unique_id)
    make_archive('dist/' + output_prefix, 'gztar', build_folder)

    print("\n====== Build COMPLETE ======")
    print("\n====== Installation Instructions ======")
    print("1: Create or use an existing S3 bucket on your AWS account (eg: 'mysocacluster')")
    print("2: Drag & Drop " + build_path + "/" + build_folder + " to your S3 bucket (eg: 'mysocacluster/" + build_folder + ")")
    print("3: Launch CloudFormation and use solution-for-scale-out-computing-on-aws.template as base template")
    print("4: Enter your cluster information.")
    print("")
    print("")
    input("Press Enter key to close ..")









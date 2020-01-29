---
title: Job customization for EC2
---

Scale-Out Computing on AWS made [job submission on EC2 very easy](../tutorials/launch-your-first-job/) and is fully integrated with EC2.
Below is a list of parameters you can specify when you request your simulation to ensure the hardware provisioned will exactly match your simulation requirements. 

!!!info 
    If you don't specify them, your job will use the default values configured for your queue (see `/apps/soca/<CLUSTER_ID>/cluster_manager/settings/queue_mapping.yml`)
    ____
    You can use [the web-based simulator](../../job-configuration-generator/) to generate your qsub command very easily.

## Compute

#### base_os

- Description: Reference to the base OS of the AMI you are using
- Allowed Values: `amazonlinux2` `centos7` `rhel7`
- Default: If not specified, value default to the OS of the install AMI
- Examples: 
    - `-l base_os=centos7`: Instances provisioned will be deployed against CentOS manifest
 
#### ht_support

*Disabled by default*

- Description: Enable support for hyper-threading
- Allowed Value: `yes` `true` `no` `false` (case insensitive) 
- Examples:
    - `-l ht_support=True`: Enable hyper-threading for all instances
    - `-l ht_support=False`: Disable hyper-threading for all instances (default)
       
#### instance_ami

- Description: Reference to a custom AMI you want to use
- Default: If not specified, value default to the AMI specified during installation
- Examples:
    - `-l instance_ami=ami-abcde123`: Capacity provisioned for the job will use the specific AMI

!!!info 
    If your are planning to use an AMI which is *not using the same OS* as the scheduler, you will need to specify `base_os` parameter

#### instance_type

- Description: The type of instance to provision for the simulation
- Examples:
    - `-l instance_type=c5.large`: Provision a c5.large for the simulation
    - `-l instance_type=c5.large+m5.large`: Provision c5.large and m5.large (if needed) for the simulation.

!!!info
    You can specify multiple instances type using "+" sign.
     When using more than 1 instance type, AWS will prioritize the capacity based on the order (eg: launch c5.large first and switch to m5.large if AWS can't provision c5.large anymore)

#### nodes

- Description:The number of EC2 instance to provision
- Examples:
    - `-l nodes=5`: Provision 5 EC2 instances


#### spot_allocation_count

- Description: Specify the number of SPOT instances to launch when provisioning both OD (On Demand) and SPOT instances
- Allowed Value: Integer
- Examples:
    - `-l nodes=10 -l spot_price=auto -l spot_allocation_count=8`: Provision 10 instances, 2 OD and 8 SPOT with max spot price capped to OD price
    - `-l nodes=10 -l spot_price=1.4 -l spot_allocation_count=5`: Provision 10 instances, 5 OD and 5 SPOT with max spot price set to $1.4 
    - `-l nodes=10 -l spot_price=auto`: Only provision SPOT instances
    - `-l nodes=10`: Only provision OD instances

!!!note
    This parameter is ignored if `spot_price` is not specified
    `spot_allocation_count` must be lower that the total number of nodes you are requesting (eg: you can not do `-l nodes=5 -l spot_allocation_count=15`)
    
#### spot_allocation_strategy

- Description: Choose allocation strategy when using multiple SPOT instances type
- Allowed Value: `capacity-optimized` or `lowest-cost`
- Default Value: `lowest-cost`
- Examples:
    - `-l spot_allocation_strategy=capacity-optimized`: AWS will provision compute nodes based on capacity availabilities


#### spot_price

- Description: Enable support for SPOT instances
- Allowed Value: any float value or `auto`
- Examples:
    - `-l spot_price=auto`: Max price will be capped to the On-Demand price
    - `-l spot_price=1.4`: Max price you are willing to pay for this instance will be $1.4 an hour.

!!!note 
    `spot_price` is capped to On-Demand price (e.g: Assuming you are provisioning a t3.medium, AWS will default spot price to 0.418 (OD price) even though you specified `-l spot_price=15`)

#### subnet_id

- Description: Reference to a subnet ID to use
- Default: If not specified, value default to one of the three private subnets created during installation
- Examples:
    - `-l subnet_id=sub-abcde123`

## Storage

### EBS

#### keep_ebs

*Disabled by default*

- Description: Retain or not the EBS disks once the simulation is complete
- Allowed Value: `yes` `true` `false` `no` (case insensitive)
- Default Value: `False`
- Example: 
    - `-l keep_ebs=False`: (Default) All EBS disks associated to the job will be deleted
    - `-l keep_ebs=True`: Retain EBS disks after the simulation has terminated (mostly for debugging/troubleshooting procedures)


#### root_size

- Description: Define the size of the local root volume
- Unit: GB
- Example: `-l root_size=300`: Provision a 300 GB SSD disk for `/` (either `sda1` or `xvda1`)

#### scratch_size

- Description: Define the size of the local root volume
- Unity: GB
- Example: `-l scratch_size=500`: Provision a 500 GB SSD disk for `/scratch`

!!!info
    scratch disk is automatically mounted on all nodes associated to the simulation under `/scratch`

#### instance_store

!!!info 
    - SOCA automatically mount instance storage when available. 
    - [For instances having more than 1 volume, SOCA will create a raid device](../../storage/backend-storage-options/#instance-store-partition)
    - In all cases, instance store volumes will be mounted on `/scratch`

#### scratch_iops

- Description: Define the number of provisioned IOPS to allocate for your `/scratch` device
- Unity: IOPS
- Example: `-l scratch_iops=3000`: Your EBS disks provisioned for `/scratch` will have 3000 dedicated IOPS

!!!info
    It is recommended to set the IOPs to 3x storage capacity of your EBS disk



### FSx for Lustre

#### fsx_lustre_bucket

- Description: Create an ephemeral FSx for your job and mount the  S3 bucket specified 
- Example: `-l fsx_lustre_bucket=my-bucket-name`: Create a new FSx for Lustre and mount it accross all nodes

!!!info
    - FSx partitions are mounted as `/fsx`
    - [You need to give IAM permission first](../../storage/launch-job-with-fsx/)
    - If not specified, SOCA automatically prefix your bucket name with  `s3://`
    - If `fsx_lustre_size` is not specified, default to 1200 GB

#### fsx_lustre_size

- Description: Create an ephemeral FSx for your job and mount the  S3 bucket specified 
- Unit: GB
- Example: `-l fsx_lustre_sizey=3600`: Provision a 3.6TB EFS disk

!!!info    
    If `fsx_lustre_size` is not specified, default to 1200 GB (smallest size supported)
    
#### fsx_lustre_dns

- Description: Mount an existing FSx to all compute nodes 
- Example: `-l fsx_lustre_dns=xxx`

!!!info    
    `fsx_lustre_bucket` is ignored if  `fsx_lustre_bucket` is specified.

## Network

#### efa_support

- Description: Enable EFA support
- Allowed Value: yes, true, True 
- Example: `-l efa_support=True`: Deploy an EFA device on all the nodes

!!!info    
    You must use an EFA compatible instance, otherwise your job will stay in the queue


#### ht_support

*Disabled by default*

- Description: Enable support for hyper-threading
- Allowed Value: `yes` `true` (case insensitive) 
- Example: `-l ht_support=True`: Enable hyper-threading for all instances

#### placement_group

*Enabled by default*

- Description: Disable placement group
- Allowed Value: `yes` `true` (case insensitive) 
- Example: `-l placement_group=Frue`: Instances will not use placement groups

!!!info
    - Placement group is enabled by default as long as the number of nodes provisioned is greated than 1



## How to use custom parameters

!!!example
    Here is an example about how to use a custom AMI at job or queue level. This example is applicable to all other parameters (simply change the parameter name to the one you one to use). 
    
#### For a single job
Use `-l instance_ami` parameter if you want to only change the AMI for a single job

~~~bash
$ qsub -l instance_ami=ami-082b... -- /bin/echo Hello
~~~

!!!note "Priority"
    Job resources have the highest priorities. Your job will always use the AMI specified at submission time even if it's different thant the one configure at queue level.

#### For an entire queue

Edit `/apps/soca/<CLUSTER_ID>/cluster_manager/settings/queue_mapping.yml` and update the default `instance_ami` parameter if you want all jobs in this queue to use your new AMI:

~~~yaml hl_lines="4"
queue_type:
  compute:
    queues: ["queue1", "queue2", "queue3"] 
    instance_ami: "<YOUR_AMI_ID>" # <- Add your new AMI 
    instance_type: ...
    root_size: ...
    scratch_size: ...
    efa: ...
    ....
~~~


## [View Examples](../launch-your-first-job/#examples)

       
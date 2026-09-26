import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

schedule_tag = os.environ.get("SCHEDULE_TAG", "dev-schedule")
region = os.environ.get("REGION", "us-east-1")
ec2 = boto3.client("ec2", region_name=region)


def lambda_handler(event, context):
    action = event.get("action", "")
    if action not in {"start", "stop"}:
        return {"status": "error", "message": "Invalid scheduler action"}

    instances = get_tagged_instances(action)
    if not instances:
        return {"status": "ok", "message": f"No instances tagged with {schedule_tag}=true"}

    instance_ids = [instance["InstanceId"] for instance in instances]
    if action == "stop":
        ec2.stop_instances(InstanceIds=instance_ids)
        message = f"Stopped {len(instance_ids)} instances"
    else:
        ec2.start_instances(InstanceIds=instance_ids)
        message = f"Started {len(instance_ids)} instances"

    logger.info("%s: %s", message, ",".join(instance_ids))
    return {"status": "ok", "message": message, "instances": instance_ids}


def get_tagged_instances(action):
    states = ["running"] if action == "stop" else ["stopped"]
    paginator = ec2.get_paginator("describe_instances")
    instances = []
    for page in paginator.paginate(
        Filters=[
            {"Name": f"tag:{schedule_tag}", "Values": ["true"]},
            {"Name": "instance-state-name", "Values": states},
        ]
    ):
        for reservation in page["Reservations"]:
            instances.extend(reservation["Instances"])
    return instances

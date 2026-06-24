import os
import json
import boto3
from datetime import datetime, timezone

SCHEDULE_TAG = os.environ.get("SCHEDULE_TAG", "dev-schedule")
REGION = os.environ.get("REGION", "us-east-1")

ec2 = boto3.client("ec2", region_name=REGION)


def lambda_handler(event, context):
    action = event.get("action", "")
    if action not in ("start", "stop"):
        return {"status": "error", "message": f"Invalid action: {action}"}

    instances = get_tagged_instances()
    if not instances:
        return {"status": "ok", "message": f"No instances tagged with {SCHEDULE_TAG}=true"}

    instance_ids = [i["InstanceId"] for i in instances]

    if action == "stop":
        ec2.stop_instances(InstanceIds=instance_ids)
        msg = f"Stopped {len(instance_ids)} instances"
    else:
        ec2.start_instances(InstanceIds=instance_ids)
        msg = f"Started {len(instance_ids)} instances"

    print(f"{msg}: {instance_ids}")
    return {"status": "ok", "message": msg, "instances": instance_ids}


def get_tagged_instances():
    paginator = ec2.get_paginator("describe_instances")
    instances = []
    for page in paginator.paginate(
        Filters=[
            {"Name": "tag:" + SCHEDULE_TAG, "Values": ["true"]},
            {"Name": "instance-state-name", "Values": ["running", "stopped"]},
        ]
    ):
        for reservation in page["Reservations"]:
            instances.extend(reservation["Instances"])
    return instances

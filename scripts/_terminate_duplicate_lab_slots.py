#!/usr/bin/env python3
"""
Terminate extra ansible-lab instances when more than one shares the same Number tag.
Keeps the oldest LaunchTime per Number; terminates newer duplicates (dry-run unless --apply).
"""
import argparse, os, sys
from collections import defaultdict

import boto3
from botocore.exceptions import ClientError

PROJECT = "ansible-lab"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--apply", action="store_true", help="Actually terminate (default: dry-run)")
    args = p.parse_args()

    k = os.environ.get("AWS_ACCESS_KEY_ID", "").strip().strip("'\"")
    s = os.environ.get("AWS_SECRET_ACCESS_KEY", "").strip().strip("'\"")
    r = os.environ.get("AWS_DEFAULT_REGION", "us-east-1").strip()
    if not k or not s:
        print("ERROR: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY required", file=sys.stderr)
        sys.exit(1)

    ec2 = boto3.client(
        "ec2",
        region_name=r,
        aws_access_key_id=k,
        aws_secret_access_key=s,
    )

    try:
        resp = ec2.describe_instances(
            Filters=[
                {"Name": "tag:Project", "Values": [PROJECT]},
                {
                    "Name": "instance-state-name",
                    "Values": ["pending", "running", "stopping", "stopped"],
                },
            ]
        )
    except ClientError as e:
        print("ERROR:", e, file=sys.stderr)
        sys.exit(1)

    by_num: dict[str, list[dict]] = defaultdict(list)
    for res in resp["Reservations"]:
        for inst in res["Instances"]:
            tags = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}
            num = tags.get("Number")
            if num is None:
                continue
            by_num[str(num)].append(inst)

    to_terminate: list[str] = []
    for num in sorted(by_num.keys(), key=lambda x: int(x)):
        rows = by_num[num]
        if len(rows) <= 1:
            continue
        # Oldest first — keep first, terminate rest
        rows.sort(key=lambda i: i["LaunchTime"])
        keep = rows[0]
        extras = rows[1:]
        print(f"Slot Number={num}: keep {keep['InstanceId']} (launched {keep['LaunchTime']})")
        for ex in extras:
            print(f"  DUPLICATE terminate {ex['InstanceId']} (launched {ex['LaunchTime']}) state={ex['State']['Name']}")
            to_terminate.append(ex["InstanceId"])

    if not to_terminate:
        print("No duplicate Number tags found — nothing to do.")
        return

    if not args.apply:
        print(f"\nDry-run: would terminate {len(to_terminate)} instance(s). Re-run with --apply to execute.")
        return

    print(f"\nTerminating {len(to_terminate)} instance(s)...")
    ec2.terminate_instances(InstanceIds=to_terminate)
    print("Done. Wait for terminated state in EC2 console, then: bash scripts/run_ec2_provision.sh")


if __name__ == "__main__":
    main()

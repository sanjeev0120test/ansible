#!/usr/bin/env python3
"""
Create an EC2 key pair 'ansible-lab-key' in us-east-1 and save the PEM.
Run once: .venv/bin/python scripts/_create_keypair.py
"""
import os, sys, stat

HOME = os.path.expanduser("~")
ak = os.environ.get("AWS_ACCESS_KEY_ID", "").strip().strip("'\"")
sk = os.environ.get("AWS_SECRET_ACCESS_KEY", "").strip().strip("'\"")
r  = os.environ.get("AWS_DEFAULT_REGION", "us-east-1").strip()
KP_NAME = "ansible-lab-key"
PEM_PATH = os.path.join(HOME, ".ssh", f"{KP_NAME}.pem")

import boto3
from botocore.exceptions import ClientError

kw = {"region_name": r, "aws_access_key_id": ak, "aws_secret_access_key": sk}
ec2 = boto3.client("ec2", **kw)

# Check if already exists (list all — Filters are easy to get wrong across API versions)
names = {kp["KeyName"] for kp in ec2.describe_key_pairs()["KeyPairs"]}
if KP_NAME in names:
    print(f"Key pair '{KP_NAME}' already exists in {r} — nothing to create.")
    if os.path.isfile(PEM_PATH):
        print(f"Local PEM found: {PEM_PATH}")
    else:
        print(
            f"No PEM at {PEM_PATH}. AWS does not store the private key.\n"
            "  Use the .pem you downloaded when you created the key, or:\n"
            f"  EC2 → Key Pairs → delete {KP_NAME!r} → run this script again to create a new one."
        )
    print(f"\nEC2_KEY_PAIR_NAME={KP_NAME}")
    print(f"EC2_SSH_PRIVATE_KEY={PEM_PATH}")
    sys.exit(0)

# Create
print(f"Creating key pair '{KP_NAME}' in {r}...")
try:
    resp = ec2.create_key_pair(KeyName=KP_NAME, KeyType="rsa", KeyFormat="pem")
except ClientError as e:
    code = e.response.get("Error", {}).get("Code", "")
    if code == "InvalidKeyPair.Duplicate":
        print(f"Key pair '{KP_NAME}' already exists in {r} (duplicate).")
        print(f"Ensure your private key is at {PEM_PATH} or set EC2_SSH_PRIVATE_KEY in .env.")
        sys.exit(0)
    raise
pem_material = resp["KeyMaterial"]

# Save PEM
os.makedirs(os.path.dirname(PEM_PATH), exist_ok=True)
with open(PEM_PATH, "w") as f:
    f.write(pem_material)
os.chmod(PEM_PATH, stat.S_IRUSR | stat.S_IWUSR)  # 600

print(f"Key pair created: {KP_NAME}")
print(f"PEM saved to    : {PEM_PATH}")
print(f"\nAdd to .env:")
print(f"EC2_KEY_PAIR_NAME={KP_NAME}")
print(f"EC2_SSH_PRIVATE_KEY={PEM_PATH}")

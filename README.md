# OpenSearch Snapshot Repository Setup Script

A bash script to automate the setup of an S3 snapshot repository for OpenSearch domains.

## 📋 Prerequisites

- AWS CLI installed and configured
- Bash shell
- Appropriate AWS permissions

## 🔑 Permissions

The following IAM permissions are required to run this script:

- `iam:CreateRole` - Create IAM roles for snapshot and client access
- `iam:PutRolePolicy` - Attach policies to the created IAM roles
- `iam:DeleteRolePolicy` - Remove policies from IAM roles during cleanup
- `iam:GetRole` - Verify role creation and retrieve role ARNs
- `iam:GetRolePolicy` - Retrieve and verify role policies
- `s3:CreateBucket` - Create the S3 bucket for storing snapshots

### Minimum Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:DeleteRole",
        "iam:GetRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3BucketCreation",
      "Effect": "Allow",
      "Action": "s3:CreateBucket",
      "Resource": "*"
    }
  ]
}
```

## 🛠️ Installation

```
# OpenSearch Snapshot Repository Setup Script

A bash script to automate the setup of an S3 snapshot repository for OpenSearch domains.

## 📋 Prerequisites

- AWS CLI installed and configured
- Bash shell
- Appropriate AWS permissions

## 🛠️ Installation

```bash
git clone https://github.com/yourusername/Bash-Scripts.git
cd Bash-Scripts
chmod +x reg-snap-repo.sh
```

## 💻 Usage

```bash
./reg-snap-repo.sh [OPTIONS]
```

### Required Flags

| Flag | Description | Example |
|------|-------------|---------|
| `-d, --domain-name` | Name of your OpenSearch domain | `-d my-opensearch-domain` |
| `-r, --repository-name` | Name for the snapshot repository | `-r my-snapshot-repo` |
| `-b, --bucket-name` | Name for the S3 bucket | `-b my-snapshot-bucket` |
| `-c, --credentials` | OpenSearch master user credentials (format: username:password) | `-c 'admin:password'` |

### Optional Flags

| Flag | Description | Example |
|------|-------------|---------|
| `-R, --region` | AWS region for S3 bucket (default: us-east-1) | `-R eu-west-1` |
| `--cleanup` | Delete IAM resources after completion | `--cleanup` |
| `-h, --help` | Show help message | `-h` |

### Examples

```bash
# Basic usage
./reg-snap-repo.sh -d os-domain -r myrepo -b mybucket -c 'admin:password'

# With all options
./reg-snap-repo.sh --domain-name=os-domain \
                   --repository-name=myrepo \
                   --bucket-name=mybucket \
                   --region=eu-west-1 \
                   --credentials='admin:password' \
                   --cleanup

# Show help
./reg-snap-repo.sh -h
```

## 🔍 How It Works

1. Creates an S3 bucket for storing snapshots
2. Creates a snapshot role with necessary S3 permissions
3. Creates a client role with OpenSearch and IAM permissions
4. Maps the client role to OpenSearch's internal role
5. Registers the S3 repository with OpenSearch

## 🧹 Cleanup

When using the `--cleanup` flag, the script will:
1. Delete the client role and its policies
2. Delete the snapshot role and its policies
3. Preserve the S3 bucket for future use

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.


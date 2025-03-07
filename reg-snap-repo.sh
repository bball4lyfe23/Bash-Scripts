#!/usr/bin/env bash

# AUTHOR: @aniiii

# Demonstrates 7 flags:
#   Required:
#     -d, --domain-name
#     -r, --repository-name
#     -b, --bucket-name
#
#   Optional:
#     -R, --region         (defaults to "us-east-1" if not specified)
#     -c, --credentials    (no default, only set if provided)
#     --cleanup           (delete IAM resources after completion)
#
#   Help:
#     -h, --help           (prints usage)

# Polling configuration
MAX_RETRIES=30
RETRY_INTERVAL=10  # seconds

###################################
# Polling Functions
###################################

# Poll for IAM role existence
poll_iam_role() {
    local role_name=$1
    local retries=$MAX_RETRIES
    
    while [ $retries -gt 0 ]; do
        if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
            return 0
        fi
        sleep $RETRY_INTERVAL
        retries=$((retries - 1))
    done
    return 1
}

# Poll for IAM role policy attachment
poll_iam_role_policy() {
    local role_name=$1
    local policy_name=$2
    local retries=$MAX_RETRIES
    
    while [ $retries -gt 0 ]; do
        if aws iam get-role-policy --role-name "$role_name" --policy-name "$policy_name" >/dev/null 2>&1; then
            return 0
        fi
        sleep $RETRY_INTERVAL
        retries=$((retries - 1))
    done
    return 1
}

# Poll for policy propagation
poll_policy_propagation() {
    local role_name=$1
    local retries=1
    
    while [ $retries -gt 0 ]; do
        sleep $RETRY_INTERVAL
        retries=$((retries - 1))
    done
    return 0
}

###################################
# 1. Usage (help) function
###################################
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Required flags:"
  echo "  -d, --domain-name       <string>  (e.g., 'opensearch-domain')"
  echo "  -r, --repository-name   <string>  (e.g., 'myrepo')"
  echo "  -b, --bucket-name       <string>  (e.g., 'my-s3-bucket')"
  echo
  echo "Optional flags:"
  echo "  -R, --region            <string>  (Default: 'us-east-1')"
  echo "  -c, --credentials       <string>  (No default, only if provided)"
  echo "  --cleanup                          (Delete IAM resources after completion)"
  echo
  echo "Help flag:"
  echo "  -h, --help                       (Show this usage message)"
  echo
  echo "Examples:"
  echo "  $0 -d os-domain -r myrepo -b mybucket"
  echo "  $0 --domain-name=os-domain --repository-name=myrepo \\"
  echo "     --bucket-name=mybucket --region=eu-west-1 --credentials=/path/to/cred"
  echo "  $0 -d os-domain -r myrepo -b mybucket --cleanup"
  exit 1
}

###################################
# 2. Use 'getopt' to parse options
###################################
# Short options: d: r: b: R: c: h
# Long options : domain-name:, repository-name:, bucket-name:, region:, credentials:, help
OPTS=$(getopt -o d:r:b:R:c:h -l domain-name:,repository-name:,bucket-name:,region:,credentials:,help,cleanup -- "$@")
if [ $? -ne 0 ]; then
  usage
fi

# Reorder positional parameters according to what getopt parsed
eval set -- "$OPTS"

###################################
# 3. Initialize variables
###################################
DOMAIN_NAME=""
REPO_NAME=""
BUCKET_NAME=""
REGION="us-east-1"    # Default
CREDENTIALS=""
DOMAIN_ARN=""
DOMAIN_ENDPOINT=""
DISTRIBUTION=""
SNAPSHOT_ROLE_NAME="os-snapshot-role"
CLIENT_ROLE_NAME="os-client-role"
SHOW_HELP=0
CLEANUP=0

# Store original credentials
ORIG_AWS_ACCESS_KEY_ID=""
ORIG_AWS_SECRET_ACCESS_KEY=""
ORIG_AWS_SESSION_TOKEN=""

###################################
# 4. Process each option
###################################
while true; do
  case "$1" in
    -d|--domain-name)
      DOMAIN_NAME="$2"
      shift 2
      ;;
    -r|--repository-name)
      REPO_NAME="$2"
      shift 2
      ;;
    -b|--bucket-name)
      BUCKET_NAME="$2"
      shift 2
      ;;
    -R|--region)
      REGION="$2"
      shift 2
      ;;
    -c|--credentials)
      CREDENTIALS="$2"
      shift 2
      ;;
    --cleanup)
      CLEANUP=1
      shift
      ;;
    -h|--help)
      SHOW_HELP=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      ;;
  esac
done

###################################
# 5. Show usage if -h/--help was set
###################################
if [ $SHOW_HELP -eq 1 ]; then
  usage
fi

###################################
# 6. Validate required flags
###################################
if [ -z "$DOMAIN_NAME" ] || [ -z "$REPO_NAME" ] || [ -z "$BUCKET_NAME" ]; then
  echo "Error: -d/--domain-name, -r/--repository-name, and -b/--bucket-name are required."
  usage
fi

#######################################
# 7. Handle Command Flags/Set Variable
#######################################

eval $(aws opensearch describe-domain --domain-name $DOMAIN_NAME --query 'DomainStatus.[ARN,Endpoint,EngineVersion]' --output text 2>/dev/null \
  | awk '{printf("export DOMAIN_ARN=%s; export DOMAIN_ENDPOINT=%s; ", $1, $2); if(substr($3,1,13)=="Elasticsearch")printf("export DISTRIBUTION=_opendistro;"); else if(substr($3,1,10)=="OpenSearch")printf("export DISTRIBUTION=_plugins;"); else printf("export DISTRIBUTION=UNKNOWN;");}')



######################
# 8. Create S3 Bucket
######################
echo "🚀 Starting repository setup for '$REPO_NAME'..."
aws s3api create-bucket --bucket ${BUCKET_NAME} --region ${REGION} >/dev/null 2>&1

##########################
# 9. Create Snapshot Role
##########################

echo "🔑 Creating Snapshot Role for OpenSearch domain access..."

# Create Trust Policy
SNAPSHOT_ROLE_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "es.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

# Create Role
aws iam create-role --role-name $SNAPSHOT_ROLE_NAME --assume-role-policy-document "$SNAPSHOT_ROLE_TRUST_POLICY" --query 'Role.Arn' --output text >/dev/null 2>&1

# Poll for role creation
if ! poll_iam_role "$SNAPSHOT_ROLE_NAME"; then
    echo "❌ Failed to create snapshot role. Exiting..."
    exit 1
fi

# Get the role ARN after confirming it exists
SNAPSHOT_ROLE_ARN=$(aws iam get-role --role-name "$SNAPSHOT_ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)

# Create Permissions Policy
SNAPSHOT_ROLE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF
)

# Attach Policy to Role
aws iam put-role-policy --role-name $SNAPSHOT_ROLE_NAME --policy-name opensearch-snapshot-policy --policy-document "$SNAPSHOT_ROLE_POLICY" >/dev/null 2>&1

# Poll for policy attachment
if ! poll_iam_role_policy "$SNAPSHOT_ROLE_NAME" "opensearch-snapshot-policy"; then
    echo "Failed to attach policy to snapshot role. Exiting..."
    exit 1
fi

# Wait for policy propagation
if ! poll_policy_propagation "$SNAPSHOT_ROLE_NAME"; then
    echo "Failed to confirm policy propagation for snapshot role. Exiting..."
    exit 1
fi

#########################
# 10. Create Client Role
#########################

echo "👤 Creating Client Role for user access..."

# Get Current IAM Principal
CURR_PRINCIPAL=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)

# Create Trust Policy
CLIENT_ROLE_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$CURR_PRINCIPAL"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

# Create Client Role
aws iam create-role --role-name "$CLIENT_ROLE_NAME" --assume-role-policy-document "$CLIENT_ROLE_TRUST_POLICY" --query 'Role.Arn' --output text >/dev/null 2>&1

# Poll for role creation
if ! poll_iam_role "$CLIENT_ROLE_NAME"; then
    echo "❌ Failed to create client role. Exiting..."
    exit 1
fi

# Get the role ARN after confirming it exists
CLIENT_ROLE_ARN=$(aws iam get-role --role-name "$CLIENT_ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)

# Create Permissions Policy
CLIENT_ROLE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "es:ESHttp*",
      "Resource": "${DOMAIN_ARN}/*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "${SNAPSHOT_ROLE_ARN}"
    }
  ]
}
EOF
)

# Attach Policy to Role
aws iam put-role-policy --role-name "$CLIENT_ROLE_NAME" --policy-name opensearch-client-policy --policy-document "$CLIENT_ROLE_POLICY" >/dev/null 2>&1

# Poll for policy attachment
if ! poll_iam_role_policy "$CLIENT_ROLE_NAME" "opensearch-client-policy"; then
    echo "Failed to attach policy to client role. Exiting..."
    exit 1
fi

# Wait for policy propagation
if ! poll_policy_propagation "$CLIENT_ROLE_NAME"; then
    echo "Failed to confirm policy propagation for client role. Exiting..."
    exit 1
fi

#######################################
# 11. Map Client Role to Internal Role
#######################################

echo "🔗 Mapping Client Role to OpenSearch internal role..."

TEST_PAYLOAD=$(cat <<EOF
{
  "users": ["$CLIENT_ROLE_ARN"]
}
EOF
)

curl -XPUT "https://$DOMAIN_ENDPOINT/$DISTRIBUTION/_security/api/rolesmapping/manage_snapshots" \
    -H 'Content-Type: application/json' \
    -d "$TEST_PAYLOAD" \
    -u "$CREDENTIALS" >/dev/null 2>&1


##########################
# 12. Register Repository
##########################

echo "📦 Registering repository '$REPO_NAME' with OpenSearch domain..."

# Construct Payload

PAYLOAD=$(cat <<EOF
{
  "type": "s3",
  "settings": {
    "bucket": "$BUCKET_NAME",
    "region": "$REGION",
    "role_arn": "$SNAPSHOT_ROLE_ARN"
  }
}
EOF
)


# Store original credentials before assuming client role
ORIG_AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
ORIG_AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
ORIG_AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN"

# Assume Role
eval $(aws sts assume-role --role-arn "$CLIENT_ROLE_ARN" --role-session-name "MySession" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text 2>/dev/null | awk "{print \"export AWS_ACCESS_KEY_ID=\"\$1\" ; export AWS_SECRET_ACCESS_KEY=\"\$2\" ; export AWS_SESSION_TOKEN=\"\$3}")


curl \
  --request PUT "https://$DOMAIN_ENDPOINT/_snapshot/$REPO_NAME" \
  --aws-sigv4 "aws:amz:us-east-1:es" \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  -H "x-amz-security-token:$AWS_SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null 2>&1


#########################
# 13. Clean Up Resources
#########################
if [ $CLEANUP -eq 1 ]; then
    echo "🧹 Cleaning up resources..."
    
    # Restore original credentials
    export AWS_ACCESS_KEY_ID="$ORIG_AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$ORIG_AWS_SECRET_ACCESS_KEY"
    export AWS_SESSION_TOKEN="$ORIG_AWS_SESSION_TOKEN"
    
    # Delete client role policy and role
    aws iam delete-role-policy --role-name "$CLIENT_ROLE_NAME" --policy-name opensearch-client-policy >/dev/null 2>&1
    aws iam delete-role --role-name "$CLIENT_ROLE_NAME" >/dev/null 2>&1
    
    # Delete snapshot role policy and role
    aws iam delete-role-policy --role-name "$SNAPSHOT_ROLE_NAME" --policy-name opensearch-snapshot-policy >/dev/null 2>&1
    aws iam delete-role --role-name "$SNAPSHOT_ROLE_NAME" >/dev/null 2>&1
    
    echo "✅ Cleanup completed successfully"
fi

echo "✅ Repository setup completed successfully!"
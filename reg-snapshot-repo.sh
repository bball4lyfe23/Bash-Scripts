#!/usr/bin/env bash

# AUTHOR: @aniiii

# Demonstrates 6 flags:
#   Required:
#     -d, --domain-name
#     -r, --repository-name
#     -b, --bucket-name
#
#   Optional:
#     -R, --region         (defaults to "us-east-1" if not specified)
#     -c, --credentials    (no default, only set if provided)
#
#   Help:
#     -h, --help           (prints usage)

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
  echo
  echo "Help flag:"
  echo "  -h, --help                       (Show this usage message)"
  echo
  echo "Examples:"
  echo "  $0 -d example.com -r myrepo -b mybucket"
  echo "  $0 --domain-name=example.com --repository-name=myrepo \\"
  echo "     --bucket-name=mybucket --region=eu-west-1 --credentials=/path/to/cred"
  exit 1
}

###################################
# 2. Use 'getopt' to parse options
###################################
# Short options: d: r: b: R: c: h
# Long options : domain-name:, repository-name:, bucket-name:, region:, credentials:, help
OPTS=$(getopt -o d:r:b:R:c:h -l domain-name:,repository-name:,bucket-name:,region:,credentials:,help -- "$@")
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
SNAPSHOT_ROLE_NAME="final-test-my-snapshot-role-1"
CLIENT_ROLE_NAME="final-test-opensearch-client-role-1"
SHOW_HELP=0

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

eval $(aws opensearch describe-domain --domain-name loggingprd --query 'DomainStatus.[ARN,Endpoint,EngineVersion]' --output text \
  | awk '{printf("export DOMAIN_ARN=%s; export DOMAIN_ENDPOINT=%s; ", $1, $2); if(substr($3,1,13)=="Elasticsearch")printf("export DISTRIBUTION=_opendistro;"); else if(substr($3,1,10)=="OpenSearch")printf("export DISTRIBUTION=_plugins;"); else printf("export DISTRIBUTION=UNKNOWN;");}')



######################
# 8. Create S3 Bucket
######################
echo "Creating S3 Bucket: $BUCKET_NAME"
aws s3api create-bucket --bucket ${BUCKET_NAME} --region ${REGION}


##########################
# 9. Create Snapshot Role
##########################

echo "Creating Snapshot Role"

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

SNAPSHOT_ROLE_ARN=$(aws iam create-role --role-name $SNAPSHOT_ROLE_NAME --assume-role-policy-document "$SNAPSHOT_ROLE_TRUST_POLICY" --query 'Role.Arn' --output text)

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

aws iam put-role-policy --role-name $SNAPSHOT_ROLE_NAME --policy-name opensearch-snapshot-policy --policy-document "$SNAPSHOT_ROLE_POLICY"

# Wait for Policy to be Attached
sleep 5

#########################
# 10. Create Client Role
#########################

echo "Creating Client Role"

# Get Current IAM Principal
CURR_PRINCIPAL=$(aws sts get-caller-identity --query Arn --output text)

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
CLIENT_ROLE_ARN=$(aws iam create-role --role-name "$CLIENT_ROLE_NAME" --assume-role-policy-document "$CLIENT_ROLE_TRUST_POLICY" --query 'Role.Arn' --output text)

#Create Permissions Policy

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
aws iam put-role-policy --role-name "$CLIENT_ROLE_NAME" --policy-name opensearch-client-policy --policy-document "$CLIENT_ROLE_POLICY"

# Wait for Policy to be Attached
sleep 5


#######################################
# 11. Map Client Role to Internal Role
#######################################

echo "Mapping Client Role to Internal Role"

TEST_PAYLOAD=$(cat <<EOF
{
  "users": ["$CLIENT_ROLE_ARN"]
}
EOF
)

curl -XPUT "https://$DOMAIN_ENDPOINT/$DISTRIBUTION/_security/api/rolesmapping/manage_snapshots" \
    -H 'Content-Type: application/json' \
    -d "$TEST_PAYLOAD" \
    -u 'aniiii:!Hdurina59110'


##########################
# 12. Register Repository
##########################

# Construct Payload

echo "Registering Repository: $REPO_NAME"

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


# Assume Role
eval $(aws sts assume-role --role-arn "$CLIENT_ROLE_ARN" --role-session-name "MySession" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text | awk "{print \"export AWS_ACCESS_KEY_ID=\"\$1\" ; export AWS_SECRET_ACCESS_KEY=\"\$2\" ; export AWS_SESSION_TOKEN=\"\$3}")


curl \
  --request PUT "https://$DOMAIN_ENDPOINT/_snapshot/$REPO_NAME" \
  --aws-sigv4 "aws:amz:us-east-1:es" \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  -H "x-amz-security-token:$AWS_SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \


#########################
# 13. Clean Up Resources
#########################
#aws iam delete-role-policy --role-name opensearch-client-role --policy-name opensearch-client-policy
#aws iam delete-role --role-name opensearch-client-role
#aws iam delete-role-policy --role-name $SNAPSHOT_ROLE_NAME --policy-name opensearch-snapshot-policy
#aws iam delete-role --role-name $SNAPSHOT_ROLE_NAME
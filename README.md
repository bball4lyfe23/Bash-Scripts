# Bash-Scripts
Bash Scripts to automate common use cases for AWS Services


## Amazon OpenSearch SnapShot Repository Registration
reg-snapshot-repo.sh

### Demonstrates 6 flags:
   Required:
     -d, --domain-name     (provide only the domain name, not the arn, e.g. 'my-domain')
     -r, --repository-name (choose repository name, can be any string, e.g. 'my-repo')
     -b, --bucket-name     (choose bucket name for repo, must follow S3 naming conventions, e.g. 'my-bucket-123456')
     -c, --credentials    (Internal Master User, e.g. 'admin:password')
     
   Optional:
     -R, --region         (defaults to "us-east-1" if not specified)
     
   Help:
     -h, --help           (prints usage)


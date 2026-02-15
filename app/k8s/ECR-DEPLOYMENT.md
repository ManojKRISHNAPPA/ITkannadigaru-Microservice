# AWS ECR Deployment Guide - InstaClone Microservices

## Overview

Your InstaClone application uses **AWS Elastic Container Registry (ECR)** for storing Docker images instead of Docker Hub. This guide covers ECR-specific deployment steps.

## Current ECR Images

```
156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/backend-service:1
156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/auth-service:1
156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/user-service:1
156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/frontend:1
```

**Registry**: `156299069385.dkr.ecr.us-west-2.amazonaws.com`
**Repository Prefix**: `itkannadigaru/`
**Region**: `us-west-2`

## Prerequisites

1. **AWS CLI** installed and configured
   ```bash
   aws --version
   aws configure
   ```

2. **kubectl** installed and configured
   ```bash
   kubectl version --client
   ```

3. **Kubernetes cluster** (EKS, minikube, kind, etc.)

4. **Docker** installed and running
   ```bash
   docker --version
   ```

5. **AWS credentials** with ECR permissions:
   - `ecr:GetAuthorizationToken`
   - `ecr:BatchCheckLayerAvailability`
   - `ecr:GetDownloadUrlForLayer`
   - `ecr:BatchGetImage`
   - `ecr:PutImage` (for pushing images)
   - `ecr:InitiateLayerUpload`
   - `ecr:UploadLayerPart`
   - `ecr:CompleteLayerUpload`

## Quick Start - 3 Steps

### Step 1: Create ECR Pull Secret

ECR requires authentication to pull images. Create a Kubernetes secret:

```bash
./create-ecr-secret.sh
```

This script:
- Gets ECR authentication token from AWS
- Creates a Kubernetes docker-registry secret
- Configures it in the `instaclone` namespace

**Important**: ECR tokens expire after 12 hours. You'll need to regenerate the secret periodically (see automation options below).

### Step 2: Create Application Secrets

Create secrets for database, JWT, and AWS credentials:

```bash
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="YOUR_SECURE_PASSWORD" \
  --from-literal=db-password="YOUR_SECURE_PASSWORD" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_AWS_ACCESS_KEY" \
  --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone
```

### Step 3: Deploy to Kubernetes

```bash
# Option A: Using the automated script (recommended)
./deploy-ecr.sh

# Option B: Manual deployment
kubectl apply -k k8s/base/
```

## Building and Pushing New Images to ECR

When you make changes to your code and want to build new images:

```bash
# Build and push all services with version 2
./build-and-push-ecr.sh 2

# Build and push to a different region
./build-and-push-ecr.sh 2 us-east-1
```

This script:
1. Authenticates with ECR
2. Creates ECR repositories if they don't exist
3. Builds Docker images
4. Tags images with version number and "latest"
5. Pushes to ECR

After pushing new images, update the version in `k8s/base/kustomization.yaml`:

```yaml
images:
  - name: 156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/backend-service
    newTag: "2"  # Update version here
  - name: 156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/auth-service
    newTag: "2"
  # ... etc
```

Then redeploy:

```bash
kubectl apply -k k8s/base/
```

## ECR Authentication - Manual Method

If you prefer to create the ECR secret manually:

### Get ECR Login Token

```bash
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  156299069385.dkr.ecr.us-west-2.amazonaws.com
```

### Create Kubernetes Secret

```bash
# Get the token
ECR_TOKEN=$(aws ecr get-login-password --region us-west-2)

# Create the secret
kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=156299069385.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --namespace=instaclone
```

### Verify Secret

```bash
kubectl get secret ecr-registry-secret -n instaclone
```

## ECR Token Expiration Problem

**Problem**: ECR tokens expire after 12 hours, causing pods to fail when pulling images.

### Solution 1: Manual Refresh (Simple)

Set up a cron job to refresh the secret:

```bash
# Add to crontab (runs every 6 hours)
crontab -e

# Add this line:
0 */6 * * * /path/to/create-ecr-secret.sh
```

### Solution 2: Kubernetes CronJob (Better)

Create a CronJob to refresh the ECR secret automatically:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-token-refresh
  namespace: instaclone
spec:
  schedule: "0 */10 * * *"  # Every 10 hours
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: ecr-token-refresher
          containers:
          - name: refresh-token
            image: amazon/aws-cli:latest
            command:
            - /bin/bash
            - -c
            - |
              TOKEN=$(aws ecr get-login-password --region us-west-2)
              kubectl delete secret ecr-registry-secret -n instaclone || true
              kubectl create secret docker-registry ecr-registry-secret \
                --docker-server=156299069385.dkr.ecr.us-west-2.amazonaws.com \
                --docker-username=AWS \
                --docker-password="${TOKEN}" \
                --namespace=instaclone
          restartPolicy: Never
```

### Solution 3: IAM Roles for Service Accounts (IRSA) - Best for EKS

If you're using **Amazon EKS**, use IRSA (IAM Roles for Service Accounts):

```bash
# 1. Create IAM policy
cat > ecr-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name ECRReadOnlyPolicy \
  --policy-document file://ecr-policy.json

# 2. Create service account
eksctl create iamserviceaccount \
  --name ecr-access \
  --namespace instaclone \
  --cluster your-cluster-name \
  --attach-policy-arn arn:aws:iam::156299069385:policy/ECRReadOnlyPolicy \
  --approve

# 3. Update deployments to use this service account
```

Then add to each deployment:

```yaml
spec:
  template:
    spec:
      serviceAccountName: ecr-access
      # No need for imagePullSecrets with IRSA!
```

## Verify Deployment

### Check Pods

```bash
kubectl get pods -n instaclone
```

All pods should be in `Running` status. If you see `ImagePullBackOff`, the ECR secret might be missing or expired.

### Check Events

```bash
kubectl get events -n instaclone --sort-by='.lastTimestamp'
```

Look for ECR authentication errors.

### Test Image Pull

```bash
# Test if Kubernetes can pull from ECR
kubectl run test-ecr \
  --image=156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/backend-service:1 \
  --image-pull-policy=Always \
  --restart=Never \
  --namespace=instaclone \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"ecr-registry-secret"}]}}'

# Check status
kubectl get pod test-ecr -n instaclone

# Clean up
kubectl delete pod test-ecr -n instaclone
```

## Managing ECR Repositories

### List ECR Repositories

```bash
aws ecr describe-repositories --region us-west-2
```

### List Images in a Repository

```bash
aws ecr list-images \
  --repository-name itkannadigaru/backend-service \
  --region us-west-2
```

### Delete Old Images

```bash
# Delete a specific image
aws ecr batch-delete-image \
  --repository-name itkannadigaru/backend-service \
  --region us-west-2 \
  --image-ids imageTag=old-version

# List and delete untagged images
IMAGES_TO_DELETE=$(aws ecr list-images \
  --repository-name itkannadigaru/backend-service \
  --region us-west-2 \
  --filter "tagStatus=UNTAGGED" \
  --query 'imageIds[*]' \
  --output json)

aws ecr batch-delete-image \
  --repository-name itkannadigaru/backend-service \
  --region us-west-2 \
  --image-ids "$IMAGES_TO_DELETE"
```

### Set Lifecycle Policy (Auto-cleanup)

```bash
cat > lifecycle-policy.json <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF

aws ecr put-lifecycle-policy \
  --repository-name itkannadigaru/backend-service \
  --region us-west-2 \
  --lifecycle-policy-text file://lifecycle-policy.json
```

## Cost Optimization

### ECR Pricing (us-west-2)

- **Storage**: $0.10 per GB/month
- **Data Transfer OUT**: $0.09 per GB (to internet)
- **Data Transfer IN**: Free

### Tips to Reduce Costs

1. **Clean up old images** regularly
2. **Use lifecycle policies** to auto-delete old images
3. **Compress Docker layers** with multi-stage builds (already done)
4. **Use image tags** wisely (don't create too many)
5. **Delete unused repositories**

## Troubleshooting

### Error: "no basic auth credentials"

**Cause**: ECR secret is missing or expired
**Fix**: Run `./create-ecr-secret.sh`

### Error: "ImagePullBackOff"

```bash
# Check pod details
kubectl describe pod <pod-name> -n instaclone

# Common causes:
# 1. ECR secret missing - Run ./create-ecr-secret.sh
# 2. Image doesn't exist - Check ECR console
# 3. Wrong region - Verify region in image URL
```

### Error: "requested access to the resource is denied"

**Cause**: AWS credentials don't have ECR permissions
**Fix**: Add ECR policies to your IAM user/role

```bash
# Check current user
aws sts get-caller-identity

# Attach ECR policy
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess
```

### ECR Token Expired During Deployment

```bash
# Regenerate secret
./create-ecr-secret.sh

# Restart deployments to use new secret
kubectl rollout restart deployment/backend -n instaclone
kubectl rollout restart deployment/auth-service -n instaclone
kubectl rollout restart deployment/user-service -n instaclone
kubectl rollout restart deployment/frontend -n instaclone
```

## CI/CD Integration with ECR

### GitHub Actions Example

```yaml
name: Build and Deploy to ECR

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2

      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build and push
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          ./build-and-push-ecr.sh $IMAGE_TAG
```

## Security Best Practices

1. **Enable Image Scanning** (already enabled in build script)
   ```bash
   aws ecr put-image-scanning-configuration \
     --repository-name itkannadigaru/backend-service \
     --region us-west-2 \
     --image-scanning-configuration scanOnPush=true
   ```

2. **Enable Encryption** (already enabled)
   - ECR uses AES-256 encryption by default

3. **Use IAM Policies** to restrict access
   - Principle of least privilege
   - Separate read/write permissions

4. **Enable VPC Endpoints** for private access
   ```bash
   # No internet traversal for ECR pulls
   aws ec2 create-vpc-endpoint \
     --vpc-id vpc-xxxxx \
     --service-name com.amazonaws.us-west-2.ecr.dkr
   ```

5. **Tag images properly**
   - Use semantic versioning
   - Don't rely solely on "latest"

## View ECR Images in AWS Console

Visit: https://console.aws.amazon.com/ecr/repositories?region=us-west-2

Or use AWS CLI:

```bash
# List all your repositories
aws ecr describe-repositories --region us-west-2 --output table

# View images in a specific repository
aws ecr describe-images \
  --repository-name itkannadigaru/backend-service \
  --region us-west-2 \
  --output table
```

## Next Steps

1. Set up ECR token refresh automation (Solution 2 or 3 above)
2. Configure ECR lifecycle policies to auto-cleanup old images
3. Set up image vulnerability scanning
4. Integrate with CI/CD pipeline
5. Consider using Amazon EKS with IRSA for seamless ECR access
6. Set up monitoring and alerts for failed image pulls

## Quick Reference Commands

```bash
# Create ECR secret
./create-ecr-secret.sh

# Deploy application
./deploy-ecr.sh

# Build and push new version
./build-and-push-ecr.sh 2

# Refresh ECR secret manually
ECR_TOKEN=$(aws ecr get-login-password --region us-west-2)
kubectl delete secret ecr-registry-secret -n instaclone
kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=156299069385.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --namespace=instaclone

# Check ECR images
aws ecr list-images --repository-name itkannadigaru/backend-service --region us-west-2

# View image scan results
aws ecr describe-image-scan-findings \
  --repository-name itkannadigaru/backend-service \
  --region us-west-2 \
  --image-id imageTag=1
```

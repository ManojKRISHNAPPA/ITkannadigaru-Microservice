#!/bin/bash

# Create ECR Pull Secret for Kubernetes
# This script creates a Kubernetes secret to pull images from AWS ECR

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-156299069385}"
NAMESPACE="${NAMESPACE:-instaclone}"
SECRET_NAME="ecr-registry-secret"

echo "=========================================="
echo "Creating ECR Pull Secret for Kubernetes"
echo "=========================================="
echo "AWS Region: $AWS_REGION"
echo "AWS Account: $AWS_ACCOUNT_ID"
echo "Namespace: $NAMESPACE"
echo "Secret Name: $SECRET_NAME"
echo "=========================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Install it from: https://aws.amazon.com/cli/"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Check AWS credentials
echo -e "${BLUE}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

CALLER_IDENTITY=$(aws sts get-caller-identity --output text)
echo -e "${GREEN}✓ AWS credentials found${NC}"
echo "  $CALLER_IDENTITY"

# Create namespace if it doesn't exist
echo -e "${BLUE}Creating namespace if needed...${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Get ECR login token
echo -e "${BLUE}Getting ECR login token...${NC}"
ECR_TOKEN=$(aws ecr get-login-password --region $AWS_REGION)

if [ -z "$ECR_TOKEN" ]; then
    echo -e "${RED}Error: Failed to get ECR token${NC}"
    exit 1
fi

echo -e "${GREEN}✓ ECR token retrieved${NC}"

# Delete existing secret if it exists
if kubectl get secret $SECRET_NAME -n $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}Deleting existing secret...${NC}"
    kubectl delete secret $SECRET_NAME -n $NAMESPACE
fi

# Create the docker-registry secret
echo -e "${BLUE}Creating Kubernetes secret...${NC}"
kubectl create secret docker-registry $SECRET_NAME \
    --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
    --docker-username=AWS \
    --docker-password="${ECR_TOKEN}" \
    --namespace=$NAMESPACE

echo -e "${GREEN}✓ Secret created successfully${NC}"

# Verify the secret
echo -e "${BLUE}Verifying secret...${NC}"
kubectl get secret $SECRET_NAME -n $NAMESPACE

echo ""
echo "=========================================="
echo -e "${GREEN}ECR Pull Secret Created Successfully!${NC}"
echo "=========================================="
echo ""
echo "Secret details:"
echo "  Name: $SECRET_NAME"
echo "  Namespace: $NAMESPACE"
echo "  Registry: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo ""
echo -e "${YELLOW}NOTE: ECR tokens expire after 12 hours${NC}"
echo "You'll need to regenerate this secret periodically or use:"
echo "  - IAM Roles for Service Accounts (IRSA) on EKS"
echo "  - ECR Credential Helper"
echo ""
echo "To regenerate the secret, run this script again:"
echo "  ./create-ecr-secret.sh"
echo ""
echo "Next step: Deploy your application"
echo "  kubectl apply -k k8s/base/"
echo ""

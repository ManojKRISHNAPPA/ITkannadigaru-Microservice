#!/bin/bash

# InstaClone - Quick Deploy Script for AWS ECR Images
# This script deploys the entire application to Kubernetes using ECR images

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

NAMESPACE="instaclone"
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-156299069385}"

echo "=========================================="
echo "InstaClone Kubernetes Deployment (ECR)"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "AWS Region: $AWS_REGION"
echo "AWS Account: $AWS_ACCOUNT_ID"
echo "=========================================="

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Install from: https://aws.amazon.com/cli/"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${BLUE}Current context:${NC}"
kubectl config current-context

read -p "Continue with deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Create namespace if it doesn't exist
echo -e "${BLUE}Creating namespace...${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create ECR pull secret
echo -e "${BLUE}Creating ECR pull secret...${NC}"
echo -e "${YELLOW}Getting ECR login token...${NC}"

ECR_TOKEN=$(aws ecr get-login-password --region $AWS_REGION)

if [ -z "$ECR_TOKEN" ]; then
    echo -e "${RED}Error: Failed to get ECR token${NC}"
    exit 1
fi

# Delete existing ECR secret if it exists
if kubectl get secret ecr-registry-secret -n $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}Deleting existing ECR secret...${NC}"
    kubectl delete secret ecr-registry-secret -n $NAMESPACE
fi

# Create the docker-registry secret
kubectl create secret docker-registry ecr-registry-secret \
    --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
    --docker-username=AWS \
    --docker-password="${ECR_TOKEN}" \
    --namespace=$NAMESPACE

echo -e "${GREEN}✓ ECR secret created${NC}"

# Check if application secrets exist
if kubectl get secret instaclone-secrets -n $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}Warning: Application secrets already exist. Skipping secret creation.${NC}"
else
    echo -e "${YELLOW}Creating application secrets...${NC}"
    echo -e "${RED}WARNING: Using default secrets. Change these in production!${NC}"

    # Generate a random JWT secret
    JWT_SECRET=$(openssl rand -base64 32)

    kubectl create secret generic instaclone-secrets \
        --from-literal=mysql-root-password="changeme123" \
        --from-literal=db-password="changeme123" \
        --from-literal=jwt-secret="$JWT_SECRET" \
        --from-literal=aws-access-key-id="YOUR_AWS_KEY" \
        --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
        --namespace=$NAMESPACE

    echo -e "${GREEN}✓ Application secrets created${NC}"
fi

# Deploy using kustomize
echo -e "${BLUE}Deploying all services...${NC}"
kubectl apply -k k8s/base/ -n $NAMESPACE

echo -e "${GREEN}✓ Deployment submitted${NC}"

# Wait for deployments to be ready
echo -e "${BLUE}Waiting for deployments to be ready...${NC}"
echo "This may take a few minutes..."

kubectl wait --for=condition=available --timeout=300s \
    deployment/backend \
    deployment/auth-service \
    deployment/user-service \
    deployment/frontend \
    -n $NAMESPACE 2>/dev/null || echo -e "${YELLOW}Some deployments are still starting up...${NC}"

echo -e "${GREEN}✓ Deployments are progressing${NC}"

# Wait for MySQL to be ready
echo -e "${BLUE}Waiting for MySQL to be ready...${NC}"
kubectl wait --for=condition=ready --timeout=300s \
    pod -l app=mysql \
    -n $NAMESPACE 2>/dev/null || echo -e "${YELLOW}MySQL is still starting up...${NC}"

# Show deployment status
echo ""
echo "=========================================="
echo -e "${GREEN}Deployment Complete!${NC}"
echo "=========================================="

echo ""
echo -e "${BLUE}Pods:${NC}"
kubectl get pods -n $NAMESPACE

echo ""
echo -e "${BLUE}Services:${NC}"
kubectl get svc -n $NAMESPACE

echo ""
echo -e "${BLUE}Ingress:${NC}"
kubectl get ingress -n $NAMESPACE

# Get ingress IP/hostname
INGRESS_IP=$(kubectl get ingress instaclone-ingress-simple -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
INGRESS_HOSTNAME=$(kubectl get ingress instaclone-ingress-simple -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

echo ""
echo "=========================================="
echo "Access your application:"
echo "=========================================="

if [ ! -z "$INGRESS_IP" ]; then
    echo "IP: http://$INGRESS_IP"
    echo ""
    echo "Add to /etc/hosts:"
    echo "$INGRESS_IP instaclone.local"
elif [ ! -z "$INGRESS_HOSTNAME" ]; then
    echo "Hostname: http://$INGRESS_HOSTNAME"
else
    echo "Ingress is pending... run:"
    echo "  kubectl get ingress -n $NAMESPACE -w"
fi

echo ""
echo "Test endpoints:"
echo "  http://instaclone.local/api/health"
echo "  http://instaclone.local/api/version"
echo "  http://instaclone.local/auth/register"
echo "  http://instaclone.local/"
echo ""

echo "View logs:"
echo "  kubectl logs -f deployment/backend -n $NAMESPACE"
echo "  kubectl logs -f deployment/auth-service -n $NAMESPACE"
echo "  kubectl logs -f deployment/user-service -n $NAMESPACE"
echo ""

echo -e "${YELLOW}NOTE: ECR tokens expire after 12 hours${NC}"
echo "To refresh the ECR secret, run:"
echo "  ./create-ecr-secret.sh"
echo ""

echo "Clean up:"
echo "  kubectl delete namespace $NAMESPACE"
echo ""

#!/bin/bash

# InstaClone - Build and Push All Docker Images to AWS ECR
# Usage: ./build-and-push-ecr.sh [version] [region]

set -e  # Exit on any error

VERSION=${1:-1}
AWS_REGION=${2:-us-west-2}
AWS_ACCOUNT_ID="156299069385"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_REPO_PREFIX="itkannadigaru"
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "=========================================="
echo "Building InstaClone Docker Images for ECR"
echo "=========================================="
echo "ECR Registry: $ECR_REGISTRY"
echo "Repository Prefix: $ECR_REPO_PREFIX"
echo "Version: $VERSION"
echo "Build Time: $BUILD_TIME"
echo "AWS Region: $AWS_REGION"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Install from: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
echo -e "${BLUE}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

echo -e "${GREEN}✓ AWS credentials found${NC}"

# Login to ECR
echo -e "${BLUE}Logging in to ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

echo -e "${GREEN}✓ Logged in to ECR${NC}"

# Function to create ECR repository if it doesn't exist
create_ecr_repo() {
    local repo_name=$1
    local full_repo_name="${ECR_REPO_PREFIX}/${repo_name}"

    echo -e "${BLUE}Checking if ECR repository exists: $full_repo_name${NC}"

    if ! aws ecr describe-repositories \
        --repository-names "$full_repo_name" \
        --region $AWS_REGION &> /dev/null; then

        echo -e "${YELLOW}Creating ECR repository: $full_repo_name${NC}"
        aws ecr create-repository \
            --repository-name "$full_repo_name" \
            --region $AWS_REGION \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256

        echo -e "${GREEN}✓ Repository created${NC}"
    else
        echo -e "${GREEN}✓ Repository exists${NC}"
    fi
}

# Function to build and push an image
build_and_push() {
    local service=$1
    local context=$2
    local ecr_repo_name=$3
    local image_name="${ECR_REGISTRY}/${ECR_REPO_PREFIX}/${ecr_repo_name}"

    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}Building $service...${NC}"
    echo -e "${BLUE}======================================${NC}"

    # Ensure ECR repository exists
    create_ecr_repo "$ecr_repo_name"

    cd "$context"

    # Build the image
    echo -e "${BLUE}Building Docker image...${NC}"
    docker build \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILD_TIME="$BUILD_TIME" \
        -t "$image_name:$VERSION" \
        -t "$image_name:latest" \
        .

    echo -e "${GREEN}✓ Built $image_name:$VERSION${NC}"

    # Push the image
    echo -e "${BLUE}Pushing to ECR...${NC}"
    docker push "$image_name:$VERSION"
    docker push "$image_name:latest"

    echo -e "${GREEN}✓ Pushed $image_name:$VERSION${NC}"
    echo -e "${GREEN}✓ Pushed $image_name:latest${NC}"

    cd - > /dev/null
}

# Build and push all services
echo ""
echo "=========================================="
echo "Building all services..."
echo "=========================================="

build_and_push "Backend Service" "./backend" "backend-service"
build_and_push "Auth Service" "./auth-service" "auth-service"
build_and_push "User Service" "./user-service" "user-service"
build_and_push "Frontend" "./frontend" "frontend"

echo ""
echo "=========================================="
echo -e "${GREEN}All images built and pushed successfully!${NC}"
echo "=========================================="
echo ""
echo "Images in ECR:"
echo "  - ${ECR_REGISTRY}/${ECR_REPO_PREFIX}/backend-service:$VERSION"
echo "  - ${ECR_REGISTRY}/${ECR_REPO_PREFIX}/auth-service:$VERSION"
echo "  - ${ECR_REGISTRY}/${ECR_REPO_PREFIX}/user-service:$VERSION"
echo "  - ${ECR_REGISTRY}/${ECR_REPO_PREFIX}/frontend:$VERSION"
echo ""
echo "View images in AWS Console:"
echo "  https://console.aws.amazon.com/ecr/repositories?region=$AWS_REGION"
echo ""
echo "Next steps:"
echo "  1. Create ECR pull secret: ./create-ecr-secret.sh"
echo "  2. Update image tags in k8s/base/kustomization.yaml if needed"
echo "  3. Deploy: kubectl apply -k k8s/base/"
echo ""

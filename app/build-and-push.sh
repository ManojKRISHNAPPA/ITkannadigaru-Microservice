#!/bin/bash

# InstaClone - Build and Push All Docker Images
# Usage: ./build-and-push.sh <dockerhub-username> [version]

set -e  # Exit on any error

DOCKER_USERNAME=${1:-yourdockerhubusername}
VERSION=${2:-latest}
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "=========================================="
echo "Building InstaClone Docker Images"
echo "=========================================="
echo "Docker Username: $DOCKER_USERNAME"
echo "Version: $VERSION"
echo "Build Time: $BUILD_TIME"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to build and push an image
build_and_push() {
    local service=$1
    local context=$2
    local image_name="$DOCKER_USERNAME/instaclone-$service"

    echo ""
    echo -e "${BLUE}Building $service...${NC}"
    cd "$context"

    # Build the image
    docker build \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILD_TIME="$BUILD_TIME" \
        -t "$image_name:$VERSION" \
        -t "$image_name:latest" \
        .

    echo -e "${GREEN}✓ Built $image_name:$VERSION${NC}"

    # Push the image
    echo -e "${BLUE}Pushing $service to Docker Hub...${NC}"
    docker push "$image_name:$VERSION"
    docker push "$image_name:latest"

    echo -e "${GREEN}✓ Pushed $image_name:$VERSION${NC}"

    cd - > /dev/null
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running"
    exit 1
fi

# Check if logged in to Docker Hub
if ! docker info | grep -q "Username"; then
    echo "Warning: You may not be logged in to Docker Hub"
    echo "Run: docker login"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Build and push all services
build_and_push "backend" "./backend"
build_and_push "auth" "./auth-service"
build_and_push "user" "./user-service"
build_and_push "frontend" "./frontend"

echo ""
echo "=========================================="
echo -e "${GREEN}All images built and pushed successfully!${NC}"
echo "=========================================="
echo ""
echo "Images:"
echo "  - $DOCKER_USERNAME/instaclone-backend:$VERSION"
echo "  - $DOCKER_USERNAME/instaclone-auth:$VERSION"
echo "  - $DOCKER_USERNAME/instaclone-user:$VERSION"
echo "  - $DOCKER_USERNAME/instaclone-frontend:$VERSION"
echo ""
echo "Next steps:"
echo "  1. Update k8s/base/kustomization.yaml with your Docker username"
echo "  2. Update secrets in k8s/base/secrets.yaml"
echo "  3. Deploy: kubectl apply -k k8s/base/"
echo ""

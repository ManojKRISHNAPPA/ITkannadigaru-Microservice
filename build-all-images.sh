#!/bin/bash

# Build script for all microservices
# This script builds all Docker images for the ITkannadigaru microservices project

set -e  # Exit on any error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default TAG
TAG="${TAG:-v1.0.0}"

echo ""
echo "=============================================="
echo "  ITkannadigaru Microservices Build Script"
echo "=============================================="
echo ""
echo "Building all services with tag: ${YELLOW}${TAG}${NC}"
echo ""

# Function to build a service
build_service() {
    local service_name=$1
    local service_path=$2
    local image_name=$3

    echo ""
    echo -e "${BLUE}[1/4] Building ${service_name}...${NC}"
    echo "----------------------------------------------"
    echo "Service path: $service_path"
    echo "Image name: ${image_name}:${TAG}"
    echo ""

    cd "$service_path"

    if docker build -t "${image_name}:${TAG}" .; then
        echo -e "${GREEN}✓ ${service_name} built successfully${NC}"
        cd - > /dev/null
        return 0
    else
        echo -e "${RED}✗ Failed to build ${service_name}${NC}"
        cd - > /dev/null
        return 1
    fi
}

# Build all services
echo "Starting build process..."

# 1. Build Backend
build_service "Backend Service" "app/backend" "deployecho-backend"

# 2. Build Frontend
build_service "Frontend Service" "app/frontend" "deployecho-frontend"

# 3. Build Auth Service
build_service "Auth Service" "app/auth-service" "instaclone-auth"

# 4. Build User Service
build_service "User Service" "app/user-service" "instaclone-user"

# Summary
echo ""
echo "=============================================="
echo "  Build Summary"
echo "=============================================="
echo ""

# List all built images
echo "Built images:"
docker images | head -1
docker images | grep -E "deployecho-backend.*${TAG}|deployecho-frontend.*${TAG}|instaclone-auth.*${TAG}|instaclone-user.*${TAG}"

echo ""
echo -e "${GREEN}✓ All services built successfully!${NC}"
echo ""
echo "Image tag: ${TAG}"
echo ""
echo "Next steps:"
echo "  1. Export TAG: export TAG=${TAG}"
echo "  2. Run services: docker-compose -f docker-compose-full.yml up -d"
echo "  3. Test services: ./test-all-services.sh"
echo ""

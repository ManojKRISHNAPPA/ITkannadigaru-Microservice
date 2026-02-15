#!/bin/bash

# Quick Start Script - Run everything with one command
# This script sets up and runs all services

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=============================================="
echo "  Quick Start - ITkannadigaru Microservices"
echo "=============================================="
echo ""

# Step 1: Set TAG
export TAG=v1.0.0
export JWT_SECRET=my-super-secret-jwt-key-change-in-production

echo -e "${YELLOW}Step 1: Building all Docker images...${NC}"
chmod +x build-all-images.sh
./build-all-images.sh

echo ""
echo -e "${YELLOW}Step 2: Starting all services with Docker Compose...${NC}"
echo "This may take a minute for MySQL to initialize..."
echo ""

docker-compose -f docker-compose-full.yml up -d

echo ""
echo -e "${YELLOW}Step 3: Waiting for services to be healthy...${NC}"
sleep 30

# Check if services are running
echo ""
echo "Checking service status..."
docker-compose -f docker-compose-full.yml ps

echo ""
echo -e "${YELLOW}Step 4: Running tests...${NC}"
sleep 5
chmod +x test-all-services.sh
./test-all-services.sh

echo ""
echo -e "${GREEN}=============================================="
echo "  All services are up and running!"
echo "==============================================${NC}"
echo ""
echo "Access the application:"
echo "  Frontend:     http://localhost:8088"
echo "  Backend API:  http://localhost:8088/api/"
echo "  Auth API:     http://localhost:3001"
echo "  User API:     http://localhost:3002"
echo ""
echo "View logs: docker-compose -f docker-compose-full.yml logs -f"
echo "Stop all:  docker-compose -f docker-compose-full.yml down"
echo ""

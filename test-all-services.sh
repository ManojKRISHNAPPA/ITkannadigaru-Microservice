#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "  ITkannadigaru Microservices Test Suite"
echo "=============================================="
echo ""

# Function to test endpoint
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"

    echo -n "Testing ${name}... "
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url")

    if [ "$response" -eq "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} (Status: $response)"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} (Expected: $expected_status, Got: $response)"
        return 1
    fi
}

# Function to test JSON endpoint
test_json_endpoint() {
    local name="$1"
    local url="$2"

    echo ""
    echo "Testing ${name}:"
    echo "URL: $url"
    response=$(curl -s "$url")
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    echo ""
}

# Test 1: Backend Service
echo ""
echo "=== Testing Backend Service ==="
test_endpoint "Backend Health" "http://localhost:8080/health"
test_json_endpoint "Backend Version" "http://localhost:8080/version"
test_json_endpoint "Backend Info" "http://localhost:8080/info"

# Test 2: Auth Service
echo ""
echo "=== Testing Auth Service ==="
test_endpoint "Auth Health" "http://localhost:3001/health"
test_json_endpoint "Auth Version" "http://localhost:3001/version"

# Test 3: Register a new user
echo ""
echo "=== Testing User Registration ==="
RANDOM_USER="testuser_$(date +%s)"
RANDOM_EMAIL="test_$(date +%s)@example.com"

echo "Registering user: $RANDOM_USER"
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:3001/auth/register \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"$RANDOM_USER\",
    \"email\": \"$RANDOM_EMAIL\",
    \"password\": \"password123\"
  }")

echo "$REGISTER_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$REGISTER_RESPONSE"

# Test 4: Login
echo ""
echo "=== Testing User Login ==="
echo "Logging in with: $RANDOM_EMAIL"
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$RANDOM_EMAIL\",
    \"password\": \"password123\"
  }")

echo "$LOGIN_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$LOGIN_RESPONSE"

# Extract token from response
TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
USER_ID=$(echo "$LOGIN_RESPONSE" | grep -o '"id":[0-9]*' | cut -d':' -f2 | head -1)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}✗ Failed to get token from login response${NC}"
    TOKEN="dummy-token"
fi

echo ""
echo "Token obtained: ${TOKEN:0:50}..."
echo "User ID: $USER_ID"

# Test 5: Validate token
echo ""
echo "=== Testing Token Validation ==="
VALIDATE_RESPONSE=$(curl -s http://localhost:3001/auth/validate \
  -H "Authorization: Bearer $TOKEN")

echo "$VALIDATE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$VALIDATE_RESPONSE"

# Test 6: User Service
echo ""
echo "=== Testing User Service ==="
test_endpoint "User Health" "http://localhost:3002/health"
test_json_endpoint "User Version" "http://localhost:3002/version"

# Test 7: Get user profile
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    echo ""
    echo "=== Testing Get User Profile ==="
    test_json_endpoint "Get User Profile (ID: $USER_ID)" "http://localhost:3002/users/$USER_ID"
fi

# Test 8: Update user profile
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ] && [ "$TOKEN" != "dummy-token" ]; then
    echo ""
    echo "=== Testing Update User Profile ==="
    UPDATE_RESPONSE=$(curl -s -X PUT "http://localhost:3002/users/$USER_ID/profile" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "bio": "Updated bio from automated test script"
      }')

    echo "$UPDATE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$UPDATE_RESPONSE"
fi

# Test 9: Search users
echo ""
echo "=== Testing User Search ==="
SEARCH_RESPONSE=$(curl -s "http://localhost:3002/users/search?q=test")
echo "$SEARCH_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$SEARCH_RESPONSE"

# Test 10: Nginx Proxy
echo ""
echo "=== Testing Nginx Proxy ==="
test_endpoint "Frontend via Proxy" "http://localhost:8088/"
test_endpoint "Backend via Proxy" "http://localhost:8088/api/health"
test_json_endpoint "Backend Version via Proxy" "http://localhost:8088/api/version"

# Test 11: Database connectivity
echo ""
echo "=== Testing Database ==="
echo "Checking MySQL container..."
docker exec instaclone-mysql mysqladmin -uroot -prootpassword ping 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ MySQL is alive${NC}"

    echo ""
    echo "User count in database:"
    docker exec instaclone-mysql mysql -uroot -prootpassword instaclone \
      -e "SELECT COUNT(*) as total_users FROM users;" 2>/dev/null
else
    echo -e "${RED}✗ MySQL connection failed${NC}"
fi

# Summary
echo ""
echo "=============================================="
echo "  Test Suite Complete"
echo "=============================================="
echo ""
echo "Services tested:"
echo "  - Backend Service (port 8080)"
echo "  - Auth Service (port 3001)"
echo "  - User Service (port 3002)"
echo "  - Nginx Proxy (port 8088)"
echo "  - MySQL Database (port 3306)"
echo ""
echo "Test user created:"
echo "  Username: $RANDOM_USER"
echo "  Email: $RANDOM_EMAIL"
echo "  Password: password123"
echo "  User ID: $USER_ID"
echo ""
echo "Access the application at: http://localhost:8088"
echo ""

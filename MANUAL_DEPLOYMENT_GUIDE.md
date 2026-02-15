# Manual Deployment Guide - ITkannadigaru Microservices

## Overview
This guide provides step-by-step instructions to manually build, run, and test all microservices locally using Docker.

## Architecture
- **Backend** (port 8080): Simple Express API
- **Frontend** (port 80): React app with Vite
- **Auth-service** (port 3001): Authentication with JWT + MySQL
- **User-service** (port 3002): User profiles, followers + MySQL
- **MySQL** (port 3306): Database for auth and user services
- **Nginx** (port 8088): Reverse proxy routing requests

---

## Prerequisites

### 1. Install Docker
```bash
# Check if Docker is installed
docker --version
docker-compose --version
```

### 2. Set Environment Variables
```bash
# Set image tag version (use any tag you want)
export TAG=v1.0.0

# Database credentials
export DB_HOST=mysql
export DB_PORT=3306
export DB_USER=root
export DB_PASSWORD=rootpassword
export DB_NAME=instaclone

# JWT Secret
export JWT_SECRET=my-super-secret-jwt-key-change-in-production
```

---

## Step 1: Build All Docker Images

### Build Backend Service
```bash
cd app/backend
docker build -t deployecho-backend:${TAG} .
cd ../..
```

### Build Frontend Service
```bash
cd app/frontend
docker build -t deployecho-frontend:${TAG} .
cd ../..
```

### Build Auth Service
```bash
cd app/auth-service
docker build -t instaclone-auth:${TAG} .
cd ../..
```

### Build User Service
```bash
cd app/user-service
docker build -t instaclone-user:${TAG} .
cd ../..
```

### Verify All Images Built Successfully
```bash
docker images | grep -E "deployecho|instaclone"
```

You should see:
```
deployecho-backend    v1.0.0
deployecho-frontend   v1.0.0
instaclone-auth       v1.0.0
instaclone-user       v1.0.0
```

---

## Step 2: Set Up MySQL Database

### Option A: Using Docker MySQL (Recommended for local testing)

Create a MySQL container:
```bash
docker run -d \
  --name instaclone-mysql \
  --network bridge \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=instaclone \
  -p 3306:3306 \
  mysql:8.0
```

Wait 30 seconds for MySQL to start, then initialize the database:
```bash
# Copy SQL script into container
docker cp scripts/init-db.sql instaclone-mysql:/tmp/init-db.sql

# Execute SQL script
docker exec -i instaclone-mysql mysql -uroot -prootpassword < scripts/init-db.sql
```

Verify database is initialized:
```bash
docker exec -it instaclone-mysql mysql -uroot -prootpassword -e "USE instaclone; SHOW TABLES;"
```

### Option B: Using Existing MySQL Server

If you have MySQL running on your server:
```bash
# Connect to your MySQL server
mysql -h YOUR_MYSQL_HOST -u root -p

# Run the initialization script
source scripts/init-db.sql

# Verify
USE instaclone;
SHOW TABLES;
```

---

## Step 3: Run All Services with Docker Compose

### Update docker-compose.yml
The updated `docker-compose.yml` includes all services + MySQL. See the updated file below.

### Start All Services
```bash
# Export the TAG variable
export TAG=v1.0.0

# Start all services in detached mode
docker-compose up -d

# Check all containers are running
docker-compose ps
```

Expected output:
```
NAME                      STATUS
deployecho-backend        Up
deployecho-frontend       Up
instaclone-auth           Up
instaclone-user           Up
deployecho-proxy          Up
instaclone-mysql          Up
```

### View Logs
```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f backend
docker-compose logs -f auth-service
docker-compose logs -f user-service
docker-compose logs -f mysql
```

---

## Step 4: Test Each Service

### Test Backend Service
```bash
# Health check
curl http://localhost:8080/health

# Version check
curl http://localhost:8080/version

# Info check
curl http://localhost:8080/info
```

Expected response:
```json
{
  "service": "deployecho-backend",
  "version": "v1.0.0",
  "env": "dev"
}
```

### Test Auth Service
```bash
# Health check
curl http://localhost:3001/health

# Register a new user
curl -X POST http://localhost:3001/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser1",
    "email": "test1@example.com",
    "password": "password123"
  }'

# Login
curl -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test1@example.com",
    "password": "password123"
  }'

# Save the token from login response
export TOKEN="YOUR_TOKEN_HERE"

# Validate token
curl http://localhost:3001/auth/validate \
  -H "Authorization: Bearer $TOKEN"
```

### Test User Service
```bash
# Health check
curl http://localhost:3002/health

# Get user profile (userId 1 was created by init-db.sql)
curl http://localhost:3002/users/1

# Update profile (requires auth token from login)
curl -X PUT http://localhost:3002/users/1/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "bio": "Updated bio from manual test"
  }'

# Search users
curl "http://localhost:3002/users/search?q=test"
```

### Test Frontend + Nginx Proxy
```bash
# Access frontend through nginx proxy
curl http://localhost:8088/

# Access backend through nginx proxy
curl http://localhost:8088/api/health
curl http://localhost:8088/api/version
```

Open in browser:
```
http://localhost:8088
```

---

## Step 5: Database Commands

### Connect to MySQL Container
```bash
docker exec -it instaclone-mysql mysql -uroot -prootpassword instaclone
```

### Useful SQL Queries
```sql
-- Show all users
SELECT id, username, email, created_at FROM users;

-- Count users
SELECT COUNT(*) as total_users FROM users;

-- Show all posts
SELECT p.id, u.username, p.caption, p.created_at
FROM posts p
JOIN users u ON p.user_id = u.id;

-- Show followers relationships
SELECT
  u1.username as follower,
  u2.username as following
FROM follows f
JOIN users u1 ON f.follower_id = u1.id
JOIN users u2 ON f.following_id = u2.id;

-- Exit MySQL
EXIT;
```

---

## Step 6: Stop and Clean Up

### Stop All Services
```bash
docker-compose down
```

### Stop and Remove Volumes (WARNING: This deletes database data)
```bash
docker-compose down -v
```

### Remove All Built Images
```bash
docker rmi deployecho-backend:v1.0.0
docker rmi deployecho-frontend:v1.0.0
docker rmi instaclone-auth:v1.0.0
docker rmi instaclone-user:v1.0.0
```

### Clean Up MySQL Container
```bash
docker stop instaclone-mysql
docker rm instaclone-mysql
```

---

## Troubleshooting

### Container Not Starting
```bash
# Check container logs
docker logs <container_name>

# Inspect container
docker inspect <container_name>
```

### Database Connection Issues
```bash
# Check MySQL is running
docker exec instaclone-mysql mysqladmin -uroot -prootpassword ping

# Check database exists
docker exec -it instaclone-mysql mysql -uroot -prootpassword -e "SHOW DATABASES;"

# Restart MySQL
docker restart instaclone-mysql
```

### Port Already in Use
```bash
# Find process using port
lsof -i :8088
lsof -i :3306

# Kill process or change port in docker-compose.yml
```

### Auth Service Returns 500 Error
- Verify MySQL is running and initialized
- Check database credentials in environment variables
- Check auth-service logs: `docker logs instaclone-auth`

### User Service Returns 500 Error
- Same as Auth Service
- Additionally, verify S3 configuration if using avatar upload
- For local testing, S3 operations may fail (expected)

---

## Architecture Diagram

```
                     ┌──────────────┐
                     │   Browser    │
                     └──────┬───────┘
                            │
                     ┌──────▼───────┐
                     │    Nginx     │
                     │   (Port 8088) │
                     └──────┬───────┘
                            │
                ┌───────────┴───────────┐
                │                       │
         ┌──────▼───────┐      ┌───────▼────────┐
         │   Frontend    │      │    Backend     │
         │   (Port 80)   │      │   (Port 8080)  │
         └───────────────┘      └────────────────┘


     ┌─────────────────┐         ┌─────────────────┐
     │  Auth Service   │         │  User Service   │
     │  (Port 3001)    │         │  (Port 3002)    │
     └────────┬────────┘         └────────┬────────┘
              │                           │
              └───────────┬───────────────┘
                          │
                   ┌──────▼──────┐
                   │    MySQL    │
                   │  (Port 3306) │
                   └─────────────┘
```

---

## Next Steps: Jenkins Automation

After manual testing is complete, you can automate this process in Jenkins:

1. **Build Stage**: Run all `docker build` commands
2. **Push Stage**: Push images to Docker registry (ECR, Docker Hub, etc.)
3. **Deploy Stage**: SSH to server and run `docker-compose up -d`
4. **Test Stage**: Run curl commands to verify all services are healthy

---

## Notes

- For production, use proper secrets management (not environment variables)
- The user-service requires AWS S3 for avatar uploads (currently will fail if S3 not configured)
- Default passwords in init-db.sql are hashed with bcrypt
- JWT tokens expire after 24 hours (access token) and 30 days (refresh token)
- All services have health check endpoints at `/health`

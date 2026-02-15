# Server Deployment Instructions

## Overview
This guide explains how to deploy the ITkannadigaru microservices on your server manually before automating with Jenkins.

## Files Created
- `MANUAL_DEPLOYMENT_GUIDE.md` - Complete step-by-step manual guide
- `docker-compose-full.yml` - Updated compose file with all services + MySQL
- `nginx/nginx-full.conf` - Updated nginx config routing to all services
- `build-all-images.sh` - Script to build all Docker images
- `test-all-services.sh` - Script to test all endpoints
- `quickstart.sh` - One-command setup (build + run + test)

## On Your Server

### 1. Clone/Pull the Repository
```bash
cd /path/to/your/server
git clone <your-repo-url>
# OR if already cloned
git pull origin main
```

### 2. Make Scripts Executable
```bash
chmod +x build-all-images.sh
chmod +x test-all-services.sh
chmod +x quickstart.sh
```

### 3. Option A: Quick Start (Automated)
Run everything with one command:
```bash
./quickstart.sh
```

This will:
- Build all 4 Docker images
- Start all services (including MySQL)
- Wait for services to be healthy
- Run comprehensive tests

### 4. Option B: Manual Step-by-Step

#### Step 1: Build Images
```bash
export TAG=v1.0.0
./build-all-images.sh
```

#### Step 2: Start Services
```bash
docker-compose -f docker-compose-full.yml up -d
```

#### Step 3: View Logs
```bash
# All logs
docker-compose -f docker-compose-full.yml logs -f

# Specific service
docker-compose -f docker-compose-full.yml logs -f auth-service
```

#### Step 4: Test Services
```bash
./test-all-services.sh
```

## Service URLs

Once running, services are available at:

| Service | Direct Port | Via Nginx Proxy |
|---------|-------------|-----------------|
| Frontend | - | http://YOUR_SERVER:8088/ |
| Backend | 8080 | http://YOUR_SERVER:8088/api/ |
| Auth Service | 3001 | http://YOUR_SERVER:8088/auth/ |
| User Service | 3002 | http://YOUR_SERVER:8088/users/ |
| MySQL | 3306 | - |

## Manual Testing Examples

### Test Backend
```bash
curl http://localhost:8080/health
curl http://localhost:8080/version
```

### Test Auth Service
```bash
# Register
curl -X POST http://localhost:3001/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'

# Login
curl -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

### Test via Nginx Proxy
```bash
curl http://localhost:8088/api/health
curl http://localhost:8088/api/version
```

## Useful Commands

### View Running Containers
```bash
docker-compose -f docker-compose-full.yml ps
```

### Stop All Services
```bash
docker-compose -f docker-compose-full.yml down
```

### Restart a Service
```bash
docker-compose -f docker-compose-full.yml restart auth-service
```

### Access MySQL
```bash
docker exec -it instaclone-mysql mysql -uroot -prootpassword instaclone
```

### Check Logs
```bash
# All services
docker-compose -f docker-compose-full.yml logs -f

# Specific service
docker-compose -f docker-compose-full.yml logs -f backend
docker-compose -f docker-compose-full.yml logs -f auth-service
docker-compose -f docker-compose-full.yml logs -f user-service
docker-compose -f docker-compose-full.yml logs -f mysql
```

### Rebuild a Specific Service
```bash
# Example: Rebuild auth service after code change
cd app/auth-service
docker build -t instaclone-auth:v1.0.0 .
cd ../..
docker-compose -f docker-compose-full.yml up -d auth-service
```

## Database Management

### Initialize/Reset Database
```bash
# Copy SQL script to container
docker cp scripts/init-db.sql instaclone-mysql:/tmp/init-db.sql

# Execute SQL script
docker exec -i instaclone-mysql mysql -uroot -prootpassword < scripts/init-db.sql
```

### Backup Database
```bash
docker exec instaclone-mysql mysqldump -uroot -prootpassword instaclone > backup_$(date +%Y%m%d_%H%M%S).sql
```

### Restore Database
```bash
docker exec -i instaclone-mysql mysql -uroot -prootpassword instaclone < backup_20260215_120000.sql
```

## Troubleshooting

### Container won't start
```bash
# Check logs
docker logs <container-name>

# Inspect container
docker inspect <container-name>

# Restart container
docker restart <container-name>
```

### Port already in use
```bash
# Find what's using the port
sudo lsof -i :8088
sudo lsof -i :3306

# Kill the process or change port in docker-compose-full.yml
```

### Database connection failed
```bash
# Check MySQL is running
docker ps | grep mysql

# Check MySQL logs
docker logs instaclone-mysql

# Restart MySQL
docker restart instaclone-mysql

# Wait 30 seconds and restart dependent services
docker-compose -f docker-compose-full.yml restart auth-service user-service
```

### Clean slate restart
```bash
# Stop everything
docker-compose -f docker-compose-full.yml down -v

# Remove all images
docker rmi deployecho-backend:v1.0.0
docker rmi deployecho-frontend:v1.0.0
docker rmi instaclone-auth:v1.0.0
docker rmi instaclone-user:v1.0.0

# Rebuild and restart
./quickstart.sh
```

## Next Steps: Jenkins Automation

After successful manual testing, you can automate this in Jenkins:

### Jenkins Pipeline Stages
1. **Checkout**: Pull code from Git
2. **Build**: Run `build-all-images.sh`
3. **Test**: Unit tests (if any)
4. **Push**: Push images to Docker registry (ECR/Docker Hub)
5. **Deploy**: SSH to server and run `docker-compose up -d`
6. **Verify**: Run `test-all-services.sh`

### Jenkins Environment Variables
```groovy
environment {
    TAG = "v${BUILD_NUMBER}"
    JWT_SECRET = credentials('jwt-secret')
    DB_PASSWORD = credentials('db-password')
}
```

## Notes for Production

⚠️ **Before production deployment:**

1. Change database password (not `rootpassword`)
2. Use proper JWT_SECRET (not default)
3. Set up SSL/TLS certificates
4. Configure proper AWS credentials for S3 (user-service)
5. Set up database backups
6. Configure monitoring and alerts
7. Use Docker secrets instead of environment variables
8. Set up log aggregation (ELK, CloudWatch, etc.)
9. Configure firewall rules
10. Set up CI/CD pipeline in Jenkins

## Architecture Summary

```
Server (Port 8088)
    │
    ├─ Nginx Proxy
    │   ├─ / → Frontend (React)
    │   ├─ /api/ → Backend (Express)
    │   ├─ /auth/ → Auth Service (JWT + MySQL)
    │   └─ /users/ → User Service (Profiles + MySQL)
    │
    └─ MySQL Database (instaclone)
        ├─ users
        ├─ posts
        ├─ follows
        └─ ... (10 tables total)
```

## Support

For detailed explanations, see `MANUAL_DEPLOYMENT_GUIDE.md`

For issues, check:
- Container logs: `docker logs <container-name>`
- Service health: `curl http://localhost:<port>/health`
- Database: `docker exec -it instaclone-mysql mysql -uroot -prootpassword`

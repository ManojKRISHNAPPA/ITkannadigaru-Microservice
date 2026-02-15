# 🚀 ITkannadigaru Microservices - Complete Setup Package

## 📋 Summary

This package contains everything you need to manually build, deploy, and test your microservices before automating with Jenkins.

---

## 📁 Files Created

### 1. **MANUAL_DEPLOYMENT_GUIDE.md** 📖
**Purpose**: Complete step-by-step manual deployment guide

**What it contains**:
- Prerequisites and setup
- Step-by-step build instructions for each service
- MySQL database setup (Docker and native)
- How to run services with docker-compose
- Testing instructions for each service
- Database commands and queries
- Troubleshooting guide
- Architecture diagram

**When to use**: First time setup, understanding the architecture, or troubleshooting

---

### 2. **SERVER_DEPLOYMENT.md** 🖥️
**Purpose**: Quick reference for server deployment

**What it contains**:
- Quick start commands
- Service URLs table
- Manual testing examples
- Useful Docker commands
- Database management commands
- Troubleshooting common issues
- Jenkins automation preparation notes

**When to use**: On your server for quick reference, daily operations

---

### 3. **docker-compose-full.yml** 🐳
**Purpose**: Updated Docker Compose configuration with all services

**What it includes**:
- All 4 microservices (backend, frontend, auth, user)
- MySQL database with automatic initialization
- Nginx reverse proxy
- Health checks for all services
- Proper networking and dependencies
- Environment variable configuration

**How to use**:
```bash
export TAG=v1.0.0
docker-compose -f docker-compose-full.yml up -d
```

---

### 4. **nginx/nginx-full.conf** 🔀
**Purpose**: Updated Nginx configuration routing to all services

**What it routes**:
- `/` → Frontend (React app)
- `/api/` → Backend service
- `/auth/` → Auth service
- `/users/` → User service
- `/health` → Nginx health check

**Features**:
- CORS headers for API requests
- Gzip compression
- Proper proxy headers
- File upload support (10MB max)

---

### 5. **build-all-images.sh** 🏗️
**Purpose**: Automated script to build all Docker images

**What it does**:
- Builds all 4 microservice images
- Tags them with specified version
- Shows build summary
- Provides next steps

**How to use**:
```bash
export TAG=v1.0.0
chmod +x build-all-images.sh
./build-all-images.sh
```

---

### 6. **test-all-services.sh** 🧪
**Purpose**: Comprehensive testing script for all services

**What it tests**:
- Backend health and endpoints
- Auth service (register, login, token validation)
- User service (profiles, search)
- Nginx proxy routing
- MySQL database connectivity
- Creates test user automatically

**How to use**:
```bash
chmod +x test-all-services.sh
./test-all-services.sh
```

**Output**: Color-coded test results with pass/fail status

---

### 7. **quickstart.sh** ⚡
**Purpose**: One-command setup for everything

**What it does**:
1. Builds all Docker images
2. Starts all services with docker-compose
3. Waits for services to be healthy
4. Runs comprehensive tests
5. Displays access URLs

**How to use**:
```bash
chmod +x quickstart.sh
./quickstart.sh
```

**Perfect for**: First-time setup, quick deployments, testing

---

### 8. **Jenkinsfile.example** 🤖
**Purpose**: Jenkins pipeline template for automation

**Pipeline stages**:
1. **Checkout**: Pull code from Git
2. **Build**: Build all Docker images
3. **Test**: Test images locally
4. **Tag**: Tag images with version
5. **Push**: Push to Docker registry (ECR/Docker Hub)
6. **Deploy**: SSH to server and deploy
7. **Smoke Tests**: Verify deployment

**Features**:
- Environment variable management
- Branch-specific deployment (main only)
- Automatic rollback on failure
- Slack notifications (optional)
- Old image cleanup

**How to use**:
1. Copy to `Jenkinsfile` in your repo
2. Update credentials and server details
3. Create Jenkins pipeline job
4. Point to your Git repo

---

## 🎯 Quick Start for Your Server

### Step 1: Copy files to server
```bash
# From your local machine
scp -r * user@your-server:/opt/itkannadigaru-microservice/
```

### Step 2: SSH to server
```bash
ssh user@your-server
cd /opt/itkannadigaru-microservice
```

### Step 3: Run quick start
```bash
chmod +x quickstart.sh
./quickstart.sh
```

### Step 4: Access your application
```
http://your-server-ip:8088
```

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   Your Server                    │
│                                                  │
│  ┌────────────┐        Port 8088                │
│  │   Nginx    │◄─────── Public Access           │
│  │   Proxy    │                                  │
│  └─────┬──────┘                                  │
│        │                                          │
│    ┌───┴───┬────────┬──────────┐                │
│    │       │        │          │                 │
│  ┌─▼─┐  ┌─▼──┐  ┌──▼───┐  ┌──▼───┐            │
│  │FE │  │BE  │  │Auth │  │User │             │
│  │:80│  │:8080│ │:3001│  │:3002│             │
│  └───┘  └────┘  └──┬──┘  └──┬───┘            │
│                     │        │                   │
│                  ┌──▼────────▼──┐               │
│                  │    MySQL     │               │
│                  │    :3306     │               │
│                  └──────────────┘               │
└─────────────────────────────────────────────────┘

Services:
- Frontend: React app (Vite)
- Backend: Express.js API
- Auth: JWT authentication + MySQL
- User: User profiles + followers + MySQL
- MySQL: Database (instaclone)
```

---

## 🔑 Key Environment Variables

### Required for Deployment
```bash
export TAG=v1.0.0                              # Image version
export JWT_SECRET=your-secret-key              # JWT signing key
```

### MySQL Configuration (already set in docker-compose)
```bash
DB_HOST=mysql
DB_PORT=3306
DB_USER=root
DB_PASSWORD=rootpassword
DB_NAME=instaclone
```

### Optional (for User Service S3 uploads)
```bash
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
S3_BUCKET=instaclone-media
S3_REGION=us-east-1
```

---

## 🧪 Testing Checklist

After deployment, verify these endpoints:

- [ ] Backend health: `curl http://localhost:8080/health`
- [ ] Backend version: `curl http://localhost:8080/version`
- [ ] Auth health: `curl http://localhost:3001/health`
- [ ] Auth register: Test user registration
- [ ] Auth login: Test user login
- [ ] User health: `curl http://localhost:3002/health`
- [ ] User profile: Test get user profile
- [ ] Nginx proxy: `curl http://localhost:8088/api/health`
- [ ] Frontend: Open browser to `http://localhost:8088`
- [ ] MySQL: `docker exec -it instaclone-mysql mysql -uroot -prootpassword instaclone`

**Or just run**: `./test-all-services.sh` ✅

---

## 📝 Common Commands

### Start everything
```bash
export TAG=v1.0.0
docker-compose -f docker-compose-full.yml up -d
```

### Stop everything
```bash
docker-compose -f docker-compose-full.yml down
```

### View logs
```bash
docker-compose -f docker-compose-full.yml logs -f
```

### Restart a service
```bash
docker-compose -f docker-compose-full.yml restart auth-service
```

### Rebuild and restart
```bash
./build-all-images.sh
docker-compose -f docker-compose-full.yml up -d --force-recreate
```

---

## 🚨 Troubleshooting

### Logs not showing?
```bash
docker-compose -f docker-compose-full.yml logs -f <service-name>
```

### Service won't start?
```bash
docker logs <container-name>
```

### Database connection failed?
```bash
docker restart instaclone-mysql
sleep 30
docker-compose -f docker-compose-full.yml restart auth-service user-service
```

### Port already in use?
```bash
sudo lsof -i :<port>
# Kill the process or change port in docker-compose-full.yml
```

---

## 📦 What's Next?

### After Manual Testing ✅
1. Verify all services work correctly
2. Test all API endpoints
3. Understand the architecture
4. Document any issues

### Before Jenkins Automation 🤖
1. Set up Docker registry (ECR/Docker Hub)
2. Configure Jenkins server
3. Add Jenkins credentials:
   - GitHub SSH key
   - Server SSH key
   - JWT secret
   - Database password
4. Update `Jenkinsfile.example` with your details
5. Create Jenkins pipeline job

### For Production 🚀
1. Change default passwords
2. Use proper secrets management
3. Set up SSL/TLS certificates
4. Configure AWS S3 for user-service
5. Set up monitoring and alerts
6. Configure log aggregation
7. Set up database backups
8. Configure firewall rules
9. Use Docker secrets
10. Set up CI/CD pipeline

---

## 📞 Support

- **Manual Guide**: See `MANUAL_DEPLOYMENT_GUIDE.md`
- **Server Reference**: See `SERVER_DEPLOYMENT.md`
- **Architecture**: See diagrams in this file
- **Testing**: Run `./test-all-services.sh`
- **Quick Start**: Run `./quickstart.sh`

---

## ✅ Success Criteria

Your deployment is successful when:
- ✅ All 4 microservices are running
- ✅ MySQL database is initialized
- ✅ Nginx is routing requests correctly
- ✅ All health checks pass
- ✅ You can register and login users
- ✅ Frontend loads in browser
- ✅ All tests in `test-all-services.sh` pass

---

## 🎉 You're Ready!

Everything you need is in this package. Start with the quickstart script, then move to manual testing, and finally automate with Jenkins.

Good luck! 🚀

# InstaClone Kubernetes - Quick Reference

## Quick Commands

### Deploy Everything
```bash
# Method 1: Using Kustomize (recommended)
kubectl apply -k k8s/base/

# Method 2: Using deploy script
./deploy.sh yourdockerhubusername

# Method 3: Manual deployment
kubectl create namespace instaclone
kubectl apply -f k8s/base/ -n instaclone
```

### Check Status
```bash
# All pods
kubectl get pods -n instaclone

# Specific service
kubectl get pods -l app=auth-service -n instaclone

# Detailed pod info
kubectl describe pod <pod-name> -n instaclone

# Watch pod status
kubectl get pods -n instaclone -w
```

### View Logs
```bash
# Follow logs
kubectl logs -f deployment/auth-service -n instaclone

# Last 100 lines
kubectl logs deployment/auth-service -n instaclone --tail=100

# All pods with label
kubectl logs -l app=auth-service -n instaclone

# Previous crashed container
kubectl logs <pod-name> -n instaclone --previous
```

### Scale Services
```bash
kubectl scale deployment auth-service --replicas=5 -n instaclone
kubectl scale deployment user-service --replicas=3 -n instaclone
```

### Update Deployment
```bash
# Update image
kubectl set image deployment/auth-service \
  auth-service=yourdockerhubusername/instaclone-auth:v2.0 \
  -n instaclone

# Rollout status
kubectl rollout status deployment/auth-service -n instaclone

# Rollout history
kubectl rollout history deployment/auth-service -n instaclone

# Rollback
kubectl rollout undo deployment/auth-service -n instaclone
```

### Debug Pods
```bash
# Shell into pod
kubectl exec -it deployment/auth-service -n instaclone -- /bin/sh

# Run command in pod
kubectl exec deployment/auth-service -n instaclone -- env | grep DB

# Port forward to local machine
kubectl port-forward deployment/auth-service 3001:3001 -n instaclone
```

### Secrets Management
```bash
# Create secret
kubectl create secret generic instaclone-secrets \
  --from-literal=jwt-secret=$(openssl rand -base64 32) \
  -n instaclone

# View secret (base64 encoded)
kubectl get secret instaclone-secrets -n instaclone -o yaml

# Decode secret
kubectl get secret instaclone-secrets -n instaclone \
  -o jsonpath='{.data.jwt-secret}' | base64 -d

# Edit secret
kubectl edit secret instaclone-secrets -n instaclone

# Delete secret
kubectl delete secret instaclone-secrets -n instaclone
```

### Database Operations
```bash
# Connect to MySQL
kubectl exec -it statefulset/mysql -n instaclone -- mysql -u root -p

# Run SQL from command line
kubectl exec -it statefulset/mysql -n instaclone -- \
  mysql -u root -p instaclone -e "SELECT COUNT(*) FROM users;"

# Backup database
kubectl exec statefulset/mysql -n instaclone -- \
  mysqldump -u root -p instaclone > backup.sql

# Restore database
kubectl exec -i statefulset/mysql -n instaclone -- \
  mysql -u root -p instaclone < backup.sql
```

### Ingress Operations
```bash
# Get ingress info
kubectl get ingress -n instaclone

# Describe ingress
kubectl describe ingress instaclone-ingress -n instaclone

# Get ingress IP/hostname
kubectl get ingress instaclone-ingress -n instaclone \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Resource Usage
```bash
# Pod resource usage
kubectl top pods -n instaclone

# Node resource usage
kubectl top nodes

# Specific pod
kubectl top pod <pod-name> -n instaclone
```

### Events and Troubleshooting
```bash
# Get events
kubectl get events -n instaclone --sort-by='.lastTimestamp'

# Watch events
kubectl get events -n instaclone -w

# Describe all resources
kubectl describe all -n instaclone
```

### Clean Up
```bash
# Delete all resources
kubectl delete -k k8s/base/

# Delete namespace (removes everything)
kubectl delete namespace instaclone

# Delete specific deployment
kubectl delete deployment auth-service -n instaclone
```

## API Testing

### Health Checks
```bash
# Backend
curl http://instaclone.local/api/health
curl http://instaclone.local/api/version

# Auth Service
curl http://instaclone.local/auth/health

# User Service
curl http://instaclone.local/users/health
```

### Register User
```bash
curl -X POST http://instaclone.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'
```

### Login
```bash
curl -X POST http://instaclone.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'

# Save token
TOKEN="<token-from-response>"
```

### Get User Profile
```bash
curl http://instaclone.local/users/1
```

### Update Profile
```bash
curl -X PUT http://instaclone.local/users/1/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "bio": "Hello from Kubernetes!"
  }'
```

### Follow User
```bash
curl -X POST http://instaclone.local/users/2/follow \
  -H "Authorization: Bearer $TOKEN"
```

## Environment Variables

### ConfigMap (instaclone-config)
- `DB_HOST`: mysql
- `DB_PORT`: 3306
- `DB_NAME`: instaclone
- `DB_USER`: root
- `ENV`: production
- `S3_REGION`: us-east-1
- `S3_BUCKET`: instaclone-media

### Secrets (instaclone-secrets)
- `mysql-root-password`: Database password
- `db-password`: Database password
- `jwt-secret`: JWT signing key
- `aws-access-key-id`: AWS credentials
- `aws-secret-access-key`: AWS credentials

## Service Endpoints

| Service      | Internal URL                    | External Path   |
|--------------|---------------------------------|-----------------|
| Frontend     | http://frontend:80              | /               |
| Backend      | http://backend:8080             | /api/*          |
| Auth Service | http://auth-service:3001        | /auth/*         |
| User Service | http://user-service:3002        | /users/*        |
| MySQL        | mysql:3306                      | N/A (internal)  |

## Docker Commands

### Build Images
```bash
# Build all
./build-and-push.sh yourdockerhubusername v1.0.0

# Build individual service
cd backend
docker build -t yourdockerhubusername/instaclone-backend:v1.0 .
docker push yourdockerhubusername/instaclone-backend:v1.0
```

### Local Testing
```bash
# Run locally
docker run -p 8080:8080 \
  -e DB_HOST=host.docker.internal \
  yourdockerhubusername/instaclone-backend:latest

# Run with compose (if you have docker-compose.yml)
docker-compose up
```

## Kustomize

### Build without applying
```bash
kubectl kustomize k8s/base/
```

### Create overlay for different environment
```bash
# Dev overlay
mkdir -p k8s/overlays/dev
cat > k8s/overlays/dev/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../base
namespace: instaclone-dev
images:
  - name: yourdockerhubusername/instaclone-backend
    newTag: dev
EOF

# Deploy dev overlay
kubectl apply -k k8s/overlays/dev/
```

## Common Issues

### Pod stuck in Pending
```bash
# Check events
kubectl describe pod <pod-name> -n instaclone

# Common causes:
# - Insufficient resources
# - PVC not bound
# - Image pull error
```

### Pod stuck in CrashLoopBackOff
```bash
# Check logs
kubectl logs <pod-name> -n instaclone

# Common causes:
# - Missing environment variables
# - Database connection failed
# - Application error
```

### Service not reachable
```bash
# Check service endpoints
kubectl get endpoints -n instaclone

# Check if pods are ready
kubectl get pods -n instaclone

# Check ingress
kubectl describe ingress instaclone-ingress -n instaclone
```

### Database connection issues
```bash
# Test from pod
kubectl exec -it deployment/auth-service -n instaclone -- nc -zv mysql 3306

# Check MySQL logs
kubectl logs statefulset/mysql -n instaclone
```

## Production Checklist

- [ ] Change all default secrets
- [ ] Set up SSL/TLS certificates
- [ ] Configure resource limits
- [ ] Set up monitoring (Prometheus/Grafana)
- [ ] Set up logging (ELK/Loki)
- [ ] Configure HPA for auto-scaling
- [ ] Set up backup for MySQL
- [ ] Configure network policies
- [ ] Use private container registry
- [ ] Set up CI/CD pipeline
- [ ] Configure pod security policies
- [ ] Set up alerting
- [ ] Document runbooks
- [ ] Load testing
- [ ] Disaster recovery plan

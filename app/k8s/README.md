# Kubernetes Deployment Guide - InstaClone Microservices

## Architecture Overview

```
                                    Internet
                                       |
                                       v
                            [Ingress Controller]
                                       |
                    +------------------+------------------+
                    |                  |                  |
                    v                  v                  v
              [Frontend:80]    [Backend:8080]    [Auth:3001]    [User:3002]
                    |                  |                  |            |
                    |                  |                  +------------+
                    |                  |                               |
                    |                  |                               v
                    |                  |                        [MySQL:3306]
                    |                  |                               |
                    |                  |                        [AWS S3 Bucket]
                    |                  +-------------------------------+
                    +--------------------------------------------------+
```

## Services and Ports

| Service       | Internal Port | Path Pattern | Purpose                              |
|---------------|---------------|--------------|--------------------------------------|
| Frontend      | 80            | `/`          | React SPA (serves UI)                |
| Backend       | 8080          | `/api/*`     | Deployment verification API          |
| Auth Service  | 3001          | `/auth/*`    | Authentication & user registration   |
| User Service  | 3002          | `/users/*`   | User profiles, follow, avatar upload |
| MySQL         | 3306          | N/A          | Database (internal only)             |

## Path-Based Routing (Ingress)

The Ingress controller routes traffic based on URL paths:

```
https://instaclone.yourdomain.com/auth/register    → auth-service:3001
https://instaclone.yourdomain.com/auth/login       → auth-service:3001
https://instaclone.yourdomain.com/users/123        → user-service:3002
https://instaclone.yourdomain.com/users/search     → user-service:3002
https://instaclone.yourdomain.com/api/health       → backend:8080
https://instaclone.yourdomain.com/                 → frontend:80
https://instaclone.yourdomain.com/dashboard        → frontend:80
```

## How Services Connect to Each Other

### 1. Frontend → Backend Services
- Frontend makes HTTP requests to `/auth/*`, `/users/*`, `/api/*`
- Ingress routes these requests to the appropriate backend service
- No direct pod-to-pod communication needed

### 2. Auth Service → MySQL
- Uses Kubernetes DNS: `mysql.instaclone.svc.cluster.local:3306`
- Simplified: `mysql:3306`
- Connection managed via environment variables:
  - `DB_HOST=mysql`
  - `DB_PORT=3306`
  - `DB_NAME=instaclone`
  - `DB_USER=root`
  - `DB_PASSWORD` (from Secret)

### 3. User Service → MySQL + S3
- **MySQL Connection**: Same as Auth Service (`mysql:3306`)
- **AWS S3**: Uses AWS SDK with credentials:
  - `AWS_ACCESS_KEY_ID` (from Secret)
  - `AWS_SECRET_ACCESS_KEY` (from Secret)
  - `S3_BUCKET=instaclone-media`
  - `S3_REGION=us-east-1`

### 4. Service Discovery
- Kubernetes creates DNS records automatically:
  - `mysql` → resolves to MySQL pod IP
  - `auth-service` → resolves to Auth Service pod IPs
  - `user-service` → resolves to User Service pod IPs
  - `backend` → resolves to Backend pod IPs
  - `frontend` → resolves to Frontend pod IPs

## Prerequisites

1. **Kubernetes cluster** (minikube, kind, EKS, GKE, AKS, etc.)
2. **kubectl** installed and configured
3. **NGINX Ingress Controller** installed
4. **Docker images** pushed to Docker Hub
5. **AWS S3 bucket** created (for user service)

## Step-by-Step Deployment

### Step 1: Install NGINX Ingress Controller

```bash
# For cloud providers (AWS, GCP, Azure)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# For minikube
minikube addons enable ingress

# For kind
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/kind/deploy.yaml
```

### Step 2: Create Namespace

```bash
kubectl create namespace instaclone
kubectl config set-context --current --namespace=instaclone
```

### Step 3: Update Secrets (IMPORTANT!)

Edit `k8s/base/secrets.yaml` and replace placeholder values:

```bash
# Generate a secure JWT secret
openssl rand -base64 32

# Update secrets.yaml with your actual values
# DO NOT commit secrets to Git!
```

**Better approach** - Create secrets from command line:

```bash
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="YOUR_SECURE_PASSWORD" \
  --from-literal=db-password="YOUR_SECURE_PASSWORD" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_AWS_KEY" \
  --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone
```

### Step 4: Update Docker Image Names

Edit `k8s/base/kustomization.yaml` and replace `yourdockerhubusername` with your Docker Hub username.

Or update each deployment YAML file:
- `backend-deployment.yaml`
- `auth-service-deployment.yaml`
- `user-service-deployment.yaml`
- `frontend-deployment.yaml`

### Step 5: Deploy All Services

Using Kustomize (recommended):

```bash
kubectl apply -k k8s/base/
```

Using kubectl:

```bash
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/secrets.yaml
kubectl apply -f k8s/base/mysql-statefulset.yaml
kubectl apply -f k8s/base/backend-deployment.yaml
kubectl apply -f k8s/base/auth-service-deployment.yaml
kubectl apply -f k8s/base/user-service-deployment.yaml
kubectl apply -f k8s/base/frontend-deployment.yaml
kubectl apply -f k8s/base/ingress.yaml
```

### Step 6: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n instaclone

# Check services
kubectl get svc -n instaclone

# Check ingress
kubectl get ingress -n instaclone

# View logs
kubectl logs -f deployment/auth-service -n instaclone
kubectl logs -f deployment/user-service -n instaclone
kubectl logs -f deployment/backend -n instaclone
kubectl logs -f deployment/frontend -n instaclone
```

### Step 7: Access the Application

Get the Ingress IP/hostname:

```bash
kubectl get ingress instaclone-ingress -n instaclone
```

**For local development** (minikube):

```bash
# Add to /etc/hosts
echo "$(minikube ip) instaclone.local" | sudo tee -a /etc/hosts

# Access at: http://instaclone.local
```

**For cloud providers**:
- Update DNS to point to the LoadBalancer IP
- Update `ingress.yaml` with your domain name

## Building and Pushing Docker Images

### Build all images:

```bash
# Backend
cd backend
docker build -t yourdockerhubusername/instaclone-backend:latest .
docker push yourdockerhubusername/instaclone-backend:latest

# Auth Service
cd ../auth-service
docker build -t yourdockerhubusername/instaclone-auth:latest .
docker push yourdockerhubusername/instaclone-auth:latest

# User Service
cd ../user-service
docker build -t yourdockerhubusername/instaclone-user:latest .
docker push yourdockerhubusername/instaclone-user:latest

# Frontend
cd ../frontend
docker build -t yourdockerhubusername/instaclone-frontend:latest .
docker push yourdockerhubusername/instaclone-frontend:latest
```

### Using version tags (recommended for production):

```bash
VERSION=1.0.0

docker build -t yourdockerhubusername/instaclone-backend:${VERSION} .
docker build -t yourdockerhubusername/instaclone-backend:latest .
docker push yourdockerhubusername/instaclone-backend:${VERSION}
docker push yourdockerhubusername/instaclone-backend:latest
```

## Testing the Deployment

### 1. Test Backend Health

```bash
curl http://instaclone.local/api/health
# Expected: "ok"

curl http://instaclone.local/api/version
# Expected: JSON with version info
```

### 2. Test Auth Service

```bash
# Register a user
curl -X POST http://instaclone.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'

# Login
curl -X POST http://instaclone.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
# Save the token from response
```

### 3. Test User Service

```bash
# Get user profile (replace {userId} and {token})
curl http://instaclone.local/users/1

# Update profile (requires authentication)
curl -X PUT http://instaclone.local/users/1/profile \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "bio": "Hello from Kubernetes!"
  }'
```

### 4. Test Frontend

```bash
# Access in browser
open http://instaclone.local
```

## Scaling Services

Scale individual services based on load:

```bash
# Scale frontend
kubectl scale deployment frontend --replicas=5 -n instaclone

# Scale auth service
kubectl scale deployment auth-service --replicas=3 -n instaclone

# Scale user service
kubectl scale deployment user-service --replicas=3 -n instaclone
```

## Monitoring and Debugging

### View logs:

```bash
# All pods
kubectl logs -l app=auth-service -n instaclone --tail=100 -f

# Specific pod
kubectl logs auth-service-7d9c8b5f4d-abc12 -n instaclone

# Previous crashed container
kubectl logs auth-service-7d9c8b5f4d-abc12 -n instaclone --previous
```

### Exec into pod:

```bash
kubectl exec -it deployment/auth-service -n instaclone -- /bin/sh

# Inside pod:
# Check environment variables
env | grep DB

# Test database connection
nc -zv mysql 3306

# Test other services
wget -O- http://user-service:3002/health
```

### Describe resources:

```bash
kubectl describe pod auth-service-xxx -n instaclone
kubectl describe deployment auth-service -n instaclone
kubectl describe ingress instaclone-ingress -n instaclone
```

## Updating Deployments

### Update a service with new image:

```bash
# Update image
kubectl set image deployment/auth-service \
  auth-service=yourdockerhubusername/instaclone-auth:v2.0.0 \
  -n instaclone

# Check rollout status
kubectl rollout status deployment/auth-service -n instaclone

# Rollback if needed
kubectl rollout undo deployment/auth-service -n instaclone
```

## Environment-Specific Configurations

Create overlays for different environments:

### Development overlay (`k8s/overlays/dev/kustomization.yaml`):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

namespace: instaclone-dev

patches:
  - path: replica-patch.yaml
    target:
      kind: Deployment

images:
  - name: yourdockerhubusername/instaclone-backend
    newTag: dev
```

### Production overlay (`k8s/overlays/prod/kustomization.yaml`):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

namespace: instaclone-prod

replicas:
  - name: auth-service
    count: 5
  - name: user-service
    count: 5

images:
  - name: yourdockerhubusername/instaclone-backend
    newTag: v1.0.0
```

Deploy with overlays:

```bash
# Development
kubectl apply -k k8s/overlays/dev/

# Production
kubectl apply -k k8s/overlays/prod/
```

## ArgoCD GitOps Setup (Coming Soon)

You mentioned creating a separate GitHub folder for ArgoCD GitOps. Here's the structure:

```
instaclone-gitops/
├── apps/
│   ├── backend.yaml
│   ├── auth-service.yaml
│   ├── user-service.yaml
│   └── frontend.yaml
├── projects/
│   └── instaclone-project.yaml
└── applicationsets/
    └── instaclone-appset.yaml
```

## Clean Up

Remove all resources:

```bash
kubectl delete -k k8s/base/
# or
kubectl delete namespace instaclone
```

## Troubleshooting

### Pods not starting?

```bash
kubectl get events -n instaclone --sort-by='.lastTimestamp'
kubectl describe pod <pod-name> -n instaclone
```

### Database connection issues?

```bash
# Check if MySQL is ready
kubectl exec -it statefulset/mysql -n instaclone -- mysql -u root -p

# Test from auth-service pod
kubectl exec -it deployment/auth-service -n instaclone -- nc -zv mysql 3306
```

### Ingress not working?

```bash
# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check ingress resource
kubectl describe ingress instaclone-ingress -n instaclone
```

## Security Best Practices

1. **DO NOT** commit secrets to Git
2. Use **Sealed Secrets** or **External Secrets Operator** in production
3. Enable **Network Policies** to restrict pod-to-pod traffic
4. Use **RBAC** to limit access to Kubernetes resources
5. Enable **Pod Security Policies** or **Pod Security Standards**
6. Use **TLS/SSL** for ingress (Let's Encrypt with cert-manager)
7. Regularly update images with security patches
8. Use **image scanning** (Trivy, Clair) in CI/CD pipeline

## Next Steps

1. Set up SSL/TLS certificates with cert-manager
2. Configure horizontal pod autoscaling (HPA)
3. Set up monitoring with Prometheus/Grafana
4. Configure log aggregation with ELK or Loki
5. Implement backup strategy for MySQL data
6. Set up ArgoCD for GitOps deployment
7. Configure service mesh (Istio/Linkerd) for advanced traffic management

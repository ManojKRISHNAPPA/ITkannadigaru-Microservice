# InstaClone - Complete Kubernetes Setup Summary

## 🎉 What Was Created

All Kubernetes manifests and deployment scripts have been generated and configured for your **AWS ECR** images.

## 📦 Your ECR Images

```
156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/backend-service:1
156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/auth-service:1
156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/user-service:1
156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/frontend:1
```

## 📁 Files Created

### Kubernetes Manifests (k8s/base/)
- ✅ `namespace.yaml` - Creates "instaclone" namespace
- ✅ `configmap.yaml` - Environment variables & MySQL init script
- ✅ `secrets.yaml` - Passwords, JWT secret, AWS credentials
- ✅ `mysql-statefulset.yaml` - MySQL database with persistent storage
- ✅ `backend-deployment.yaml` - Backend service (port 8080)
- ✅ `auth-service-deployment.yaml` - Auth service (port 3001)
- ✅ `user-service-deployment.yaml` - User service (port 3002)
- ✅ `frontend-deployment.yaml` - React frontend (port 80)
- ✅ `ingress.yaml` - Path-based routing (/api, /auth, /users, /)
- ✅ `kustomization.yaml` - Kustomize configuration

### Deployment Scripts
- ✅ `create-ecr-secret.sh` - Creates ECR authentication secret
- ✅ `deploy-ecr.sh` - One-command deployment to Kubernetes
- ✅ `build-and-push-ecr.sh` - Builds and pushes images to ECR
- ✅ `build-and-push.sh` - Legacy Docker Hub script
- ✅ `deploy.sh` - Legacy Docker Hub deployment

### Documentation
- ✅ `k8s/README.md` - Complete deployment guide
- ✅ `k8s/ARCHITECTURE.md` - Architecture diagrams & service flows
- ✅ `k8s/QUICKREF.md` - Quick command reference
- ✅ `k8s/ECR-DEPLOYMENT.md` - ECR-specific deployment guide
- ✅ `k8s/.gitignore` - Protects secrets from Git

## 🚀 Quick Start - Deploy to Kubernetes

### Prerequisites

1. AWS CLI configured
   ```bash
   aws configure
   ```

2. kubectl connected to your cluster
   ```bash
   kubectl cluster-info
   ```

3. NGINX Ingress Controller installed
   ```bash
   # For cloud (AWS/GCP/Azure)
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

   # For minikube
   minikube addons enable ingress
   ```

### Deploy in 3 Steps

#### Step 1: Create ECR Authentication Secret

```bash
./create-ecr-secret.sh
```

This creates a Kubernetes secret to pull images from your ECR.

**Note**: ECR tokens expire after 12 hours. See `k8s/ECR-DEPLOYMENT.md` for automation options.

#### Step 2: Create Application Secrets

```bash
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="YOUR_SECURE_PASSWORD" \
  --from-literal=db-password="YOUR_SECURE_PASSWORD" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_AWS_ACCESS_KEY" \
  --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone
```

#### Step 3: Deploy Everything

```bash
./deploy-ecr.sh
```

This script:
- Creates namespace
- Refreshes ECR secret
- Deploys all services
- Waits for pods to be ready
- Shows you how to access the app

## 🌐 Access Your Application

### Get Ingress IP/Hostname

```bash
kubectl get ingress -n instaclone
```

### For Local Testing (minikube)

```bash
# Get minikube IP
minikube ip

# Add to /etc/hosts
echo "$(minikube ip) instaclone.local" | sudo tee -a /etc/hosts

# Open in browser
open http://instaclone.local
```

### For Cloud Clusters

Update your DNS to point to the LoadBalancer IP/hostname from the ingress.

## 🔍 Verify Deployment

### Check All Pods

```bash
kubectl get pods -n instaclone
```

Expected output:
```
NAME                            READY   STATUS    RESTARTS   AGE
backend-xxxxx                   1/1     Running   0          2m
backend-yyyyy                   1/1     Running   0          2m
auth-service-xxxxx              1/1     Running   0          2m
auth-service-yyyyy              1/1     Running   0          2m
user-service-xxxxx              1/1     Running   0          2m
user-service-yyyyy              1/1     Running   0          2m
frontend-xxxxx                  1/1     Running   0          2m
frontend-yyyyy                  1/1     Running   0          2m
mysql-0                         1/1     Running   0          2m
```

### Test Endpoints

```bash
# Backend health
curl http://instaclone.local/api/health

# Backend version
curl http://instaclone.local/api/version

# Auth health
curl http://instaclone.local/auth/health

# User health
curl http://instaclone.local/users/health

# Frontend
curl http://instaclone.local/
```

### Register a Test User

```bash
curl -X POST http://instaclone.local/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'
```

## 🔄 Updating Your Application

### Build New Images

When you make code changes:

```bash
# Build and push version 2
./build-and-push-ecr.sh 2
```

### Update Kubernetes to Use New Version

Edit `k8s/base/kustomization.yaml`:

```yaml
images:
  - name: 156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/backend-service
    newTag: "2"  # Change version
  - name: 156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/auth-service
    newTag: "2"
  - name: 156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/user-service
    newTag: "2"
  - name: 156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/frontend
    newTag: "2"
```

### Deploy Updated Version

```bash
kubectl apply -k k8s/base/
```

### Verify Rollout

```bash
kubectl rollout status deployment/auth-service -n instaclone
kubectl rollout status deployment/user-service -n instaclone
kubectl rollout status deployment/backend -n instaclone
kubectl rollout status deployment/frontend -n instaclone
```

## 🛠️ Common Operations

### View Logs

```bash
# Follow logs
kubectl logs -f deployment/auth-service -n instaclone
kubectl logs -f deployment/user-service -n instaclone

# Last 100 lines
kubectl logs deployment/backend -n instaclone --tail=100

# All pods with label
kubectl logs -l app=auth-service -n instaclone
```

### Scale Services

```bash
# Scale up for high traffic
kubectl scale deployment auth-service --replicas=5 -n instaclone
kubectl scale deployment user-service --replicas=5 -n instaclone

# Scale down
kubectl scale deployment auth-service --replicas=2 -n instaclone
```

### Restart a Service

```bash
kubectl rollout restart deployment/auth-service -n instaclone
```

### Shell into a Pod

```bash
kubectl exec -it deployment/auth-service -n instaclone -- /bin/sh

# Inside the pod:
# Check environment
env | grep DB

# Test database connection
nc -zv mysql 3306

# Test other service
wget -O- http://user-service:3002/health
```

### Access MySQL Database

```bash
# Connect to MySQL
kubectl exec -it statefulset/mysql -n instaclone -- mysql -u root -p

# Inside MySQL:
USE instaclone;
SHOW TABLES;
SELECT * FROM users;
```

## 🔐 Security Reminder

### ECR Token Expiration

Your ECR authentication token expires after **12 hours**.

**Options to handle this:**

1. **Manual refresh** - Run `./create-ecr-secret.sh` every 12 hours
2. **Cron job** - Automate the script with cron
3. **Kubernetes CronJob** - Deploy a job to refresh automatically
4. **IRSA (EKS only)** - Use IAM Roles for Service Accounts

See `k8s/ECR-DEPLOYMENT.md` for detailed setup instructions.

## 📊 Service Architecture

```
Internet → Ingress Controller
              ↓
    ┌─────────┼─────────┬─────────┐
    ↓         ↓         ↓         ↓
Frontend  Backend   Auth      User
  :80      :8080    :3001     :3002
                      ↓         ↓
                      └────┬────┘
                           ↓
                        MySQL
                         :3306
```

**Path Routing:**
- `/` → Frontend (React SPA)
- `/api/*` → Backend Service
- `/auth/*` → Auth Service (login, register)
- `/users/*` → User Service (profiles, follow)

## 📚 Documentation

- **k8s/README.md** - Complete deployment guide with step-by-step instructions
- **k8s/ARCHITECTURE.md** - Architecture diagrams, service flows, scaling strategy
- **k8s/QUICKREF.md** - Quick command reference for daily operations
- **k8s/ECR-DEPLOYMENT.md** - ECR-specific guide, token management, troubleshooting

## 🧹 Clean Up

To remove everything:

```bash
# Delete namespace (removes all resources)
kubectl delete namespace instaclone

# Or delete with kustomize
kubectl delete -k k8s/base/
```

## 🎯 Next Steps

1. **Deploy to your cluster** - Run `./deploy-ecr.sh`
2. **Set up ECR token refresh** - See `k8s/ECR-DEPLOYMENT.md`
3. **Configure SSL/TLS** - Add cert-manager for HTTPS
4. **Set up monitoring** - Deploy Prometheus/Grafana
5. **Create GitOps repo** - Set up ArgoCD for automated deployments
6. **Configure autoscaling** - Add HorizontalPodAutoscaler
7. **Set up CI/CD** - Automate builds and deployments

## ⚡ Troubleshooting

### Pods in ImagePullBackOff

**Cause**: ECR secret expired or missing

**Fix**:
```bash
./create-ecr-secret.sh
kubectl rollout restart deployment/auth-service -n instaclone
```

### Pods in CrashLoopBackOff

**Cause**: Application error or database not ready

**Fix**:
```bash
# Check logs
kubectl logs deployment/auth-service -n instaclone

# Check if MySQL is ready
kubectl get pods -l app=mysql -n instaclone

# Describe pod for events
kubectl describe pod <pod-name> -n instaclone
```

### Ingress not working

**Cause**: Ingress controller not installed or misconfigured

**Fix**:
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl describe ingress instaclone-ingress-simple -n instaclone

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

## 💡 Tips

1. **Use version tags** - Don't rely on "latest" in production
2. **Set resource limits** - Prevent pods from consuming too much
3. **Enable monitoring** - Know when something goes wrong
4. **Backup database** - Regular MySQL backups
5. **Test in staging** - Always test before production
6. **Document changes** - Keep deployment notes
7. **Use GitOps** - ArgoCD for production deployments

## 🤝 Support

- Check documentation in `k8s/*.md` files
- View pod logs: `kubectl logs -f deployment/<service> -n instaclone`
- Check events: `kubectl get events -n instaclone --sort-by='.lastTimestamp'`
- Describe resources: `kubectl describe pod <pod-name> -n instaclone`

---

**Ready to deploy?** Run: `./deploy-ecr.sh`

# MicroK8s + ArgoCD Complete Setup Guide

## Quick Answer

**YES! Your setup will work with MicroK8s + ArgoCD.**

✅ All Kubernetes manifests are compatible
✅ ArgoCD works perfectly with your current structure
✅ ECR images will pull fine with proper authentication
✅ Path-based ingress routing will work

## What You Need to Do

### Phase 1: Prepare MicroK8s (15 minutes)

```bash
# 1. Enable required addons
microk8s enable dns
microk8s enable hostpath-storage
microk8s enable ingress
microk8s enable metrics-server

# 2. Set up kubectl alias
alias kubectl='microk8s kubectl'

# 3. Verify everything is running
microk8s status
kubectl get pods -A
```

**See**: `k8s/MICROK8S-SETUP.md` for detailed steps

### Phase 2: Install ArgoCD (10 minutes)

```bash
# 1. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Wait for pods
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# 3. Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 4. Access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
```

**See**: `k8s/ARGOCD-SETUP.md` for detailed steps

### Phase 3: Create GitOps Repository (20 minutes)

```bash
# 1. Create new Git repository
mkdir ~/instaclone-gitops
cd ~/instaclone-gitops
git init
git branch -M main

# 2. Copy your manifests (EXCLUDING secrets)
cp -r /path/to/ITkannadigaru-Microservice/app/k8s/base .
rm base/secrets.yaml  # Don't commit secrets!

# 3. Create .gitignore
cat > .gitignore <<EOF
secrets.yaml
*-secrets.yaml
.env
*.bak
EOF

# 4. Create apps directory for ArgoCD
mkdir apps
cp /path/to/ITkannadigaru-Microservice/app/argocd-apps/instaclone-app.yaml apps/

# 5. Update repoURL in apps/instaclone-app.yaml
vim apps/instaclone-app.yaml
# Change: https://github.com/YOUR_USERNAME/instaclone-gitops.git

# 6. Commit and push to GitHub
git add .
git commit -m "Initial commit: InstaClone K8s manifests"
git remote add origin https://github.com/YOUR_USERNAME/instaclone-gitops.git
git push -u origin main
```

### Phase 4: Handle Secrets (Choose One Method)

#### Option A: Manual (Simple - Good for Dev)

```bash
# Create namespace
kubectl create namespace instaclone

# ECR secret
./create-ecr-secret.sh

# Application secrets
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="changeme123" \
  --from-literal=db-password="changeme123" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_AWS_KEY" \
  --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone
```

#### Option B: Sealed Secrets (Recommended - GitOps)

```bash
# Install controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Install CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Create sealed secret
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="changeme123" \
  --from-literal=db-password="changeme123" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --namespace=instaclone \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > ~/instaclone-gitops/base/sealed-secrets.yaml

# Commit to Git (it's encrypted!)
cd ~/instaclone-gitops
git add base/sealed-secrets.yaml
git commit -m "Add sealed secrets"
git push
```

**See**: `k8s/SECRETS-MANAGEMENT.md` for all options

### Phase 5: Deploy with ArgoCD (5 minutes)

#### Method 1: Using ArgoCD CLI

```bash
# Install CLI
brew install argocd  # macOS
# or download from GitHub for Linux

# Login
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure

# Create application
argocd app create instaclone \
  --repo https://github.com/YOUR_USERNAME/instaclone-gitops.git \
  --path base \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace instaclone \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Watch deployment
argocd app get instaclone
argocd app sync instaclone --watch
```

#### Method 2: Using kubectl

```bash
# Apply ArgoCD Application manifest
kubectl apply -f argocd-apps/instaclone-app.yaml

# Watch status
kubectl get application instaclone -n argocd -w
```

#### Method 3: Using ArgoCD UI

1. Open https://localhost:8080
2. Click "+ New App"
3. Fill in:
   - Name: instaclone
   - Project: default
   - Sync Policy: Automatic
   - Repository URL: https://github.com/YOUR_USERNAME/instaclone-gitops.git
   - Path: base
   - Cluster: https://kubernetes.default.svc
   - Namespace: instaclone
4. Click "Create"
5. Click "Sync"

### Phase 6: Access Your Application

```bash
# Add to /etc/hosts
echo "127.0.0.1 instaclone.local" | sudo tee -a /etc/hosts

# Test
curl http://instaclone.local/api/health
curl http://instaclone.local/auth/health
curl http://instaclone.local/users/health

# Open in browser
open http://instaclone.local
```

---

## Complete Architecture

```
Developer Machine                Git Repository             MicroK8s Cluster
      │                               │                           │
      │  git push changes             │                           │
      │──────────────────────────────>│                           │
      │                               │                           │
      │                               │  ArgoCD watches           │
      │                               │<──────────────────────────│
      │                               │                           │
      │                               │  kubectl apply            │
      │                               │──────────────────────────>│
      │                               │                           │
      │                               │                    ┌──────▼──────┐
      │                               │                    │  ArgoCD UI  │
      │                               │                    │ localhost:  │
      │                               │                    │    8080     │
      │                               │                    └──────┬──────┘
      │                               │                           │
      │                               │                    ┌──────▼──────────┐
      │                               │                    │   Deployments   │
      │                               │                    │  - Backend      │
      │                               │                    │  - Auth         │
      │                               │                    │  - User         │
      │                               │                    │  - Frontend     │
      │                               │                    │  - MySQL        │
      │                               │                    └─────────────────┘
      │                               │                           │
      │                               │                    ┌──────▼──────┐
      │                               │                    │   Ingress   │
      │ http://instaclone.local       │                    └──────┬──────┘
      │<──────────────────────────────────────────────────────────┘
```

---

## GitOps Workflow

### Daily Development Workflow

```bash
# 1. Make changes to code
vim backend/src/index.js

# 2. Build and push new Docker image
./build-and-push-ecr.sh 2  # version 2

# 3. Update GitOps repo
cd ~/instaclone-gitops
vim base/kustomization.yaml
# Update image tag from "1" to "2"

# 4. Commit and push
git add base/kustomization.yaml
git commit -m "Update backend to version 2"
git push

# 5. ArgoCD automatically deploys!
# Wait 1-3 minutes or watch:
argocd app get instaclone
```

### Rollback

```bash
# View deployment history
argocd app history instaclone

# Rollback to previous version
argocd app rollback instaclone <revision-number>

# Or just revert Git commit
cd ~/instaclone-gitops
git revert HEAD
git push
```

---

## Files and Documentation

### Kubernetes Manifests
- `k8s/base/` - All your deployment YAMLs (already ECR-configured)
- `argocd-apps/` - ArgoCD Application definitions

### Documentation (Read in Order)
1. **DEPLOYMENT-SUMMARY.md** - Start here for overview
2. **k8s/MICROK8S-SETUP.md** - MicroK8s configuration
3. **k8s/ARGOCD-SETUP.md** - ArgoCD installation and setup
4. **k8s/SECRETS-MANAGEMENT.md** - How to handle secrets
5. **k8s/ECR-DEPLOYMENT.md** - ECR-specific details
6. **k8s/ARCHITECTURE.md** - Deep dive into architecture
7. **k8s/QUICKREF.md** - Command reference
8. **argocd-apps/README.md** - ArgoCD Application usage

---

## What Changes with ArgoCD?

### Before (Manual Deployment)
```bash
kubectl apply -k k8s/base/
# Manual process every time
```

### After (GitOps with ArgoCD)
```bash
git push
# ArgoCD automatically deploys!
# No more kubectl commands needed
```

### Benefits

✅ **Automated** - Push to Git, automatic deployment
✅ **Auditable** - All changes tracked in Git
✅ **Rollback** - Easy to revert via Git
✅ **Declarative** - Git is source of truth
✅ **Visual** - See deployment status in UI
✅ **Self-healing** - Auto-fixes manual changes

---

## ECR Token Management with MicroK8s + ArgoCD

ECR tokens expire after 12 hours. Solutions:

### Option 1: CronJob (Simple)

```bash
# Create CronJob that refreshes ECR secret every 10 hours
# See k8s/ARGOCD-SETUP.md for full YAML
kubectl apply -f ecr-token-refresh-cronjob.yaml
```

### Option 2: Sealed Secrets + CronJob

```bash
# CronJob creates and seals the ECR secret
# See k8s/SECRETS-MANAGEMENT.md for details
```

### Option 3: IRSA (If migrating to EKS later)

No tokens needed! Best option for production on AWS EKS.

---

## Common Issues and Solutions

### Issue: Pods in ImagePullBackOff

**Cause:** ECR secret expired or missing

**Fix:**
```bash
./create-ecr-secret.sh
kubectl rollout restart deployment/backend -n instaclone
```

### Issue: ArgoCD shows "OutOfSync"

**Cause:** Manual changes made to cluster

**Fix:**
```bash
# Let ArgoCD revert to Git state
argocd app sync instaclone

# Or disable auto-sync if you want manual control
```

### Issue: Secrets not working

**Cause:** Secrets not created before ArgoCD deployment

**Fix:**
```bash
# Create secrets manually first
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="changeme" \
  --namespace=instaclone

# Then sync ArgoCD
argocd app sync instaclone
```

### Issue: Ingress not accessible

**Cause:** MicroK8s ingress not enabled or /etc/hosts not configured

**Fix:**
```bash
# Enable ingress
microk8s enable ingress

# Update /etc/hosts
echo "127.0.0.1 instaclone.local argocd.local" | sudo tee -a /etc/hosts
```

---

## Next Steps After Setup

1. ✅ **Monitor deployments** - Watch ArgoCD UI
2. 🔄 **Set up notifications** - Slack/email alerts
3. 🔄 **Add environments** - Dev, staging, prod overlays
4. 🔄 **Implement HPA** - Auto-scaling based on load
5. 🔄 **Add monitoring** - Prometheus + Grafana
6. 🔄 **Set up CI/CD** - GitHub Actions to build images
7. 🔄 **Backup strategy** - MySQL backup CronJob

---

## Summary

Your complete setup includes:

**Infrastructure:**
- ✅ MicroK8s (lightweight Kubernetes)
- ✅ NGINX Ingress Controller
- ✅ ArgoCD (GitOps controller)
- ✅ Sealed Secrets / Manual secrets

**Application:**
- ✅ 4 ECR Docker images
- ✅ Backend, Auth, User, Frontend services
- ✅ MySQL StatefulSet
- ✅ Path-based ingress routing

**GitOps:**
- ✅ Separate gitops repository
- ✅ Automatic deployments via ArgoCD
- ✅ Git as source of truth
- ✅ Visual deployment tracking

**Automation:**
- ✅ ECR token refresh CronJob
- ✅ Auto-sync from Git
- ✅ Self-healing deployments

---

## Quick Start (TL;DR)

```bash
# 1. Prepare MicroK8s
microk8s enable dns hostpath-storage ingress

# 2. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Create GitOps repo
mkdir ~/instaclone-gitops
cp -r k8s/base ~/instaclone-gitops/
rm ~/instaclone-gitops/base/secrets.yaml
cd ~/instaclone-gitops && git init && git push to GitHub

# 4. Create secrets
./create-ecr-secret.sh
kubectl create secret generic instaclone-secrets --from-literal=... -n instaclone

# 5. Deploy with ArgoCD
kubectl apply -f argocd-apps/instaclone-app.yaml

# 6. Access
echo "127.0.0.1 instaclone.local argocd.local" | sudo tee -a /etc/hosts
open http://instaclone.local
open https://localhost:8080  # ArgoCD UI
```

---

**Your setup is ArgoCD-ready!** All manifests are compatible with MicroK8s and ArgoCD. Just follow the phases above and you'll have a production-grade GitOps workflow running locally. 🚀

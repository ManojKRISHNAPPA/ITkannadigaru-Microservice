# ArgoCD Setup Guide for MicroK8s - InstaClone

## Overview

This guide shows you how to set up **ArgoCD** on MicroK8s to deploy your InstaClone application using **GitOps**.

**What is GitOps?**
- Your Kubernetes manifests live in a Git repository
- ArgoCD watches the Git repo
- When you push changes to Git, ArgoCD automatically deploys them
- No more manual `kubectl apply`!

## Prerequisites

1. MicroK8s installed and running
2. Required addons enabled (see MICROK8S-SETUP.md)
3. Git repository ready (we'll create the structure)
4. kubectl configured (alias for microk8s kubectl)

## Architecture: Current Setup + ArgoCD

```
Developer                    Git Repository              MicroK8s Cluster
   │                              │                            │
   │  git push                    │                            │
   │─────────────────────────────>│                            │
   │                              │                            │
   │                              │  ArgoCD watches            │
   │                              │<───────────────────────────│
   │                              │                            │
   │                              │  Sync changes              │
   │                              │───────────────────────────>│
   │                              │                            │
   │                              │                    ┌───────▼────────┐
   │                              │                    │  Deployments   │
   │                              │                    │  - Backend     │
   │                              │                    │  - Auth        │
   │                              │                    │  - User        │
   │                              │                    │  - Frontend    │
   │                              │                    │  - MySQL       │
   │                              │                    └────────────────┘
```

## Step 1: Install ArgoCD on MicroK8s

### Install ArgoCD

```bash
# Create namespace
microk8s kubectl create namespace argocd

# Install ArgoCD
microk8s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
microk8s kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

### Verify Installation

```bash
# Check pods
microk8s kubectl get pods -n argocd

# Expected output: All pods should be Running
# - argocd-server
# - argocd-repo-server
# - argocd-application-controller
# - argocd-dex-server
# - argocd-redis
```

### Get ArgoCD Admin Password

```bash
# Get initial admin password
ARGOCD_PASSWORD=$(microk8s kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"

# Save this password!
```

## Step 2: Access ArgoCD UI

### Option A: Port Forward (Easiest for MicroK8s)

```bash
# Forward port to localhost
microk8s kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access in browser:
# https://localhost:8080
# Username: admin
# Password: (from previous step)
```

**Note**: Accept the self-signed certificate warning in your browser.

### Option B: Expose via Ingress (Better for permanent access)

```bash
cat > argocd-ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  rules:
  - host: argocd.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
EOF

microk8s kubectl apply -f argocd-ingress.yaml

# Add to /etc/hosts
echo "127.0.0.1 argocd.local" | sudo tee -a /etc/hosts

# Access at: https://argocd.local
```

### Option C: Install ArgoCD CLI (Optional but recommended)

```bash
# Linux
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# macOS
brew install argocd

# Login via CLI
argocd login localhost:8080 \
  --username admin \
  --password $ARGOCD_PASSWORD \
  --insecure
```

## Step 3: Prepare GitOps Repository Structure

You need to create a **separate Git repository** for GitOps. Here's the recommended structure:

```
instaclone-gitops/              # New repository
├── README.md
├── apps/                        # ArgoCD Application definitions
│   ├── instaclone-app.yaml     # Main application
│   ├── backend.yaml             # Individual apps (optional)
│   ├── auth-service.yaml
│   ├── user-service.yaml
│   └── frontend.yaml
├── base/                        # Base K8s manifests (copy from current repo)
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── backend-deployment.yaml
│   ├── auth-service-deployment.yaml
│   ├── user-service-deployment.yaml
│   ├── frontend-deployment.yaml
│   ├── mysql-statefulset.yaml
│   └── ingress.yaml
└── overlays/                    # Environment-specific configs
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

**Important**:
- ❌ **DO NOT** commit `secrets.yaml` to Git
- ✅ Create secrets manually in the cluster first
- ✅ Or use **Sealed Secrets** / **External Secrets Operator** (recommended)

### Create GitOps Repository

```bash
# Create new directory
mkdir -p ~/instaclone-gitops
cd ~/instaclone-gitops

# Initialize Git
git init
git branch -M main

# Copy your manifests (excluding secrets)
cp -r /path/to/ITkannadigaru-Microservice/app/k8s/base .

# Remove secrets file (will be managed separately)
rm base/secrets.yaml

# Create apps directory
mkdir -p apps
```

## Step 4: Create ArgoCD Application Manifest

Create the main ArgoCD Application that manages your InstaClone deployment:

```bash
cat > apps/instaclone-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: instaclone
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  # Project (use 'default' or create custom project)
  project: default

  # Source - Your GitOps repository
  source:
    repoURL: https://github.com/YOUR_USERNAME/instaclone-gitops.git
    targetRevision: main
    path: base  # Path to kustomization

  # Destination - Where to deploy
  destination:
    server: https://kubernetes.default.svc
    namespace: instaclone

  # Sync policy
  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Auto-sync if manual changes detected
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true  # Auto-create namespace

  # Health check
  ignoreDifferences: []
EOF
```

### Update with Your Git Repository

Edit `apps/instaclone-app.yaml` and replace:
- `YOUR_USERNAME` with your GitHub username
- `repoURL` with your actual GitOps repository URL

## Step 5: Handle Secrets with ArgoCD

Since secrets can't be in Git, you have 3 options:

### Option 1: Manual Secret Creation (Simple)

Create secrets manually before deploying with ArgoCD:

```bash
# ECR Secret
./create-ecr-secret.sh

# Application secrets
microk8s kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="YOUR_PASSWORD" \
  --from-literal=db-password="YOUR_PASSWORD" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_AWS_KEY" \
  --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone
```

### Option 2: Sealed Secrets (Recommended)

Encrypt secrets so they can be safely stored in Git:

```bash
# Install Sealed Secrets controller
microk8s kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Install kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Create sealed secret
microk8s kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="YOUR_PASSWORD" \
  --from-literal=db-password="YOUR_PASSWORD" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > base/sealed-secrets.yaml

# Now you can commit sealed-secrets.yaml to Git!
git add base/sealed-secrets.yaml
```

### Option 3: External Secrets Operator (Production)

For AWS Secrets Manager, Vault, etc. (more advanced setup).

## Step 6: Push GitOps Repo to GitHub

```bash
cd ~/instaclone-gitops

# Create .gitignore
cat > .gitignore <<EOF
secrets.yaml
*-secrets.yaml
*.bak
.env
EOF

# Add all files
git add .
git commit -m "Initial commit: InstaClone K8s manifests"

# Create GitHub repo and push
# 1. Go to GitHub and create 'instaclone-gitops' repository
# 2. Push:
git remote add origin https://github.com/YOUR_USERNAME/instaclone-gitops.git
git push -u origin main
```

## Step 7: Deploy with ArgoCD

### Method 1: Using ArgoCD CLI

```bash
# Create application
argocd app create instaclone \
  --repo https://github.com/YOUR_USERNAME/instaclone-gitops.git \
  --path base \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace instaclone \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# View status
argocd app get instaclone

# Sync manually (if automated sync is not enabled)
argocd app sync instaclone

# Watch sync progress
argocd app sync instaclone --watch
```

### Method 2: Using kubectl (Apply Application Manifest)

```bash
# Apply the ArgoCD Application
microk8s kubectl apply -f apps/instaclone-app.yaml

# Check application status
microk8s kubectl get applications -n argocd

# Describe for details
microk8s kubectl describe application instaclone -n argocd
```

### Method 3: Using ArgoCD UI

1. Open ArgoCD UI (https://localhost:8080 or https://argocd.local)
2. Login with admin credentials
3. Click **"+ New App"**
4. Fill in:
   - **Application Name**: instaclone
   - **Project**: default
   - **Sync Policy**: Automatic
   - **Repository URL**: https://github.com/YOUR_USERNAME/instaclone-gitops.git
   - **Path**: base
   - **Cluster**: https://kubernetes.default.svc
   - **Namespace**: instaclone
5. Click **"Create"**
6. Click **"Sync"** to deploy

## Step 8: Verify Deployment

### Check ArgoCD Status

```bash
# Via CLI
argocd app get instaclone

# Via kubectl
microk8s kubectl get application instaclone -n argocd

# Check sync status
microk8s kubectl describe application instaclone -n argocd
```

### Check Kubernetes Resources

```bash
# Check pods
microk8s kubectl get pods -n instaclone

# Check services
microk8s kubectl get svc -n instaclone

# Check ingress
microk8s kubectl get ingress -n instaclone
```

### View in ArgoCD UI

The UI shows:
- 🟢 **Green** = Synced and Healthy
- 🟡 **Yellow** = Out of Sync
- 🔴 **Red** = Unhealthy

You'll see a visual graph of all resources!

## How GitOps Works Now

### Making Changes

```bash
cd ~/instaclone-gitops

# Edit a deployment (e.g., change replicas)
vim base/backend-deployment.yaml

# Commit and push
git add .
git commit -m "Scale backend to 3 replicas"
git push

# ArgoCD automatically detects and applies changes!
# Wait 1-3 minutes or sync manually:
argocd app sync instaclone
```

### Updating Image Versions

```bash
# Edit kustomization.yaml
vim base/kustomization.yaml

# Change image tags:
images:
  - name: 156299069385.dkr.ecr.us-west-2.amazonaws.com/itkannadigaru/backend-service
    newTag: "2"  # Update version

# Commit and push
git add base/kustomization.yaml
git commit -m "Update backend to version 2"
git push

# ArgoCD will deploy the new version automatically
```

## ECR Token Refresh with ArgoCD

Since ECR tokens expire after 12 hours, you need to automate token refresh:

### Create Kubernetes CronJob

```bash
cat > ecr-token-refresh-cronjob.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ecr-token-refresher
  namespace: instaclone
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ecr-token-refresher
  namespace: instaclone
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ecr-token-refresher
  namespace: instaclone
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ecr-token-refresher
subjects:
- kind: ServiceAccount
  name: ecr-token-refresher
  namespace: instaclone
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-token-refresh
  namespace: instaclone
spec:
  schedule: "0 */10 * * *"  # Every 10 hours
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: ecr-token-refresher
          containers:
          - name: refresh-token
            image: amazon/aws-cli:latest
            command:
            - /bin/bash
            - -c
            - |
              # Get ECR token
              TOKEN=\$(aws ecr get-login-password --region us-west-2)

              # Delete old secret
              kubectl delete secret ecr-registry-secret -n instaclone || true

              # Create new secret
              kubectl create secret docker-registry ecr-registry-secret \
                --docker-server=156299069385.dkr.ecr.us-west-2.amazonaws.com \
                --docker-username=AWS \
                --docker-password="\${TOKEN}" \
                --namespace=instaclone
            env:
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: aws-credentials
                  key: access-key-id
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: aws-credentials
                  key: secret-access-key
          restartPolicy: OnFailure
EOF

# Create AWS credentials secret first
microk8s kubectl create secret generic aws-credentials \
  --from-literal=access-key-id="YOUR_AWS_KEY" \
  --from-literal=secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone

# Apply CronJob
microk8s kubectl apply -f ecr-token-refresh-cronjob.yaml
```

## Monitoring and Troubleshooting

### View Logs in ArgoCD

```bash
# Application logs
argocd app logs instaclone

# Specific pod logs via kubectl
microk8s kubectl logs -f deployment/backend -n instaclone
```

### Sync Issues

```bash
# Force sync
argocd app sync instaclone --force

# Refresh (re-check Git repo)
argocd app refresh instaclone

# View sync status
argocd app get instaclone --show-operation
```

### Rollback

```bash
# View history
argocd app history instaclone

# Rollback to specific revision
argocd app rollback instaclone <revision-number>
```

### Delete and Recreate

```bash
# Delete application (keeps resources)
argocd app delete instaclone --cascade=false

# Delete application and resources
argocd app delete instaclone
```

## ArgoCD Best Practices

1. **Use separate GitOps repo** - Don't mix application code with K8s manifests
2. **Encrypted secrets** - Use Sealed Secrets or External Secrets
3. **Auto-sync with caution** - Test in dev first
4. **Use Projects** - Organize apps by team/environment
5. **Health checks** - Define custom health checks if needed
6. **Notifications** - Set up Slack/email notifications for sync failures
7. **RBAC** - Restrict who can sync to production

## Summary

Your setup now has:

✅ **MicroK8s** - Lightweight Kubernetes
✅ **ArgoCD** - GitOps controller
✅ **ECR Integration** - Pulls images from AWS ECR
✅ **Path-based Ingress** - Routes traffic correctly
✅ **Automated Deployments** - Push to Git → Auto-deploy
✅ **Auto-healing** - ArgoCD reverts manual changes

## Next Steps

1. ✅ Set up GitOps repository structure
2. ✅ Create secrets (manually or with Sealed Secrets)
3. ✅ Push manifests to Git
4. ✅ Create ArgoCD Application
5. ✅ Set up ECR token refresh CronJob
6. 🔄 Configure Slack/email notifications
7. 🔄 Set up separate dev/staging/prod environments
8. 🔄 Add monitoring (Prometheus/Grafana)

Your InstaClone app is now GitOps-ready! 🎉

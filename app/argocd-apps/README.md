# InstaClone - ArgoCD Applications

This directory contains ArgoCD Application manifests for GitOps deployment.

## Files

- **instaclone-app.yaml** - Main application (single environment)
- **instaclone-project.yaml** - ArgoCD Project with RBAC
- **instaclone-appset.yaml** - ApplicationSet for multi-environment deployment

## Usage

### Single Environment Deployment

Deploy just one environment (dev, staging, or production):

```bash
# Update the repoURL in instaclone-app.yaml first
vim instaclone-app.yaml

# Apply
kubectl apply -f instaclone-app.yaml

# Check status
kubectl get application instaclone -n argocd
```

### Multi-Environment Deployment

Deploy to multiple environments (dev, staging, prod) automatically:

```bash
# Create project first
kubectl apply -f instaclone-project.yaml

# Deploy ApplicationSet
kubectl apply -f instaclone-appset.yaml

# This creates 3 applications:
# - instaclone-dev
# - instaclone-staging
# - instaclone-prod

# Check all applications
kubectl get applications -n argocd
```

## Prerequisites

1. **ArgoCD installed** on your cluster
2. **GitOps repository** created with your K8s manifests
3. **Secrets created** manually (ECR secret + application secrets)
4. **Update repoURL** in the YAML files with your Git repository

## Before Applying

Update these values in all YAML files:

```yaml
# Replace with your actual repository
repoURL: https://github.com/YOUR_USERNAME/instaclone-gitops.git
```

## GitOps Repository Structure

Your GitOps repo should look like:

```
instaclone-gitops/
├── base/                    # Base manifests (no secrets.yaml)
│   ├── kustomization.yaml
│   ├── backend-deployment.yaml
│   ├── auth-service-deployment.yaml
│   ├── user-service-deployment.yaml
│   ├── frontend-deployment.yaml
│   ├── mysql-statefulset.yaml
│   ├── configmap.yaml
│   └── ingress.yaml
└── overlays/                # Environment-specific
    ├── dev/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

## Managing Secrets

Secrets are NOT stored in Git. Options:

### Option 1: Manual (Simple)

Create secrets directly in cluster before deploying with ArgoCD:

```bash
# ECR secret
./create-ecr-secret.sh

# Application secrets
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="changeme" \
  --from-literal=db-password="changeme" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_KEY" \
  --from-literal=aws-secret-access-key="YOUR_SECRET" \
  --namespace=instaclone
```

### Option 2: Sealed Secrets (Recommended)

Encrypt secrets to store in Git safely:

```bash
# Install sealed-secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Install kubeseal CLI
# ... (see ARGOCD-SETUP.md)

# Create sealed secret
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="changeme" \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > base/sealed-secrets.yaml

# Commit to Git
git add base/sealed-secrets.yaml
git commit -m "Add sealed secrets"
git push
```

### Option 3: External Secrets Operator (Production)

Use AWS Secrets Manager, Vault, etc.

## Deployment Flow

```
Developer
   │
   │ git push
   ▼
GitHub Repository (instaclone-gitops)
   │
   │ ArgoCD watches
   ▼
ArgoCD Controller
   │
   │ kubectl apply
   ▼
Kubernetes Cluster (MicroK8s)
   │
   ▼
Pods Running
```

## Viewing in ArgoCD UI

After applying the manifests:

1. Access ArgoCD UI: https://localhost:8080 or https://argocd.local
2. You'll see your application(s)
3. Click on the app to see the resource tree
4. Green = Synced and Healthy
5. Click "Sync" to manually deploy

## Troubleshooting

### Application stuck in "Progressing"

```bash
# Check application details
kubectl describe application instaclone -n argocd

# Check ArgoCD logs
kubectl logs -f deployment/argocd-application-controller -n argocd
```

### Sync fails with "permission denied"

Check if the Git repository is accessible:

```bash
# For private repos, add SSH key or Git credentials
argocd repo add https://github.com/YOUR_USERNAME/instaclone-gitops.git \
  --username YOUR_USERNAME \
  --password YOUR_GITHUB_TOKEN
```

### Resources not appearing

Ensure your kustomization.yaml in the GitOps repo has all resources listed:

```yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - backend-deployment.yaml
  - auth-service-deployment.yaml
  - user-service-deployment.yaml
  - frontend-deployment.yaml
  - mysql-statefulset.yaml
  - ingress.yaml
```

## Next Steps

1. Update `repoURL` with your GitOps repository
2. Push your manifests to the GitOps repo
3. Create secrets in the cluster
4. Apply ArgoCD Application: `kubectl apply -f instaclone-app.yaml`
5. Watch it sync: `kubectl get application instaclone -n argocd -w`
6. Access ArgoCD UI to see the visual graph

## Learn More

- ArgoCD Docs: https://argo-cd.readthedocs.io/
- Kustomize: https://kustomize.io/
- Sealed Secrets: https://github.com/bitnami-labs/sealed-secrets

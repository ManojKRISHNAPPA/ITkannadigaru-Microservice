# Secrets Management with ArgoCD - InstaClone

## The Problem

**Secrets cannot be stored in Git in plain text** for security reasons. However, ArgoCD syncs from Git repositories. How do we handle secrets?

## Three Solutions

1. **Manual Secret Creation** (Simple, good for dev)
2. **Sealed Secrets** (Recommended, encrypted secrets in Git)
3. **External Secrets Operator** (Best for production, integrates with AWS Secrets Manager/Vault)

---

## Solution 1: Manual Secret Creation (Simple)

Create secrets manually in the cluster **before** deploying with ArgoCD.

### Step 1: Create Secrets

```bash
# Create namespace first
kubectl create namespace instaclone

# ECR pull secret
./create-ecr-secret.sh

# Or manually:
ECR_TOKEN=$(aws ecr get-login-password --region us-west-2)
kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=156299069385.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --namespace=instaclone

# Application secrets
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="YOUR_SECURE_PASSWORD" \
  --from-literal=db-password="YOUR_SECURE_PASSWORD" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_AWS_KEY" \
  --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone
```

### Step 2: Remove secrets.yaml from GitOps Repo

```bash
cd ~/instaclone-gitops
rm base/secrets.yaml  # Don't track in Git

# Add to .gitignore
echo "secrets.yaml" >> .gitignore
echo "*-secrets.yaml" >> .gitignore
```

### Step 3: Configure ArgoCD to Ignore Secret Diffs

Update your ArgoCD Application:

```yaml
spec:
  ignoreDifferences:
    - group: ""
      kind: Secret
      name: ecr-registry-secret
      jsonPointers:
        - /data

    - group: ""
      kind: Secret
      name: instaclone-secrets
      jsonPointers:
        - /data
```

### Pros & Cons

**Pros:**
- ✅ Simple to understand
- ✅ No additional tools needed
- ✅ Works immediately

**Cons:**
- ❌ Manual process (not automated)
- ❌ No audit trail
- ❌ Secrets not versioned
- ❌ Hard to rotate secrets across environments

**Best for:** Development, testing, small teams

---

## Solution 2: Sealed Secrets (Recommended)

Encrypt secrets so they can be safely stored in Git. Only the cluster can decrypt them.

### How It Works

```
Developer                Git Repository           Kubernetes
   │                           │                      │
   │  kubectl create secret    │                      │
   │  (plaintext)               │                      │
   ├──────────┐                 │                      │
   │          │                 │                      │
   │  kubeseal (encrypt)        │                      │
   │          │                 │                      │
   │  SealedSecret.yaml         │                      │
   │  (encrypted, safe)         │                      │
   │                            │                      │
   │  git push                  │                      │
   └───────────────────────────>│                      │
                                │                      │
                                │  ArgoCD sync         │
                                │─────────────────────>│
                                │                      │
                                │            SealedSecret Controller
                                │            decrypts & creates Secret
                                │                      │
                                                       ▼
                                                  Plain Secret
```

### Step 1: Install Sealed Secrets Controller

```bash
# Install controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Wait for it to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/sealed-secrets-controller -n kube-system

# Verify
kubectl get pods -n kube-system | grep sealed-secrets
```

### Step 2: Install kubeseal CLI

```bash
# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# macOS
brew install kubeseal

# Verify
kubeseal --version
```

### Step 3: Create Sealed Secrets

```bash
cd ~/instaclone-gitops/base

# Create sealed secret for application secrets
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="YOUR_SECURE_PASSWORD" \
  --from-literal=db-password="YOUR_SECURE_PASSWORD" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_AWS_KEY" \
  --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > sealed-secrets.yaml

# This creates sealed-secrets.yaml with encrypted data
cat sealed-secrets.yaml
```

### Step 4: Update Kustomization

Add sealed-secrets.yaml to kustomization:

```yaml
# base/kustomization.yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - sealed-secrets.yaml  # Add this
  - mysql-statefulset.yaml
  - backend-deployment.yaml
  - auth-service-deployment.yaml
  - user-service-deployment.yaml
  - frontend-deployment.yaml
  - ingress.yaml
```

### Step 5: Commit to Git

```bash
git add base/sealed-secrets.yaml
git add base/kustomization.yaml
git commit -m "Add sealed secrets"
git push

# ArgoCD will now sync and the controller will decrypt!
```

### Handling ECR Secret (Expires Every 12 Hours)

For ECR, create a CronJob that generates and seals the secret:

```bash
cat > sealed-ecr-cronjob.yaml <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sealed-ecr-token-refresh
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
              # Install kubeseal
              wget -q https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
              tar -xzf kubeseal-0.24.0-linux-amd64.tar.gz

              # Get ECR token
              TOKEN=\$(aws ecr get-login-password --region us-west-2)

              # Create sealed secret
              kubectl create secret docker-registry ecr-registry-secret \
                --docker-server=156299069385.dkr.ecr.us-west-2.amazonaws.com \
                --docker-username=AWS \
                --docker-password="\${TOKEN}" \
                --namespace=instaclone \
                --dry-run=client -o yaml | \
                ./kubeseal -o yaml | \
                kubectl apply -f -
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

kubectl apply -f sealed-ecr-cronjob.yaml
```

### Rotating Secrets

```bash
# Update the secret value
kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="NEW_PASSWORD" \
  --namespace=instaclone \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > sealed-secrets.yaml

# Commit and push
git add sealed-secrets.yaml
git commit -m "Rotate MySQL password"
git push

# ArgoCD syncs, controller decrypts, pods restart
```

### Pros & Cons

**Pros:**
- ✅ Secrets stored in Git (encrypted)
- ✅ Audit trail (Git history)
- ✅ Version controlled
- ✅ GitOps compatible
- ✅ Automatic deployment

**Cons:**
- ❌ Requires sealed-secrets controller
- ❌ Slightly more complex
- ❌ Controller has the decryption key (cluster-scoped)

**Best for:** Most production use cases, GitOps workflows

---

## Solution 3: External Secrets Operator (Production)

Fetch secrets from external systems (AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager, Azure Key Vault).

### How It Works

```
Kubernetes                AWS Secrets Manager
    │                            │
    │  ExternalSecret CR         │
    │  (reference to secret)     │
    │                            │
    │  External Secrets          │
    │  Operator watches          │
    │                            │
    │  Fetch secret              │
    │───────────────────────────>│
    │                            │
    │  Return secret value       │
    │<───────────────────────────│
    │                            │
    │  Create K8s Secret         │
    │                            │
    ▼                            │
Plain Secret
(in cluster)
```

### Step 1: Install External Secrets Operator

```bash
# Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace

# Verify
kubectl get pods -n external-secrets-system
```

### Step 2: Create AWS Secrets in AWS Secrets Manager

```bash
# Create secrets in AWS
aws secretsmanager create-secret \
  --name instaclone/mysql-password \
  --secret-string "YOUR_SECURE_PASSWORD" \
  --region us-west-2

aws secretsmanager create-secret \
  --name instaclone/jwt-secret \
  --secret-string "$(openssl rand -base64 32)" \
  --region us-west-2

aws secretsmanager create-secret \
  --name instaclone/aws-credentials \
  --secret-string '{"accessKeyId":"YOUR_KEY","secretAccessKey":"YOUR_SECRET"}' \
  --region us-west-2
```

### Step 3: Create SecretStore

```bash
cat > base/secret-store.yaml <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: instaclone
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        # Use IRSA (IAM Roles for Service Accounts) on EKS
        # Or use static credentials (not recommended)
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-credentials
            key: secret-access-key
EOF
```

### Step 4: Create ExternalSecret

```bash
cat > base/external-secret.yaml <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: instaclone-secrets
  namespace: instaclone
spec:
  refreshInterval: 1h  # Refresh every hour
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore

  target:
    name: instaclone-secrets
    creationPolicy: Owner

  data:
    - secretKey: mysql-root-password
      remoteRef:
        key: instaclone/mysql-password

    - secretKey: db-password
      remoteRef:
        key: instaclone/mysql-password

    - secretKey: jwt-secret
      remoteRef:
        key: instaclone/jwt-secret

    - secretKey: aws-access-key-id
      remoteRef:
        key: instaclone/aws-credentials
        property: accessKeyId

    - secretKey: aws-secret-access-key
      remoteRef:
        key: instaclone/aws-credentials
        property: secretAccessKey
EOF
```

### Step 5: Update Kustomization

```yaml
# base/kustomization.yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - secret-store.yaml      # Add this
  - external-secret.yaml   # Add this
  - mysql-statefulset.yaml
  - backend-deployment.yaml
  # ... rest of resources
```

### Step 6: Commit to Git

```bash
git add base/secret-store.yaml base/external-secret.yaml
git commit -m "Add external secrets configuration"
git push

# ArgoCD syncs, External Secrets Operator fetches from AWS!
```

### Pros & Cons

**Pros:**
- ✅ Centralized secret management
- ✅ Automatic rotation
- ✅ Audit trail (in AWS CloudTrail)
- ✅ Fine-grained IAM permissions
- ✅ Secrets never leave AWS (until used)
- ✅ GitOps compatible

**Cons:**
- ❌ More complex setup
- ❌ Requires external service (AWS Secrets Manager, Vault, etc.)
- ❌ Additional cost (AWS Secrets Manager charges per secret)
- ❌ Dependency on external service

**Best for:** Large production environments, enterprise, regulated industries

---

## Comparison Table

| Feature | Manual | Sealed Secrets | External Secrets |
|---------|--------|----------------|------------------|
| Complexity | Low | Medium | High |
| GitOps | ❌ | ✅ | ✅ |
| Audit Trail | ❌ | ✅ (Git) | ✅ (AWS/Vault) |
| Auto Rotation | ❌ | ⚠️ Manual | ✅ |
| Version Control | ❌ | ✅ | ✅ |
| Cost | Free | Free | Paid (AWS) |
| Best For | Dev | Most cases | Enterprise |

---

## Recommendation by Environment

### Development
**Use Manual Secret Creation**
- Simple and fast
- No additional tools
- Easy debugging

### Staging/Production (GitOps)
**Use Sealed Secrets**
- GitOps workflow
- Version controlled
- Audit trail
- No external dependencies

### Enterprise Production
**Use External Secrets Operator**
- Centralized management
- Automatic rotation
- Compliance requirements
- Multi-cluster support

---

## ECR Token Special Case

ECR tokens expire after 12 hours, so they need special handling:

### Option 1: CronJob (Any method)
Run a CronJob every 10 hours to refresh the ECR secret

### Option 2: IAM Roles for Service Accounts (IRSA) on EKS
Best option - no token needed at all!

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ecr-access
  namespace: instaclone
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::156299069385:role/EKSECRAccessRole

# In deployments, use:
spec:
  serviceAccountName: ecr-access
  # No imagePullSecrets needed!
```

---

## Next Steps

1. Choose your secret management approach
2. Set up the chosen solution
3. Remove plain secrets from Git
4. Configure ArgoCD Application
5. Test deployment
6. Set up secret rotation if needed

Your secrets are now managed securely with ArgoCD! 🔐

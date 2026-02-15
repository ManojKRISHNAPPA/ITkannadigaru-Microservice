# MicroK8s Setup Guide for InstaClone

## Prerequisites Check

Before deploying, ensure MicroK8s is properly configured.

### 1. Check MicroK8s Status

```bash
microk8s status
```

### 2. Enable Required Addons

```bash
# DNS (required)
microk8s enable dns

# Storage (required for MySQL)
microk8s enable hostpath-storage

# Ingress Controller (required for external access)
microk8s enable ingress

# Optional but recommended
microk8s enable metrics-server
microk8s enable registry  # For local image registry

# Check status
microk8s status
```

### 3. Set Up kubectl Alias

Make your life easier:

```bash
# Add to ~/.bashrc or ~/.zshrc
alias kubectl='microk8s kubectl'

# Or use snap alias
sudo snap alias microk8s.kubectl kubectl

# Verify
kubectl version --short
```

### 4. Verify Storage Class

```bash
kubectl get storageclass
```

Expected output:
```
NAME                          PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE
microk8s-hostpath (default)   microk8s.io/hostpath   Delete          Immediate
```

### 5. Check Ingress Controller

```bash
kubectl get pods -n ingress
```

Expected output:
```
NAME                                      READY   STATUS    RESTARTS   AGE
nginx-ingress-microk8s-controller-xxxxx   1/1     Running   0          5m
```

## MicroK8s-Specific Configuration

### Update Storage Class in MySQL StatefulSet

MicroK8s uses `microk8s-hostpath` storage class. Update the MySQL StatefulSet:

**Option 1: Edit the file**

Edit `k8s/base/mysql-statefulset.yaml` and add:

```yaml
volumeClaimTemplates:
  - metadata:
      name: mysql-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: microk8s-hostpath  # Add this line
      resources:
        requests:
          storage: 10Gi
```

**Option 2: Use kubectl patch after deployment**

```bash
# Deploy first, then patch
kubectl patch statefulset mysql -n instaclone \
  -p '{"spec":{"volumeClaimTemplates":[{"spec":{"storageClassName":"microk8s-hostpath"}}]}}'
```

### Update Ingress for MicroK8s

MicroK8s ingress uses different annotations. Create a MicroK8s-specific ingress:

```bash
cat > k8s/overlays/microk8s/ingress-patch.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: instaclone-ingress-simple
  annotations:
    # MicroK8s specific
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: instaclone.local
    http:
      paths:
      - path: /auth
        pathType: Prefix
        backend:
          service:
            name: auth-service
            port:
              number: 3001
      - path: /users
        pathType: Prefix
        backend:
          service:
            name: user-service
            port:
              number: 3002
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend
            port:
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
EOF
```

## Deploy to MicroK8s

### Step 1: Create ECR Secret

```bash
# Use microk8s kubectl
./create-ecr-secret.sh
```

Or manually:

```bash
ECR_TOKEN=$(aws ecr get-login-password --region us-west-2)

microk8s kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=156299069385.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --namespace=instaclone
```

### Step 2: Create Application Secrets

```bash
microk8s kubectl create secret generic instaclone-secrets \
  --from-literal=mysql-root-password="YOUR_PASSWORD" \
  --from-literal=db-password="YOUR_PASSWORD" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=aws-access-key-id="YOUR_AWS_KEY" \
  --from-literal=aws-secret-access-key="YOUR_AWS_SECRET" \
  --namespace=instaclone
```

### Step 3: Deploy Application

```bash
# Create namespace
microk8s kubectl create namespace instaclone

# Deploy with kustomize
microk8s kubectl apply -k k8s/base/
```

### Step 4: Verify Deployment

```bash
# Check pods
microk8s kubectl get pods -n instaclone

# Check services
microk8s kubectl get svc -n instaclone

# Check ingress
microk8s kubectl get ingress -n instaclone
```

## Access Application on MicroK8s

### Get Ingress IP

```bash
microk8s kubectl get ingress -n instaclone
```

MicroK8s ingress typically uses your machine's IP.

### Update /etc/hosts

```bash
# Get your machine IP
hostname -I | awk '{print $1}'

# Add to /etc/hosts
echo "127.0.0.1 instaclone.local" | sudo tee -a /etc/hosts

# Or if MicroK8s is on a different IP
echo "YOUR_MACHINE_IP instaclone.local" | sudo tee -a /etc/hosts
```

### Test Access

```bash
curl http://instaclone.local/api/health
curl http://instaclone.local/auth/health
curl http://instaclone.local/users/health
curl http://instaclone.local/
```

Or open in browser:
```bash
xdg-open http://instaclone.local
# or
open http://instaclone.local
```

## Troubleshooting MicroK8s

### Pods stuck in Pending

```bash
# Check events
microk8s kubectl describe pod <pod-name> -n instaclone

# Common causes:
# 1. Storage not available - Enable hostpath-storage addon
# 2. Insufficient resources - Check with "microk8s status"
```

### Ingress not working

```bash
# Check ingress controller
microk8s kubectl get pods -n ingress

# If not running, enable ingress
microk8s enable ingress

# Check ingress logs
microk8s kubectl logs -n ingress -l name=nginx-ingress-microk8s
```

### ECR Image Pull Issues

```bash
# Verify ECR secret exists
microk8s kubectl get secret ecr-registry-secret -n instaclone

# If expired, recreate
./create-ecr-secret.sh

# Restart deployments
microk8s kubectl rollout restart deployment/auth-service -n instaclone
```

### MySQL PVC Issues

```bash
# Check PVC status
microk8s kubectl get pvc -n instaclone

# Check storage class
microk8s kubectl get storageclass

# If PVC pending, ensure hostpath-storage is enabled
microk8s enable hostpath-storage
```

## MicroK8s Performance Tips

### Resource Limits

MicroK8s runs on a single machine. Consider reducing replica counts:

```bash
# Scale down to 1 replica for dev
microk8s kubectl scale deployment backend --replicas=1 -n instaclone
microk8s kubectl scale deployment auth-service --replicas=1 -n instaclone
microk8s kubectl scale deployment user-service --replicas=1 -n instaclone
microk8s kubectl scale deployment frontend --replicas=1 -n instaclone
```

Or create a dev overlay with lower replicas (see next section).

### Check Resource Usage

```bash
# Node resources
microk8s kubectl top nodes

# Pod resources
microk8s kubectl top pods -n instaclone
```

## Create MicroK8s Overlay

For better resource management, create a MicroK8s-specific overlay:

```bash
mkdir -p k8s/overlays/microk8s

cat > k8s/overlays/microk8s/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

namespace: instaclone

# Reduce replicas for local development
replicas:
  - name: backend
    count: 1
  - name: auth-service
    count: 1
  - name: user-service
    count: 1
  - name: frontend
    count: 1

# Add storage class to MySQL
patchesStrategicMerge:
  - mysql-storage-patch.yaml
EOF

cat > k8s/overlays/microk8s/mysql-storage-patch.yaml <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  volumeClaimTemplates:
  - metadata:
      name: mysql-data
    spec:
      storageClassName: microk8s-hostpath
EOF
```

Deploy with overlay:

```bash
microk8s kubectl apply -k k8s/overlays/microk8s/
```

## Clean Up

```bash
# Delete namespace
microk8s kubectl delete namespace instaclone

# Or use kustomize
microk8s kubectl delete -k k8s/base/

# Disable addons if needed
microk8s disable ingress
microk8s disable metrics-server
```

## Next Steps

Your MicroK8s setup is ready! Now you can:
1. ✅ Deploy your application with `microk8s kubectl apply -k k8s/base/`
2. 🔄 Set up ArgoCD for GitOps (see ARGOCD-SETUP.md)
3. 🔄 Configure automatic ECR token refresh
4. 📊 Set up monitoring with metrics-server

## MicroK8s vs Cloud Kubernetes

| Feature | MicroK8s | Cloud K8s (EKS/GKE/AKS) |
|---------|----------|-------------------------|
| Storage | hostpath-storage | Cloud volumes (EBS, PD, Disk) |
| LoadBalancer | Uses host IP | Cloud LB (ELB, GLB, Azure LB) |
| Scaling | Single node | Multi-node |
| HA | No | Yes |
| Cost | Free | Pay per use |
| Best for | Dev/Test | Production |

## Useful MicroK8s Commands

```bash
# Start/Stop
microk8s start
microk8s stop

# Status
microk8s status
microk8s inspect

# Add nodes (for multi-node)
microk8s add-node

# Access dashboard (if enabled)
microk8s dashboard-proxy

# Reset (DANGER: deletes everything)
microk8s reset
```

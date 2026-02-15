# Architecture Diagram - InstaClone Microservices

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT (Browser)                         │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    INGRESS CONTROLLER (NGINX)                    │
│                     (Path-Based Routing)                         │
└┬────────────────┬────────────────┬────────────────┬─────────────┘
 │                │                │                │
 │ /              │ /api/*         │ /auth/*        │ /users/*
 ▼                ▼                ▼                ▼
┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐
│ Frontend  │  │  Backend  │  │   Auth    │  │   User    │
│  Service  │  │  Service  │  │  Service  │  │  Service  │
│  (Nginx)  │  │ (Node.js) │  │ (Node.js) │  │ (Node.js) │
│   :80     │  │   :8080   │  │   :3001   │  │   :3002   │
│           │  │           │  │           │  │           │
│ Replicas:2│  │ Replicas:2│  │ Replicas:2│  │ Replicas:2│
└───────────┘  └───────────┘  └─────┬─────┘  └─────┬─────┘
                                    │                │
                                    │                │
                    ┌───────────────┴────────────────┘
                    ▼
            ┌───────────────┐
            │     MySQL     │
            │  StatefulSet  │
            │     :3306     │
            │               │
            │  Replicas: 1  │
            │  Volume: 10Gi │
            └───────────────┘

                                    ┌───────────────┐
                                    │   AWS S3      │
                                    │   (Media)     │◄──── User Service
                                    │               │      (Avatar Upload)
                                    └───────────────┘
```

## Service Communication Flow

### 1. User Registration Flow

```
Client
  │
  │ POST /auth/register
  ▼
Ingress (/auth/*)
  │
  ▼
Auth Service :3001
  │
  │ 1. Validate input
  │ 2. Hash password
  │ 3. INSERT INTO users
  ▼
MySQL :3306
  │
  │ user_id, username
  ▼
Auth Service
  │
  │ 201 Created
  ▼
Client
```

### 2. User Login Flow

```
Client
  │
  │ POST /auth/login
  ▼
Ingress (/auth/*)
  │
  ▼
Auth Service :3001
  │
  │ 1. SELECT user by email
  ▼
MySQL :3306
  │
  │ user record
  ▼
Auth Service
  │
  │ 2. bcrypt.compare(password)
  │ 3. jwt.sign(user_data)
  │
  │ 200 OK + JWT token
  ▼
Client (stores token)
```

### 3. Get User Profile Flow

```
Client
  │
  │ GET /users/123
  ▼
Ingress (/users/*)
  │
  ▼
User Service :3002
  │
  │ SELECT user, COUNT followers, COUNT following
  ▼
MySQL :3306
  │
  │ user profile data
  ▼
User Service
  │
  │ 200 OK + JSON
  ▼
Client
```

### 4. Avatar Upload Flow

```
Client
  │
  │ POST /users/123/avatar
  │ Authorization: Bearer <token>
  ▼
Ingress (/users/*)
  │
  ▼
User Service :3002
  │
  │ 1. Validate JWT token
  │ 2. Verify user ownership
  │ 3. Upload to S3
  ▼
AWS S3
  │
  │ S3 URL
  ▼
User Service
  │
  │ 4. UPDATE users SET profile_photo_url
  ▼
MySQL :3306
  │
  │ affected rows
  ▼
User Service
  │
  │ 200 OK + avatar URL
  ▼
Client
```

## Kubernetes Resources Created

```
Namespace: instaclone
├── ConfigMap
│   ├── instaclone-config (DB, AWS, ENV settings)
│   └── mysql-init-script (DB schema + seed data)
│
├── Secrets
│   └── instaclone-secrets
│       ├── mysql-root-password
│       ├── db-password
│       ├── jwt-secret
│       ├── aws-access-key-id
│       └── aws-secret-access-key
│
├── StatefulSet
│   └── mysql (1 replica)
│       └── PersistentVolumeClaim: 10Gi
│
├── Deployments
│   ├── backend (2 replicas)
│   ├── auth-service (2 replicas)
│   ├── user-service (2 replicas)
│   └── frontend (2 replicas)
│
├── Services (ClusterIP)
│   ├── mysql:3306
│   ├── backend:8080
│   ├── auth-service:3001
│   ├── user-service:3002
│   └── frontend:80
│
└── Ingress
    └── instaclone-ingress
        ├── / → frontend:80
        ├── /api/* → backend:8080
        ├── /auth/* → auth-service:3001
        └── /users/* → user-service:3002
```

## Network Policies (Future Enhancement)

```
┌──────────────────────────────────────────────────────┐
│  Network Policy: frontend                            │
│  ────────────────────────────────────────────────    │
│  Ingress: Allow from Ingress Controller              │
│  Egress: Deny (static files only, no external calls) │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  Network Policy: backend                             │
│  ────────────────────────────────────────────────    │
│  Ingress: Allow from Ingress Controller              │
│  Egress: None (stateless service)                    │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  Network Policy: auth-service                        │
│  ────────────────────────────────────────────────    │
│  Ingress: Allow from Ingress Controller              │
│  Egress: Allow to mysql:3306                         │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  Network Policy: user-service                        │
│  ────────────────────────────────────────────────    │
│  Ingress: Allow from Ingress Controller              │
│  Egress: Allow to mysql:3306, AWS S3                 │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  Network Policy: mysql                               │
│  ────────────────────────────────────────────────    │
│  Ingress: Allow from auth-service, user-service      │
│  Egress: Deny all                                    │
└──────────────────────────────────────────────────────┘
```

## DNS Resolution in Kubernetes

When a pod in `auth-service` wants to connect to MySQL:

```
Code: pool = mysql.createPool({ host: "mysql", port: 3306 })
         │
         ▼
1. DNS Lookup: "mysql"
         │
         ▼
2. kube-dns/CoreDNS resolves:
   "mysql" → "mysql.instaclone.svc.cluster.local"
         │
         ▼
3. Returns Service ClusterIP: 10.96.123.45
         │
         ▼
4. kube-proxy routes traffic to one of the Pod IPs:
   10.244.1.5 (mysql-0)
         │
         ▼
5. Connection established to MySQL pod
```

## Scaling Strategy

### Horizontal Pod Autoscaler (HPA) - Future

```yaml
# Example HPA for user-service
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Manual Scaling

```bash
# Scale based on load
kubectl scale deployment user-service --replicas=5

# Scale MySQL (StatefulSet)
# Note: Scaling MySQL requires proper replication setup
kubectl scale statefulset mysql --replicas=3
```

## Resource Allocation

| Service       | CPU Request | CPU Limit | Memory Request | Memory Limit |
|---------------|-------------|-----------|----------------|--------------|
| Frontend      | 50m         | 100m      | 64Mi           | 128Mi        |
| Backend       | 100m        | 200m      | 128Mi          | 256Mi        |
| Auth Service  | 100m        | 200m      | 256Mi          | 512Mi        |
| User Service  | 100m        | 200m      | 256Mi          | 512Mi        |
| MySQL         | 250m        | 500m      | 512Mi          | 1Gi          |

**Total Cluster Requirements** (minimum):
- CPU: 600m (0.6 cores)
- Memory: 1.2Gi

**Recommended for production**:
- CPU: 4+ cores
- Memory: 8Gi+
- Storage: 50Gi+

## Health Check Strategy

All services implement:

1. **Liveness Probe**: Checks if pod is alive
   - If fails → Kubernetes restarts the pod
   - Endpoint: `GET /health`

2. **Readiness Probe**: Checks if pod is ready to serve traffic
   - If fails → Pod removed from Service endpoints
   - Endpoint: `GET /health`

3. **Startup Probe** (optional): Gives slow-starting apps more time
   - Used for MySQL initialization

## Data Persistence

```
MySQL StatefulSet
       │
       ▼
PersistentVolumeClaim (PVC)
       │
       ▼
PersistentVolume (PV)
       │
       ▼
Storage Class (Dynamic Provisioning)
       │
       ▼
Cloud Provider Storage
  ├── AWS EBS
  ├── GCP Persistent Disk
  ├── Azure Disk
  └── Local Path (minikube/kind)
```

## Security Layers

```
1. Network Layer
   └── Ingress TLS/SSL termination
   └── Network Policies (pod-to-pod firewall)

2. Application Layer
   └── JWT Authentication
   └── CORS policies
   └── Input validation

3. Data Layer
   └── Encrypted secrets (at rest)
   └── Password hashing (bcrypt)
   └── SQL injection prevention (parameterized queries)

4. Infrastructure Layer
   └── RBAC (Role-Based Access Control)
   └── Pod Security Standards
   └── Image scanning
   └── Private container registry
```

## Monitoring Stack (Future)

```
┌────────────────────────────────────────────┐
│              Grafana Dashboards            │
└────────────────┬───────────────────────────┘
                 │
┌────────────────▼───────────────────────────┐
│             Prometheus                      │
│  ┌────────────────────────────────────┐    │
│  │ Metrics:                           │    │
│  │  - Pod CPU/Memory usage            │    │
│  │  - HTTP request rate/latency       │    │
│  │  - MySQL query performance         │    │
│  │  - S3 upload success rate          │    │
│  └────────────────────────────────────┘    │
└────────────────┬───────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
   ┌────▼────┐      ┌────▼────┐
   │  kube-  │      │ Service │
   │  state- │      │ Monitors│
   │ metrics │      └─────────┘
   └─────────┘
```

## Logging Stack (Future)

```
Pods (all services)
    │
    │ stdout/stderr
    ▼
Fluentd/Fluent Bit (DaemonSet)
    │
    │ Parse & Forward
    ▼
Elasticsearch
    │
    │ Index & Store
    ▼
Kibana Dashboard
```

## CI/CD Pipeline (Future with ArgoCD)

```
Developer
    │
    │ git push
    ▼
GitHub Repository
    │
    │ webhook
    ▼
CI Pipeline (GitHub Actions/Jenkins)
    │
    ├─► Build Docker images
    ├─► Run tests
    ├─► Security scan
    ├─► Push to Docker Hub
    └─► Update image tag in GitOps repo
         │
         ▼
    ArgoCD detects change
         │
         │ sync
         ▼
    Kubernetes Cluster
         │
         ├─► Rolling update deployments
         ├─► Health checks
         └─► Rollback if failed
```

# IQGeo Platform Deployment

Automated deployment of IQGeo Platform to AWS EKS using GitHub Actions with a self-hosted runner.

## Architecture

```
GitHub Actions (Self-hosted Runner on EC2)
    |
    v
AWS EKS Cluster (IQGEO-POC-Cluster-tf)
    |
    +-- IQGeo Platform (Helm)
    +-- PostgreSQL (RDS)
    +-- Redis (In-cluster)
    +-- EFS Storage
    +-- Ingress NGINX (LoadBalancer)
```

## Prerequisites

- AWS EKS cluster running
- RDS PostgreSQL instance
- EFS file system
- Harbor registry access (for IQGeo images)
- IQGeo license file

## Setup

### 1. Create GitHub Repository

Create a new repository on GitHub (e.g., `iqgeo-deployment`).

### 2. Deploy EC2 Runner

```bash
cd terraform
terraform init
terraform apply -var="github_runner_token=YOUR_TOKEN"
```

### 3. Configure Runner

SSH to the EC2 instance and run:

```bash
sudo /home/runner/scripts/setup-runner.sh https://github.com/YOUR_ORG/iqgeo-deployment YOUR_TOKEN
```

### 4. Create Secrets

Create the required Kubernetes secrets:

```bash
# Harbor registry credentials
kubectl create secret docker-registry harbor-registry-cred \
  --docker-server=harbor.delivery.iqgeo.cloud \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD \
  -n iqgeo

# Database password
kubectl create secret generic iqgeo-db-secret \
  --from-literal=POSTGRES_PASSWORD='YOUR_DB_PASSWORD' \
  -n iqgeo

# IQGeo license
kubectl create secret generic iqgeo-license \
  --from-file=license.key=/path/to/license.key \
  -n iqgeo
```

### 5. Add GitHub Secrets

Add these secrets to your GitHub repository:
- `HARBOR_USERNAME`: Harbor registry username
- `HARBOR_PASSWORD`: Harbor registry password

### 6. Deploy

Push to main branch or trigger workflow manually.

## Directory Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yaml      # GitHub Actions workflow
├── k8s/
│   ├── namespace.yaml       # Kubernetes namespace
│   ├── storage.yaml         # EFS storage class and PVC
│   ├── values.yaml          # Helm values for IQGeo
│   └── secrets.yaml.template
├── terraform/
│   └── main.tf              # EC2 runner infrastructure
├── scripts/
│   └── setup-runner.sh      # Runner setup script
└── charts/                  # Place IQGeo Helm chart here
```

## Manual Deployment

If you need to deploy manually:

```bash
# Configure kubectl
aws eks update-kubeconfig --name IQGEO-POC-Cluster-tf --region us-east-1

# Apply manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/storage.yaml

# Deploy with Helm
helm upgrade --install iqgeo charts/iqgeo-platform-*.tgz \
  -f k8s/values.yaml \
  -n iqgeo --create-namespace
```

## Troubleshooting

Check pod status:
```bash
kubectl get pods -n iqgeo
kubectl describe pod <POD_NAME> -n iqgeo
kubectl logs <POD_NAME> -n iqgeo
```

Check runner status:
```bash
sudo systemctl status github-runner
sudo journalctl -u github-runner -f
```

## Configuration

Update `k8s/values.yaml` for:
- Database connection
- Ingress hostname
- Resource limits
- Redis configuration

## EKS Cluster Details

- Cluster: `IQGEO-POC-Cluster-tf`
- Region: `us-east-1`
- VPC: `vpc-0dc423e7d98597c6e`
- RDS: `vytiertf.cchyjvuq3inp.us-east-1.rds.amazonaws.com`
- EFS: `fs-0f64028caf280776d`


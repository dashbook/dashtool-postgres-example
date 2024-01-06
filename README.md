
# Dashtool example with Postgres

## Setup

### Prerequisites

- docker
- kind
- kubectl
- AWS S3 bucket
- dashtool

### Install and start Kind cluster

```shell
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 32432
    hostPort: 5432
EOF
```

### Install Argo

- wait until argo is installed

```shell
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v<<ARGO_WORKFLOWS_VERSION>>/install.yaml
```

```shell
kubectl patch deployment \
  argo-server \
  --namespace argo \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": [
  "server",
  "--auth-mode=server"
]}]'
```

#### Port-Forwarding

```shell
kubectl -n argo port-forward deployment/argo-server 2746:2746
```

### Create Secrets

#### Postgres

```shell
kubectl create secret generic postgres-secret --from-literal=password=postgres
```

#### AWS

```shell
kubectl create secret generic aws-secret --from-literal=secret_access_key=<SECRET_ACCESS_KEY>
export AWS_SECRET_ACCESS_KEY=<SECRET_ACCESS_KEY>
```

### Start Postgres

- wait until postgres container is running

```shell
kubectl apply -f postgres.yaml
```

### Grant permissons

```shell
kubectl apply -f role.yaml
```

## Extract & Load (EL)

```shell
git checkout bronze
```

### Dashtool build

```shell
dashtool -p sql build
```

### Dashtool workflow

```shell
dashtool -p sql workflow
```

### Create config_maps

```shell
kubectl apply -f argo/config_maps.yaml
```

### Create argo workflow

```shell
argo cron create argo/workflow.yaml
```

### Merge changes into main

```shell
git checkout main
git merge bronze
```

## Transform (T)

```shell
git checkout silver
```

### Dashtool build

```shell
dashtool -p sql build
```

### Dashtool workflow

```shell
dashtool -p sql workflow
```

### Create config_maps

```shell
kubectl apply -f argo/config_maps.yaml
```

### Create argo workflow

```shell
argo cron delete dashtool
argo cron create argo/workflow.yaml
```

### Merge changes into main

```shell
git checkout main
git merge silver
```

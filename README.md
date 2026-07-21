# vkng: Multi-node Kubernetes with GitOps

A local, multi-node Kubernetes cluster running a full GitOps workflow:

- **k3d**: local multi-node cluster (1 control-plane + 2 workers).
- **Terraform**: installs Argo CD and defines a single root `Application` (the App-of-Apps).
- **Argo CD**: syncs the root Application from Git, which in turn creates and syncs the `infrastructure` and `applications` child Applications - and continuously reconciles this repository into the cluster.
- **Helm**: a custom chart for the frontend/backend, and an umbrella chart for MySQL + backups.
- **MySQL (Bitnami)**: stateful database with a scheduled `mysqldump` backup CronJob.

```
                       terraform apply
                              │
          ┌───────────────────┴───────────────────┐
          ▼                                       ▼
helm_release: Argo CD                   argocd_application.root
 (namespace: argocd)                  path: argocd-apps/ (Git)
                                                  │
                                  Argo CD syncs the root Application,
                                  which creates the two child Applications
                                                  │
                              ┌───────────────────┴───────────────────┐
                              ▼                                       ▼
                 Application: infrastructure              Application: applications
                    path: infrastructure/               path: applications/app-chart/
                     namespace: database                       namespace: apps
                              │                                       │
                    ┌─────────┴─────────┐                   ┌─────────┴─────────┐
                    ▼                   ▼                   ▼                   ▼
             MySQL (Bitnami)     backup CronJob       backend (Go)      frontend (nginx)
               + data PVC      mysqldump every 5m    talks to MySQL  proxies /api → backend
                                  + backups PVC
```

**Data flow:** browser → frontend (nginx) → `/api/visits` proxied to backend (Go) → `INSERT`/`COUNT` in MySQL. The visit counter is persisted in the database, so it survives pod restarts.

## Repository layout

```
applications/
  app-chart/        Custom Helm chart deploying backend + frontend
  backend/          Go source + Dockerfile (MySQL-backed API)
  frontend/         nginx static page + reverse-proxy template + Dockerfile
infrastructure/     Umbrella Helm chart: Bitnami MySQL (vendored) + backup CronJob + PVC
argocd-apps/        App-of-Apps chart (renders infrastructure/applications Applications)
terraform/          Argo CD install + namespaces/secrets + the App-of-Apps root Application
```

Argo CD tracks `argocd-apps/` (the App-of-Apps root), `applications/app-chart/`
and `infrastructure/`; the image sources under `applications/backend` and
`applications/frontend` are not part of the sync.

## Prerequisites

All tools are open source and installable via [Homebrew](https://brew.sh):

| Tool             | Version used | Install (macOS)                       |
|------------------|--------------|---------------------------------------|
| colima + docker  | 29.x         | `brew install colima docker`          |
| k3d              | 5.9.x        | `brew install k3d`                    |
| kubectl          | 1.3x         | `brew install kubernetes-cli`         |
| helm             | 3.x / 4.x    | `brew install helm`                   |
| terraform        | 1.5+         | `brew install hashicorp/tap/terraform`|
| git              | any          | `brew install git`                    |

On macOS, [colima](https://github.com/abiosoft/colima) provides the container
runtime. Make sure it is running and its docker context is active:

```bash
colima start
docker context use colima
```

On Linux, Docker Engine already runs natively - just make sure the daemon is
up (`docker info`); no colima step is needed. `scripts/bootstrap.sh` detects
the OS and skips the colima step on Linux automatically.

---

## Quickstart

Steps 1-3 below (cluster creation, image build/import, `terraform apply`) are
automated by `scripts/bootstrap.sh`. It is idempotent - safe to re-run. It runs
interactively and pauses for a `yes` confirmation at the `terraform apply` step.

```bash
./scripts/bootstrap.sh
```

Once it finishes, skip ahead to [step 4](#4-access-the-argo-cd-ui), or keep
reading for the manual step-by-step process.

---

## 1. Create the cluster

```bash
k3d cluster create vkng \
  --servers 1 --agents 2 \
  --image rancher/k3s:v1.35.5-k3s1 \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer"
```

Verify that you see one control-plane and two worker nodes, all `Ready`:

```bash
kubectl config use-context k3d-vkng
kubectl get nodes -o wide
```

## 2. Build and load the application images

The images are built locally and imported into the cluster (no external
registry required). The Deployments use `imagePullPolicy: IfNotPresent`.

```bash
docker build -t vkng/backend:0.1.0 applications/backend
docker build -t vkng/frontend:0.1.0 applications/frontend

k3d image import vkng/backend:0.1.0 vkng/frontend:0.1.0 -c vkng
```

## 3. Deploy everything with Terraform

Terraform installs Argo CD, generates the MySQL password and the Argo CD admin
password, creates the namespaces/secrets, and registers a single root Argo CD
Application (App-of-Apps) pointing at `argocd-apps/`. Defaults in
`variables.tf` already work for this repository as-is; to point at your own
fork or branch, copy `terraform.tfvars.example` to `terraform.tfvars` and edit it.

```bash
cd terraform
terraform init
terraform apply
```

> **GitOps note:** Argo CD pulls manifests from the Git repository, so the
> code must be pushed to a branch Argo can reach. `target_revision` defaults
> to `main`; to test an unmerged PR branch, override it on the CLI (which
> takes precedence over `terraform.tfvars`, if you have one):
>
> ```bash
> terraform apply -var="target_revision=<branch-name>"
> ```
>
> The child Applications inherit this revision automatically (see
> "App-of-Apps" in Design notes) - no manual edits needed to test a branch.

After `apply`, Argo CD reconciles the root Application, which creates and
syncs the two child Applications. Watch them become `Synced` / `Healthy`:

```bash
kubectl -n argocd get applications
kubectl -n database get pods -w    # MySQL comes up first
kubectl -n apps get pods -w        # backend/frontend follow
```

## 4. Access the Argo CD UI

Argo CD is exposed via Ingress at <http://argocd.localhost:8080> - no
port-forward required.

```bash
# admin password (generated by Terraform)
terraform output -raw argocd_admin_password; echo
```

Open <http://argocd.localhost:8080> and log in as `admin`. You should see the
`root`, `infrastructure` and `applications` apps synced and healthy.

> Fallback: if `*.localhost` does not resolve on your system, use
> `kubectl -n argocd port-forward svc/argocd-server 8081:80` and open
> <http://localhost:8081> instead.

## 5. Verify the backup CronJob

The CronJob runs every 5 minutes. Trigger one immediately instead of waiting:

```bash
kubectl -n database create job --from=cronjob/mysql-backup mysql-backup-manual
kubectl -n database logs job/mysql-backup-manual
```

Inspect the backup PVC contents by exec-ing into a throwaway pod that mounts it:

```bash
kubectl -n database apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: backup-inspect
spec:
  restartPolicy: Never
  containers:
    - name: shell
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: backups
          mountPath: /backups
  volumes:
    - name: backups
      persistentVolumeClaim:
        claimName: mysql-backups
EOF

kubectl -n database wait --for=condition=Ready pod/backup-inspect --timeout=120s
kubectl -n database exec backup-inspect -- ls -lh /backups
# expect files like: appdb-20260720-231500.sql

kubectl -n database delete pod backup-inspect
```

## 6. Verify the application end-to-end

The frontend is exposed via Ingress at <http://vkng.localhost:8080> - no
port-forward required.

Open <http://vkng.localhost:8080> and click **Register visit** a few times;
the counter increments (frontend -> backend -> MySQL).

> Fallback: if `*.localhost` does not resolve on your system, use
> `kubectl -n apps port-forward svc/applications-app-chart-frontend 8082:80`
> and open <http://localhost:8082> instead.

Confirm persistence by restarting the backend; the counter is unchanged because
the data lives in MySQL:

```bash
kubectl -n apps rollout restart deploy/applications-app-chart-backend
# refresh the page; the count is preserved
```

## 7. Clean up

```bash
cd terraform && terraform destroy
k3d cluster delete vkng
```

Or run `./scripts/teardown.sh` to do both in one step.

---

## Design notes

- **App-of-Apps.** Terraform creates exactly one Argo CD `Application`
  (`argocd_application.root`, via the `argoproj-labs/argocd` Terraform
  provider) pointing at `argocd-apps/` - a small Helm chart rendering the
  `infrastructure` and `applications` child Applications. Terraform passes
  `repo_url`, `target_revision`, `db_namespace` and `app_namespace` to it as
  Helm parameters, so those stay in sync across root and children instead of
  being duplicated as hardcoded values in Git. Terraform's job ends at
  installing Argo CD and bootstrapping the root Application; everything below
  that is Argo CD reconciling Git.

- **Secrets never touch Git.** Terraform generates random passwords (MySQL,
  Argo CD admin) and writes them into Kubernetes Secrets rather than Git - the
  MySQL password into `mysql-credentials` in both the `database` and `apps`
  namespaces (consumed via `auth.existingSecret` / `secretKeyRef`), and only
  the bcrypt hash of the Argo CD admin password into the Argo CD Helm release.
  A production setup would use Sealed Secrets / SOPS / External Secrets to
  keep encrypted secrets in Git.

- **Bitnami images.** The default Bitnami MySQL images were removed from the
  free Docker Hub tier, so the chart is pinned to the equivalent
  `bitnamilegacy/mysql` image (`global.security.allowInsecureImages: true`). The
  MySQL chart is vendored as `infrastructure/charts/mysql-14.0.3.tgz` so Argo CD
  does not depend on the upstream repository at sync time.

- **Single custom chart.** `applications/app-chart` deploys both apps; replica
  counts, image tags, service types, ports and the optional Ingress are all
  configurable in `values.yaml`.

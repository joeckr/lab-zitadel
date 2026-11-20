# lab-zitadel

A hardened, self-contained Helm chart and local lab environment for deploying [ZITADEL](https://zitadel.com/) on a homelab Kubernetes cluster running **Talos Linux** (enforcing the `restricted` Pod Security Standard), **Cloudflare Tunnel** forwarding to a **Traefik Kubernetes Gateway** (`gateway.networking.k8s.io/v1` with `h2c`), **Longhorn** persistent storage, and [`joeckr/oci-postgres`](https://github.com/joeckr/oci-postgres) as the rootless PostgreSQL backend.

> [!IMPORTANT]
> **Update the Hostname & Domain for Your Environment**
> The default configuration in [`chart/values.yaml`](chart/values.yaml) uses **`zitadel.joeckr.dev`**. If you are deploying this chart in your own homelab, override `zitadel.externalDomain` and `httpRoute.hostnames` (plus `httpRoute.parentRefs` if your Traefik Gateway uses a different name or namespace) before installing.

---

## Architecture

```text
Internet
   │
   ▼
Cloudflare Edge (TLS termination + HTTP/2 / gRPC)
   │
   ▼
Cloudflare Tunnel (cloudflared, http2Origin: true)
   │  forwards zitadel.joeckr.dev
   ▼
Traefik Kubernetes Gateway (Gateway API)
   │  HTTPRoute (zitadel.joeckr.dev)
   ├── /ui/v2/login (optional) ──▶ ZITADEL Login V2 Service (:3000) ──▶ Login V2 Pod
   │                                                                        │
   ▼  / (h2c / HTTP/2)                                                      │ HTTP
ZITADEL Service (:8080, appProtocol: kubernetes.io/h2c) ◀───────────────────┘
   │
   ▼
ZITADEL Core Pod (start-from-init)
   │  PostgreSQL (:5432)
   ▼
PostgreSQL Service (zitadel-pg:5432) ──▶ Rootless PostgreSQL Pod (Longhorn PVC)
```

### Key Features

- **ZITADEL v4 Core & Login V2 (`chart/`)**:
  - Runs `ghcr.io/zitadel/zitadel:v4.20.4` with `start-from-init --masterkeyFromEnv --tlsMode external`, health/readiness/startup probes (`/debug/healthz`, `/debug/ready`), and automatic schema initialization.
  - Bundles and auto-bootstraps the standalone **Login V2** UI (`ghcr.io/zitadel/zitadel-login:v4.20.4`) using an auto-generated RSA keypair (`kubernetes.io/tls` Secret) registered as a `SystemAPIUser`, with `/ui/v2/login` routed automatically on the `HTTPRoute`.
- **Rootless PostgreSQL Subchart ([`joeckr/oci-postgres`](https://github.com/joeckr/oci-postgres))**:
  - Declared as an OCI Helm dependency (`oci://ghcr.io/joeckr/charts`, `postgres` `0.2.3`) using `ghcr.io/joeckr/postgres:18`.
  - Runs rootless under Restricted PSS backed by a Longhorn `ReadWriteOnce` PVC (`5Gi`).
  - Can be disabled (`postgres.enabled=false`) in favor of an external PostgreSQL database (`externalPostgres.*`).
- **Traefik Kubernetes Gateway API (`HTTPRoute` + `h2c`)**:
  - Routes `zitadel.joeckr.dev` through your Traefik Kubernetes Gateway (`gateway.networking.k8s.io/v1`).
  - Configures `appProtocol: kubernetes.io/h2c` on the ZITADEL Service so Traefik speaks cleartext HTTP/2 (`h2c`) for gRPC when TLS is terminated externally by Cloudflare.
- **Hardened for Talos Linux & PSS `restricted`**:
  - `runAsNonRoot: true`, `readOnlyRootFilesystem: true` (core), `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile.type: RuntimeDefault`, and `automountServiceAccountToken: false`.
  - Supports pre-created Kubernetes Secrets (`zitadel.existingSecret`) to keep the 32-character masterkey and database credentials out of Git.
  - Control-plane/master tolerations included for compact Talos homelab clusters.

---

## Directory Structure

```text
.
├── .github/
│   └── workflows/
│       ├── lint.yml                     # Lints workflows, commits, and shell scripts
│       ├── security.yml                 # Scans for secrets and audits workflow security
│       ├── release.yml                  # Semantic release and Helm chart publishing to GHCR
│       └── test_release.yml             # PR dry-run test for releases and chart packaging
├── chart/
│   ├── Chart.yaml                       # Helm chart metadata + oci-postgres dependency
│   ├── Chart.lock                       # Locked OCI subchart dependencies
│   ├── values.yaml                      # Default values (update domain/secrets)
│   ├── .helmignore                      # Ignore rules for chart packaging
│   └── templates/
│       ├── _helpers.tpl                 # Shared naming, label, and PostgreSQL helpers
│       ├── NOTES.txt                    # Post-install instructions
│       ├── configmap.yaml               # Non-sensitive ZITADEL configuration
│       ├── secret.yaml                  # Masterkey & DB credentials (when existingSecret is unset)
│       ├── deployment.yaml              # ZITADEL Core Deployment (PSS restricted)
│       ├── service.yaml                 # ZITADEL ClusterIP Service (:8080, h2c)
│       ├── login-configmap.yaml         # SystemAPIUsers config for Login V2
│       ├── login-key-secret.yaml        # Auto-generated RSA keypair TLS Secret for Login V2
│       ├── login-deployment.yaml        # ZITADEL Login V2 Deployment (PSS restricted)
│       ├── login-service.yaml           # ZITADEL Login V2 Service (:3000)
│       └── httproute.yaml               # Gateway API HTTPRoute for zitadel.joeckr.dev
├── compose.yml                          # Local Podman Compose preview stack
├── hk.pkl                               # hk git hooks and checks configuration
├── mise.toml                            # Mise tools and tasks
└── README.md
```

---

## Prerequisites

1. **Talos Linux Kubernetes cluster** with `kubectl` and `helm` (`>= 3.14`) configured.
2. **Longhorn** installed with a `longhorn` `StorageClass` (or override `postgres.postgres.storageClass`).
3. **Traefik (v3+) with Kubernetes Gateway API** enabled and a `Gateway` resource created (defaults expect `name: traefik-gateway` in namespace `gateway`, listener `web`).
   - Ensure the `Gateway` listener allows routes from the namespace where you install this chart (e.g., `allowedRoutes.namespaces.from: All` or `Selector`).
   - Traefik v3+ reads `appProtocol: kubernetes.io/h2c` on the ZITADEL Service to forward HTTP/2 / gRPC traffic over cleartext.
4. **Cloudflare Tunnel (`cloudflared`)** configured to forward your ZITADEL hostname (`zitadel.joeckr.dev`) to your Traefik Kubernetes Gateway service:
   - In Cloudflare Zero Trust -> **Networks** -> **Tunnels** -> **Public Hostnames**:
     - **Subdomain / Domain**: `zitadel.joeckr.dev` (replace with your own domain)
     - **Service**: `http://gateway-traefik.gateway.svc.cluster.local:80` (adjust to match your Traefik service name and namespace)
     - **Additional application settings -> HTTP Settings**: enable **HTTP2 connection** (`http2Origin: true`) so gRPC streams pass cleanly through Cloudflare Tunnel to Traefik.
   - Ensure Cloudflare SSL/TLS encryption mode is set to **Full** or **Full (strict)**.

---

## Installation

### 1. Create a Namespace

Label the namespace to enforce Kubernetes Pod Security Standards (`restricted`):

```sh
kubectl create namespace zitadel
kubectl label namespace zitadel \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest
```

### 2. Prepare Secrets (Recommended: Pre-Created Kubernetes Secret)

Using `zitadel.existingSecret` keeps sensitive values out of your Helm values files and Git history. ZITADEL requires a **32-character** masterkey (`openssl rand -hex 16` produces exactly 32 hex characters):

```sh
# Generate random credentials
ZITADEL_MASTERKEY=$(openssl rand -hex 16)
ZITADEL_SESSION_COOKIE_SECRET=$(openssl rand -hex 24)
POSTGRES_PASSWORD=$(openssl rand -base64 24)

# Create ZITADEL Secret
kubectl -n zitadel create secret generic zitadel-secrets \
  --from-literal=ZITADEL_MASTERKEY="${ZITADEL_MASTERKEY}" \
  --from-literal=ZITADEL_SESSION_COOKIE_SECRET="${ZITADEL_SESSION_COOKIE_SECRET}" \
  --from-literal=ZITADEL_DATABASE_POSTGRES_USER_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD="${POSTGRES_PASSWORD}"
```

### 3. Create a Values Override File

Create a local `my-values.yaml` (do not commit secrets to Git). Update the domain, Gateway `parentRefs`, and PostgreSQL password to match your secret:

```yaml
zitadel:
  # Update this to your own domain!
  externalDomain: "zitadel.joeckr.dev"
  existingSecret: "zitadel-secrets"

httpRoute:
  enabled: true
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: traefik-gateway
      namespace: gateway
      sectionName: web
  hostnames:
    - "zitadel.joeckr.dev"

postgres:
  enabled: true
  postgres:
    storageClass: "longhorn"
    storageSize: 5Gi
    # Must match POSTGRES_PASSWORD in zitadel-secrets
    password: "<your-postgres-password>"
```

### 4. Deploy with Helm

Build dependencies and install from the local repository:

```sh
mise run helm-d
helm upgrade --install zitadel chart/ \
  --namespace zitadel \
  --values my-values.yaml
```

Or install directly from the published OCI chart on GHCR:

```sh
helm upgrade --install zitadel oci://ghcr.io/joeckr/charts/lab-zitadel \
  --namespace zitadel \
  --values my-values.yaml
```

### 5. Verify the Deployment

```sh
# Check pods, PVCs, and HTTPRoute
kubectl -n zitadel get pods,pvc,httproute

# Check ZITADEL logs
kubectl -n zitadel logs -l app.kubernetes.io/name=lab-zitadel,app.kubernetes.io/component=server -f

# Check PostgreSQL logs
kubectl -n zitadel logs -l app=zitadel-pg -f
```

---

## Post-Install Setup

1. **Initial Console Login**:
   - Open `https://<your-domain>/ui/console` (or port-forward with `kubectl -n zitadel port-forward svc/zitadel-lab-zitadel 8080:8080`).
   - Sign in with the default admin user `zitadel-admin@zitadel.<your-domain>` and password `Password1!` (unless overridden via `zitadel.firstInstance.*`).
   - ZITADEL will immediately prompt you to change the initial admin password.

2. **Login V2 Authentication**:
   - Login V2 is enabled and auto-bootstrapped out of the box. Helm generates a persistent self-signed RSA keypair (`kubernetes.io/tls` Secret) on first install, mounts `tls.crt` into ZITADEL Core as a `SystemAPIUser` (`login-client`), and mounts `tls.key` into `zitadel-login` for Private Key JWT authentication.
   - To supply your own RSA keypair (e.g., via `cert-manager`), set `login.existingKeySecret` to the name of your `kubernetes.io/tls` Secret.

---

## Key Configuration Values

| Parameter | Default | Description |
|---|---|---|
| `zitadel.image.repository` | `ghcr.io/zitadel/zitadel` | ZITADEL Core container image |
| `zitadel.image.tag` | `"v4.20.4"` | ZITADEL Core image tag |
| `zitadel.externalDomain` | `"zitadel.joeckr.dev"` | Public ZITADEL hostname (**update for your domain**) |
| `zitadel.externalPort` | `443` | Public external port |
| `zitadel.externalSecure` | `true` | Advertise HTTPS external URLs |
| `zitadel.tlsMode` | `"external"` | Internal TLS mode (`external` serves `h2c` for Traefik) |
| `zitadel.masterkey` | placeholder (32 chars) | 32-character encryption masterkey |
| `zitadel.existingSecret` | `""` | Pre-existing Kubernetes Secret name (skips creating Secret) |
| `zitadel.loginV2Required` | `true` | Enforce standalone Login V2 UI |
| `login.enabled` | `true` | Deploy `ghcr.io/zitadel/zitadel-login` Deployment & Service |
| `login.basePath` | `"/ui/v2/login"` | Path prefix routed to the Login V2 container |
| `login.systemUserId` | `"login-client"` | Lowercase `SystemAPIUser` ID for Login V2 |
| `login.existingKeySecret` | `""` | Pre-existing `kubernetes.io/tls` RSA keypair Secret (auto-generated if empty) |
| `login.sessionCookieSecret` | placeholder (32 chars) | Session cookie signing secret (`>= 32` chars) |
| `service.appProtocol` | `"kubernetes.io/h2c"` | Tells Traefik Gateway API to use HTTP/2 cleartext (`h2c`) |
| `httpRoute.enabled` | `true` | Create Gateway API `HTTPRoute` |
| `httpRoute.parentRefs` | `gateway/traefik-gateway` (`web`) | Target Traefik Kubernetes `Gateway` reference |
| `httpRoute.hostnames` | `["zitadel.joeckr.dev"]` | Hostnames matched by the `HTTPRoute` |
| `postgres.enabled` | `true` | Deploy embedded `oci-postgres` subchart |
| `postgres.postgres.image` | `ghcr.io/joeckr/postgres` | Rootless PostgreSQL image |
| `postgres.postgres.tag` | `"18"` | PostgreSQL major version tag |
| `postgres.postgres.storageClass` | `"longhorn"` | StorageClass for PostgreSQL PVC |
| `postgres.postgres.storageSize` | `5Gi` | Storage size for PostgreSQL PVC |

See [`chart/values.yaml`](chart/values.yaml) for the complete list of configurable options.

---

## Security & Hardened Pod Architecture (Kubernetes PSS `restricted`)

All pods in this chart comply with the Kubernetes **Pod Security Standards `restricted`** profile out of the box on Talos Linux:

| Security Dimension | Restricted PSS Requirement | Implementation in This Chart |
|---|---|---|
| **Workload Execution** | Non-root UID (`runAsNonRoot: true`) | ZITADEL (`1000:1000`), Login V2 (`1001:1001`), `oci-postgres` (rootless, `fsGroup: 1031`) |
| **Root Filesystem** | Hardened per workload | `readOnlyRootFilesystem: true` on ZITADEL Core (with `/tmp` `emptyDir`) |
| **Capabilities** | Must drop `ALL` capabilities | `capabilities.drop: ["ALL"]` on all containers |
| **Privilege Escalation** | Prohibited | `allowPrivilegeEscalation: false` |
| **Seccomp Profile** | `RuntimeDefault` or `Localhost` | `seccompProfile: { type: RuntimeDefault }` |
| **Service Account Token** | Disabled unless required | `automountServiceAccountToken: false` |
| **Port Binding** | Unprivileged (> 1024) | ZITADEL `8080`, Login V2 `3000`, PostgreSQL `5432` |
| **Routing Layer** | Kubernetes Gateway API | `gateway.networking.k8s.io/v1` `HTTPRoute` (`h2c` backend) |

---

## Local Preview (`compose.yml`)

You can preview ZITADEL + PostgreSQL locally before deploying to your cluster:

```sh
# Start PostgreSQL and ZITADEL
mise run compose
# or: podman compose up -d

# Tail logs
mise run logs

# Stop and remove containers
mise run down
```

- **ZITADEL Console**: [http://localhost:8080/ui/console](http://localhost:8080/ui/console)
- **Default Local Credentials**: `zitadel-admin@zitadel.localhost` / `Password1!`

---

## Local Development & Tasks

### Setup

```sh
# Install tools and git hooks
mise run install
```

### Available Tasks

Run tasks with `mise run <task>`:

| Task | Description | Command |
|---|---|---|
| `install` | Install tools and set up git hooks | `hk install --mise` |
| `hk` (or `check`) | Run all linters and hook checks | `hk check --all` |
| `compose` | Start local ZITADEL + PostgreSQL preview stack | `podman compose up -d` |
| `down` | Stop local Podman Compose stack | `podman compose down` |
| `logs` | View Podman Compose logs | `podman compose logs -f` |
| `helm-d` | Build Helm chart dependencies | `helm dependency build chart/` |
| `helm-l` | Lint Helm chart | `helm lint chart/` |
| `helm-t` | Render Helm chart templates to `rendered.yaml` | `helm template test chart/ > rendered.yaml` |
| `helm-i` | Install Helm chart to current Kubernetes cluster | `helm install test chart/` |
| `helm-u` | Uninstall Helm chart release from cluster | `helm uninstall test` |
| `trivy-fs` | Scan repository filesystem for security vulnerabilities | `trivy fs .` |

---

## Conventional Commits & Releases

Commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:
- `feat: add new feature` -> Triggers a **minor** release (e.g., `v0.1.0` -> `v0.2.0`).
- `fix: resolve issue` -> Triggers a **patch** release (e.g., `v0.1.0` -> `v0.1.1`).
- `feat!: breaking change` -> Triggers a **major** release.
- `chore:`, `docs:`, `ci:`, `test:`, `refactor:` -> Maintenance changes (no release bump).

Upon merging to `main`, the `release.yml` workflow automatically computes the next version, updates `version` and `appVersion` in `chart/Chart.yaml`, creates a Git tag, publishes a GitHub Release, and packages and pushes the Helm chart to GHCR.

## Support

If you find this project useful, consider supporting my work on [Ko-fi](https://ko-fi.com/joeckr):

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/joeckr)

## License

Please refer to the `LICENSE` file for details.

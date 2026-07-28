# Three-environment Google Cloud Terraform platform

This repository provisions the same complete service catalog in three isolated
Google Cloud environments: `dev`, `test`, and `production`. Terraform creates
one Compute Engine VM per environment, while a shared second-generation Cloud
Run function supplies the Function-as-a-Service endpoint.

> **Cost warning:** this is an enterprise-sized demonstration, not a Free Tier
> deployment. Do not run `terraform apply` until billing, quotas, network
> exposure, and the expected cost have been approved.

## Architecture

```text
Google Cloud project
|
+-- Custom VPC (10.42.0.0/16)
|   +-- dev subnet  (10.42.10.0/24) -> dev VM
|   +-- test subnet (10.42.20.0/24) -> test VM
|   +-- prod subnet (10.42.30.0/24) -> production VM
|   +-- IAP-only SSH + optional trusted application CIDRs
|
+-- Shared Cloud Run function (2nd gen)
|   +-- Python 3.14 HTTP endpoint
|   +-- Private GCS source package
|   +-- Dedicated build and runtime service accounts
|
+-- Cloud Logging / Monitoring
```

The VPC is custom-mode and does not depend on a default network. Each VM has a
reserved external IPv4 address, a dedicated subnet, OS Login, a dedicated
runtime identity, and all Shielded VM protections enabled. Google-managed
encryption protects Persistent Disk by default.

## Capacity

| Environment | Compute Engine type | vCPU | RAM | Boot disk |
|---|---|---:|---:|---:|
| dev | `n2-standard-8` | 8 | 32 GB | 150 GB `pd-balanced` |
| test | `n2-standard-8` | 8 | 32 GB | 150 GB `pd-balanced` |
| production | `n2-standard-16` | 16 | 64 GB | 300 GB `pd-balanced` |
| **Total** | **3 VMs** | **32** | **128 GB** | **600 GB** |

The sizing is deliberate because each machine runs databases, JVM workloads,
NiFi, TensorFlow Serving, Spark, and the rest of the catalog together. Confirm
that the project has at least 32 regional N2 vCPUs available before deployment.

## Service inventory

Each VM runs the same 36 Docker containers:

- Runtimes: Python, Node.js, Java, Go, and Ruby.
- Frameworks and data processing: Django, Flask, FastAPI, Express, Spring Boot,
  .NET SDK, and Apache Spark.
- Databases: MySQL, MariaDB, PostgreSQL, MongoDB, and Redis.
- Web/application servers: Nginx, Apache HTTP Server, Tomcat, and WildFly.
- Application platforms: Open WebUI, Jupyter, Ganache, Remix IDE, EMQX, WebXR,
  PocketBase, Portainer, and n8n.
- Added services: AR, VR, TensorFlow Serving, Kong Gateway, Apache NiFi, and
  MediaMTX.

The shared Cloud Run function is the 37th logical service type. The complete
deployment therefore contains 108 container deployments (36 x 3) and one
serverless function.

## Google Cloud resources

Terraform manages:

- Required Google Cloud APIs.
- One custom VPC, three regional subnets, and three reserved external IPv4
  addresses.
- Three Ubuntu 24.04 Compute Engine VMs and 600 GB of balanced Persistent Disk.
- Internal, IAP SSH, optional direct SSH, and optional public-service firewall
  rules.
- Separate VM, function-build, and function-runtime service accounts with
  scoped IAM roles.
- One private GCS source bucket/object and one Python 3.14 Cloud Run function.
- Three independently generated NiFi administrator passwords.
- A best-effort Google Cloud Ops Agent installation for bootstrap logs.

## Prerequisites

- Terraform 1.7 or newer.
- Google Cloud CLI.
- An existing Google Cloud project with billing enabled.
- Permission to enable services and create Compute Engine, IAM, Cloud Storage,
  Cloud Build, Cloud Run, and Cloud Run functions resources.
- Permission to act as the service accounts created by this configuration.
- Adequate N2 CPU, external IPv4, and Persistent Disk quota in the selected
  region.

Authenticate locally:

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
```

## Safe local validation (no cloud resources)

The backend deliberately uses `gcp.tfstate`. It must not be migrated from an
old AWS or Azure state file.

```powershell
terraform init -reconfigure -upgrade
terraform fmt -recursive -check
terraform validate -no-color
terraform test -no-color
```

The mocked test does not authenticate to Google Cloud, create infrastructure,
or incur cloud charges. `terraform init` only installs provider plugins.

## Configuration

Create the ignored variables file and edit every placeholder:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
code terraform.tfvars
```

Application ports are closed to the internet by default. For short-lived
testing, set `public_service_allowed_cidrs` to your own public address with a
`/32` suffix. Never use `0.0.0.0/0` for production.

Add an IAM identity to `iap_ssh_members` if Terraform should grant the roles
needed for OS Login and IAP tunnelling:

```hcl
iap_ssh_members = ["user:you@example.com"]
```

The default environment map must contain exactly `dev`, `test`, and
`production`. Machine types, zones, subnet CIDRs, and disk sizes can be
overridden only after measuring the real workloads. If `gcp_region` changes,
all three `zone` values must be changed to zones in that same region.

## Preview and deploy

`terraform plan` reads Google Cloud but does not create resources:

```powershell
terraform plan -out=gcp.tfplan
```

Review the full plan. A real deployment starts billing:

```powershell
terraform apply gcp.tfplan
```

API activation and IAM propagation can take several minutes. The startup script
then installs Docker, pulls the images, downloads the TensorFlow example model,
and waits for the added services to become healthy.

## Access and verification

After an approved deployment:

```powershell
terraform output environment_public_ips
terraform output environment_service_urls
terraform output environment_iap_ssh_commands
terraform output environment_run_commands
terraform output -raw gcp_function_url
```

Use a generated IAP command to inspect a VM. OS Login accounts are dynamic, so
administrators should run Docker commands with `sudo`.

NiFi listens only on VM loopback. Start the environment-specific tunnel shown
by this output:

```powershell
terraform output environment_nifi_iap_tunnels
```

Then browse to `https://localhost:8443/nifi`. The demonstration uses a
self-signed certificate, so a browser warning is expected.

When your `/32` CIDR is allowed, replace `ENVIRONMENT_IP` below:

```powershell
curl.exe http://ENVIRONMENT_IP:8092/healthz
curl.exe http://ENVIRONMENT_IP:8093/healthz
curl.exe http://ENVIRONMENT_IP:8000/ar/healthz
curl.exe -H "Content-Type: application/json" -d '{"instances":[1.0,2.0,5.0]}' http://ENVIRONMENT_IP:8501/v1/models/half_plus_two:predict
```

On a VM, inspect `/var/log/devcloud-userdata.log`,
`/var/log/platform-userdata.log`, `/opt/platform/bootstrap-success`, and:

```bash
sudo docker ps
cd /opt/runtime && sudo docker compose ps
cd /opt/platform && sudo docker compose ps
```

## Security and data notes

- SSH is allowed through Identity-Aware Proxy from Google's documented
  `35.235.240.0/20` range; direct SSH is disabled by default.
- Database, Jupyter, Portainer, EMQX dashboard, Ganache, NiFi, and Kong admin
  ports are not publicly exposed.
- The FaaS endpoint is public by default because every Kong instance needs to
  invoke it. Set `function_allow_unauthenticated = false` and add authenticated
  invocation before using this design for production.
- Database passwords and tokens are present in Terraform state and VM startup
  metadata. Protect both, and prefer Secret Manager in a production design.
- Docker volumes are stored on auto-deleting boot disks. Back them up before
  VM replacement, `terraform destroy`, or major configuration changes.
- Some original images use `latest`. Pin tested image digests before treating
  this as a production platform.

To remove an approved deployment:

```powershell
terraform plan -destroy
terraform destroy
```

Destroying the VMs deletes their boot disks and all Docker data. Terraform
state, `.tfvars`, generated ZIP files, plans, PEM/key files, and local tooling
folders are excluded from Git.

## References

- [Compute Engine N2 machine types](https://docs.cloud.google.com/compute/docs/general-purpose-machines)
- [Cloud Run functions with Terraform](https://docs.cloud.google.com/functions/docs/tutorials/terraform)
- [Cloud Run functions runtime support](https://docs.cloud.google.com/functions/docs/runtime-support)
- [IAP TCP forwarding](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding)
- [Google Cloud Free Tier](https://docs.cloud.google.com/free/docs/free-cloud-features)

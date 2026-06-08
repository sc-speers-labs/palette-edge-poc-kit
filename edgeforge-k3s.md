# Palette Edge: EdgeForge Build Guide (K3s)

A practical guide to building Palette Edge artifacts (Installer ISO and Provider Images) using CanvOS with K3s, and deploying an Edge cluster through Palette. This guide assumes you are working in **your own environment** — not a Spectro Cloud lab.

---

## Overview

The EdgeForge workflow produces two artifacts:

- **Installer ISO** — boots your Edge host and installs the Palette Edge agent
- **Provider Images** — Kairos-based container images combining Ubuntu and K3s, used in the cluster profile OS layer

Both are required before you can deploy an Edge cluster.

**Reference:** [EdgeForge Workflow](https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/) | [Build Edge Artifacts](https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/palette-canvos/)

---

## Prerequisites

### Build Machine

- Physical or virtual Linux machine (AMD64/x86_64 architecture)
- Docker and Docker Compose installed
- Git installed
- Internet access
- At least 50 GB free disk space (builds are large)

Verify your architecture:
```bash
uname -m
# Expected output: x86_64
```

Install Docker if needed:
```bash
# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add your user to the docker group
sudo usermod -aG docker $USER
newgrp docker
```

### Image Registry

You need a container registry to push provider images to. Options:

- **Your own private registry** (recommended for production)
- **`ttl.sh`** — free, anonymous, images expire after 24 hours (useful for testing only)
- **Docker Hub, ECR, GCR, etc.**

### Palette Account

- A running Palette instance (SaaS or self-hosted)
- A registration token: **Tenant Settings → Security → Registration Tokens → Add New Registration Token**

---

## Step 1: Prepare Configuration Files

You need two files: `.arg` (controls the build) and `user-data` (configures the installer ISO).

### Option A: Appliance Studio (GUI — Tech Preview)

Appliance Studio provides a browser-based UI for creating these files with schema validation.

> **Note:** Appliance Studio is a Tech Preview feature. For production workloads, create the files manually (Option B).

```bash
# Download and start Appliance Studio
wget software.spectrocloud.com/appliance-studio/v4.6.1/docker-compose.yml
sudo docker compose up -d
```

Access at `http://localhost:8443`. Under **Kubernetes & Cluster**, set the distribution to `k3s`. Download the generated files when done.

**Reference:** [Appliance Studio](https://docs.spectrocloud.com/deployment-modes/appliance-mode/appliance-studio/) | [Prepare User Data and Argument Files](https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/prepare-user-data/)

---

### Option B: Manual File Creation

#### `.arg` File

The following is a known-good `.arg` file for a K3s + Ubuntu build. The fields marked `# REQUIRED` must be set by you; everything else can be used as-is.

```bash
# -------------------------------------------------------
# Palette Edge - CanvOS build arguments
# K3s + Ubuntu
# -------------------------------------------------------

ARCH=amd64
OS_DISTRIBUTION=ubuntu
OS_VERSION=22               # use 22 for 22.04, or 24 for 24.04
IMAGE_REGISTRY=<your-registry>    # REQUIRED — e.g. myregistry.example.com or ttl.sh
IMAGE_REPO=ubuntu
CUSTOM_TAG=<your-tag>             # REQUIRED — alphanumeric lowercase only, e.g. prod-v1
K8S_DISTRIBUTION=k3s
K8S_VERSION=1.32.13               # pin to your target version; check k8s_version.json in CanvOS for supported values
ISO_NAME=palette-edge-installer
HTTPS_PROXY=
HTTP_PROXY=
PROXY_CERT_PATH=
UPDATE_KERNEL=false
FIPS_ENABLED=false
```

> **Important:** Do not leave `HTTPS_PROXY`, `HTTP_PROXY`, or `PROXY_CERT_PATH` with a value if you are not using a proxy — empty is correct. If there is a `BASE_IMAGE=` line in the file, remove it entirely rather than leaving it blank, or the build will fail.

> **Build output naming:** The provider image tag will follow the pattern `[IMAGE_REGISTRY]/[IMAGE_REPO]:[K8S_DISTRIBUTION]-[K8S_VERSION]-[CanvOS_version]-[CUSTOM_TAG]`. For example: `myregistry.example.com/ubuntu:k3s-1.32.13-v4.9.10-prod-v1`

> **Tip — build speed:** By default CanvOS builds provider images for every supported K3s version. To speed things up, open `k8s_version.json` in the CanvOS directory after checkout and delete all versions except the one you need before running the build.

For all available arguments, see: [Edge Artifact Build Configurations](https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/palette-canvos/arg-reference/)

---

#### `user-data` File

The following is a known-good `user-data` file for a centrally managed deployment against the Palette SaaS endpoint. Fields marked `# REQUIRED` must be set by you.

```yaml
#cloud-config
stylus:
  site:
    paletteEndpoint: console.spectrocloud.com
    edgeHostToken: <your-registration-token>    # REQUIRED — from Tenant Settings → Security → Registration Tokens
    projectName: <your-project-name>            # REQUIRED — must match exactly as it appears in Palette

install:
  reboot: true
  poweroff: false    # set to true to power off after flashing instead of rebooting

stages:
  initramfs:
    - users:
        kairos:
          groups:
            - sudo
          passwd: <your-os-password>    # REQUIRED — set a strong password; this is the local OS user
      name: Create kairos user
```

**That's the minimum.** The following shows the same file with optional additions for common production needs — use only what applies to your environment:

```yaml
#cloud-config
stylus:
  site:
    paletteEndpoint: console.spectrocloud.com
    edgeHostToken: <your-registration-token>    # REQUIRED
    projectName: <your-project-name>            # REQUIRED
    name: edge-<your-site-id>                   # optional — sets a human-readable hostname in Palette
    tags:                                        # optional — arbitrary key/value labels visible in Palette
      site: warehouse-01
      env: production

    # Uncomment if your site requires a network proxy for outbound connections
    # network:
    #   httpProxy: http://proxy.example.com
    #   httpsProxy: https://proxy.example.com
    #   noProxy: 10.0.0.0/8,192.168.0.0/16

    # Uncomment to configure a static IP instead of DHCP
    # network:
    #   interfaces:
    #     eth0:
    #       type: static
    #       ipAddress: 10.0.10.25/24
    #       gateway: 10.0.10.1
    #       nameserver: 10.0.10.1

install:
  reboot: true
  poweroff: false

stages:
  initramfs:
    - users:
        kairos:
          groups:
            - sudo
          passwd: <your-os-password>    # REQUIRED
      name: Create kairos user
```

> **Note:** `registrationURL` is intentionally omitted. It only controls whether a QR code appears on the console during registration and has no effect on whether registration succeeds. Omit it unless you specifically need the QR code workflow.

For all user-data parameters, see: [Installer Configuration Reference](https://docs.spectrocloud.com/clusters/edge/edge-configuration/installer-reference/)

---

## Step 2: Build the Artifacts

### Install Earthly

```bash
sudo /bin/sh -c 'wget https://github.com/earthly/earthly/releases/latest/download/earthly-linux-amd64 \
  -O /usr/local/bin/earthly && chmod +x /usr/local/bin/earthly'
sudo /usr/local/bin/earthly bootstrap --with-autocomplete
```

### Clone CanvOS

```bash
git clone https://github.com/spectrocloud/CanvOS.git
cd CanvOS
```

Check available versions and check out the latest:

```bash
git tag
# Caution: git tag output is lexicographic, not numeric.
# v4.7.14 sorts before v4.7.9 because "1" < "9".
# Scroll through carefully and identify the true latest version.

git checkout v4.X.X   # replace with actual latest version
```

### Place Your Configuration Files

```bash
nano .arg        # paste your .arg content
nano user-data   # paste your user-data content
```

### (Optional) Validate User Data

```bash
sudo earthly +validate-user-data
```

### Run the Build

```bash
export EARTHLY_DISABLE_REMOTE_REGISTRY_PROXY=1
sudo -E earthly +build-all-images
```

The build takes 10–20 minutes. On success you'll see:
```
========================== Earthly Build SUCCESS ==========================
```

If the build fails citing a snapshot that doesn't exist, force a cache-free rebuild:
```bash
sudo earthly --no-cache +iso
```

### Verify Build Output

```bash
ls build/
# You should see:
# palette-edge-installer.iso
# palette-edge-installer.iso.sha256
```

List the built container images — the K3s image tag will include `k3s` in the name:
```bash
sudo docker images
# Example image name: myregistry.example.com/ubuntu:k3s-1.32.13-v4.9.10-prod-v1
```

### Push Provider Images to Your Registry

```bash
sudo docker push <your-registry>/<your-repo>:<tag>
# Example: sudo docker push myregistry.example.com/ubuntu:k3s-1.32.13-v4.9.10-prod-v1
```

---

## Step 3: Flash the Edge Host

Boot your Edge host from the installer ISO. The installer will run automatically and flash the Palette Edge agent to the host's disk.

> **iDRAC / virtual media note:** If booting via Dell iDRAC virtual media, the installer may drop to a `grub>` prompt. This is a known device enumeration issue. Workaround at the prompt:
> ```
> set root=(cd0)
> configfile /boot/grub2/grub.cfg
> ```

Once flashing is complete, the host will reboot (or power off, depending on your `install.poweroff` setting). Remove the installer media before the next boot so the host doesn't re-flash.

On next power-on, the host will register automatically with Palette using the `edgeHostToken` in your user-data.

---

## Step 4: Verify Registration in Palette

1. Log into Palette and navigate to your project
2. Go to **Clusters → Edge Hosts**
3. Your host should appear with status **Ready** and health **Healthy**

If it doesn't appear within a few minutes, check:
- The `paletteEndpoint` in your user-data is correct and reachable from the host
- The `edgeHostToken` is valid and not expired
- Network connectivity from the edge host to Palette

---

## Step 5: Create a Cluster Profile

You need a cluster profile with three layers:

- **OS layer:** BYOOS (Edge) pack
- **Kubernetes layer:** Palette Optimized K3S
- **Network layer:** Cilium (recommended) or Calico

### OS Layer (BYOOS) Values

In the BYOOS pack, ensure these values match your build exactly:

```yaml
options:
  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"
  system.registry: <your-registry>         # must match IMAGE_REGISTRY in .arg
  system.repo: ubuntu                       # must match IMAGE_REPO in .arg
  system.k8sDistribution: k3s
  system.osName: ubuntu
  system.peVersion: v4.9.X                  # CanvOS version tag used in your build (e.g. v4.9.10)
  system.customTag: <your-tag>              # must match CUSTOM_TAG in .arg (e.g. prod-v1)
  system.osVersion: 22                      # use 22 or 24 — matches OS_VERSION in .arg
```

### Kubernetes Layer

Select **Palette Optimized K3S** and choose the version matching what you built. The OIDC identity provider is configured here — for most deployments, set it to `palette`:

```yaml
pack:
  palette:
    config:
      oidc:
        identityProvider: palette
```

### Spectro Proxy / Kubernetes Dashboard

If using the Spectro Kubernetes Dashboard in proxy mode, you need a `certSANs` entry so TLS verification works through the proxy. For K3s, add the following to the Kubernetes pack values under `kubeadmconfig.apiServer`:

```yaml
kubeadmconfig:
  apiServer:
    certSANs:
      - "cluster-{{ .spectro.system.cluster.uid }}.{{ .spectro.system.reverseproxy.server }}"
```

> **Note:** This is only required if you are using the Spectro Proxy pack and the Kubernetes Dashboard in proxy mode. If you are using RKE2 instead of K3s, use `tls-san` instead of `certSANs`.

**Reference:** [Model Edge Native Cluster Profile](https://docs.spectrocloud.com/clusters/edge/site-deployment/model-profile/)

---

## Step 6: Deploy the Cluster

1. In Palette, go to **Clusters → Create Cluster**
2. Select **Edge Native** → **Start Edge Native Configuration**
3. Name your cluster and click **Next**
4. Select your cluster profile and confirm
5. In **Cluster Config**, set the **VIP** (virtual IP for the control plane)
6. In **Nodes Config**, add your registered Edge hosts under Pool Configuration
7. Enable **Allow worker capability** if using a single-node control plane as both control plane and worker
8. Remove the default Worker Pool if running a single-node cluster
9. Click **Next → Validate → Finish Configuration**

Deployment takes 5–15 minutes depending on image pull times.

---

## Step 7: Connect to the Cluster

Once the cluster shows **Healthy / Running** in Palette:

1. Navigate to your cluster's overview page
2. Download the **Admin Kubeconfig File**
3. Set your kubeconfig:

```bash
export KUBECONFIG=/path/to/your/downloaded.kubeconfig
kubectl get nodes
kubectl get pods -A
```

---

## Useful References

| Topic | Link |
|---|---|
| EdgeForge overview | https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/ |
| Build Edge Artifacts (combined ISO + images) | https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/palette-canvos/ |
| Build Installer ISO only | https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/palette-canvos/build-installer-iso/ |
| Prepare user-data and .arg files | https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/prepare-user-data/ |
| Installer configuration reference | https://docs.spectrocloud.com/clusters/edge/edge-configuration/installer-reference/ |
| .arg build argument reference | https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/palette-canvos/arg-reference/ |
| Model Edge cluster profile | https://docs.spectrocloud.com/clusters/edge/site-deployment/model-profile/ |
| Create registration token | https://docs.spectrocloud.com/clusters/edge/site-deployment/site-installation/create-registration-token/ |
| Appliance Studio | https://docs.spectrocloud.com/deployment-modes/appliance-mode/appliance-studio/ |
| Edge deployment lifecycle | https://docs.spectrocloud.com/clusters/edge/edge-native-lifecycle/ |
| Hardware requirements | https://docs.spectrocloud.com/clusters/edge/hardware-requirements/ |

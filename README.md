# Ansible playbook to build Chef Infra Client 19.x from source

Builds **Chef Infra Client `v19.4.14`** on an Ubuntu x86_64/amd64 host, then
packages **per-release** `.deb` artifacts for Ubuntu **22.04 / 24.04 / 26.04**
using Docker (each `.deb` is compiled inside that release's container image).

1. Install apt build toolchain and utilities (includes `docker.io`)  
2. Install Ruby **3.4.10** via **rbenv** (matches Habitat plan for v19.4.14)  
3. Install the Habitat CLI (**hab**) binary from packages.chef.io (no Builder token)  
4. Clone `chef/chef` and build/install via **Bundler + `rake install:local`**  
5. Build release-specific `.deb` packages in Docker (`ubuntu:22.04`, `24.04`, `26.04`)

## Why not `hab pkg build` by default?

Habitat Studio can run on the host, but Chef 19’s plan needs Builder `core/*`
packages (license + token). This playbook uses a local gem build plus Docker
packaging instead.

## Prerequisites

- Ansible on the control machine (`ansible-playbook`)
- SSH to the build VM as a user with passwordless sudo
- Outbound HTTPS from the VM (GitHub, rubygems.org, Docker Hub)

## Inventory

Default target: `ubuntu@192.168.0.131` in `inventory/hosts.yml`.

## Usage

```bash
make help           # list targets
make build          # bootstrap + source build + validate + all packages
make validate       # re-check chef-client --version on the VM
make package        # build .debs for 22.04, 24.04, and 26.04
make package-22.04  # jammy only
make package-24.04  # noble only
make package-26.04  # resolute only
```

Artifacts on the build VM:

```text
~/packages/ubuntu-22.04/chef-infra-client_19.4.14~ubuntu22.04_amd64.deb
~/packages/ubuntu-24.04/chef-infra-client_19.4.14~ubuntu24.04_amd64.deb
~/packages/ubuntu-26.04/chef-infra-client_19.4.14~ubuntu26.04_amd64.deb
```

Install on a matching Ubuntu amd64 host:

```bash
sudo apt-get install -y ./chef-infra-client_19.4.14~ubuntu22.04_amd64.deb
/usr/bin/chef-client --version
```

Use the package built for that host’s release (22.04 package on jammy, etc.).

Source checkout: `~/src/chef` (tag `v19.4.14`).

## Variables

See `group_vars/all.yml` for pins and `chef_package_targets` (images + Depends).

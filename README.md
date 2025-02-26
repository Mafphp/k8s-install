# Kubernetes Cluster Setup Scripts

![Kubernetes Logo](https://static-00.iconduck.com/assets.00/kubernetes-icon-512x496-t2lupefk.png)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.28-326CE5.svg?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-E95420.svg?logo=ubuntu&logoColor=white)](https://ubuntu.com/)

A collection of automated scripts for quick deployment of a Kubernetes cluster on Ubuntu machines.

## 📋 Overview

This repository contains tw scripts that automate the deployment of a Kubernetes cluster:

- `k8s-master-install.sh`: Sets up the Kubernetes control plane node
- `k8s-worker-install.sh`: Sets up Kubernetes worker nodes

## 🚀 Feature

- **Fully Automated**: Minimal manual intervention required
- **Interactive**: Guides you through the necessary configuration steps
- **Production-Ready**: Follows Kubernetes best practices
- **Error Handling**: Validates inputs and provides clear error messages
- **Flexible Networking**: Configurable pod network CIDR
- **Container Runtime**: Uses containerd for optimal performance
- **User-Friendly**: Clear, step-by-step output during installation

## 📋 Requirements

 Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu 20.04 LTS or newer |
| **CPU** | 2+ cores per node |
| **RAM** | 2GB+ per node (4GB+ recommended) |
| **Storage** | 20GB+ free space |
| **Network** | Connectivity between all nodes |
| **Privileges** | Root or sudo access |
| **Internet** | Access to download packages |

## 🛠️ Installation

### Control Plane (Master) Node

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/kubernetes-setup.git
   cd kubernetes-setup
   ```
2. **Master Token**
   ```bash
   kubeadm token create --print-join-command
   ```

3. **Remove the Taint from the Master Node**
   ```bash
   kubectl taint nodes <master-node-name> node-role.kubernetes.io/control-plane:NoSchedule-
   ```

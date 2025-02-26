#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Print commands and their arguments as they are executed
set -x

echo "=== Starting Kubernetes Master Node Installation ==="

# Step 1-2: Update and upgrade packages
echo "Updating and upgrading packages..."
sudo apt update
sudo apt-get upgrade -y

# Step 3-4: Disable swap
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Step 5-6: Set hostname
echo "Setting hostname to k8s-master..."
sudo hostnamectl set-hostname k8s-master
hostname

# Step 7: Update /etc/hosts
echo "Updating /etc/hosts..."
MASTER_IP=$(hostname -I | awk '{print $1}')
echo "$MASTER_IP k8s-master" | sudo tee -a /etc/hosts

# Step 8-10: Configure kernel modules
echo "Configuring kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Step 11-12: Configure system settings
echo "Configuring system settings..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Step 13-14: Install prerequisites
echo "Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Step 15-18: Install containerd
echo "Installing containerd..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y containerd.io

# Step 19-23: Configure containerd
echo "Configuring containerd..."
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Step 24-28: Install Kubernetes components
echo "Installing Kubernetes components..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Step 29: Initialize Kubernetes control plane
echo "Initializing Kubernetes control plane..."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 | tee kubeadm-init.out

# Step 30-32: Configure kubectl for the current user
echo "Configuring kubectl for the current user..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel CNI plugin for pod networking
echo "Installing Flannel CNI plugin..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Print join command for worker nodes
echo "=== Installation Complete ==="
echo "To add worker nodes to this cluster, run the following command on each worker node:"
echo ""
grep -A 1 "kubeadm join" kubeadm-init.out

# Verify installation
echo "=== Verifying Installation ==="
echo "Waiting for nodes to become ready..."
sleep 30
kubectl get nodes
kubectl get pods -A

echo "=== Kubernetes Master Node Installation Completed Successfully ==="
echo "You can now use kubectl to manage your cluster."

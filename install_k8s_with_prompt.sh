#!/bin/bash
# Interactive Kubernetes setup with Rancher, Calico, cert-manager and NGINX ingress
# For domain: rancher.fardabara.com

# Function to ask for confirmation before each step
function confirm_step {
    echo -e "\n======================================================"
    echo "NEXT STEP: $1"
    echo "======================================================"
    read -p "Run this step? (yes/no): " response
    if [[ "$response" != "yes" ]]; then
        echo "Script stopped by user."
        exit 0
    fi
}

# Step 1: Set hostname
confirm_step "Set hostname to k8s-master"
sudo hostnamectl set-hostname k8s-master

# Step 2: Add hostname to /etc/hosts
confirm_step "Add hostname to /etc/hosts"
echo "$(hostname -I | awk '{print $1}') k8s-master" | sudo tee -a /etc/hosts

# Step 3: Install dependencies
confirm_step "Install dependencies"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2

# Step 4: Disable swap
confirm_step "Disable swap (required for Kubernetes)"
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Step 5: Load kernel modules
confirm_step "Load kernel modules (overlay, br_netfilter)"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Step 6: Configure sysctl settings
confirm_step "Configure sysctl settings for Kubernetes"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# Step 7: Install containerd
confirm_step "Install containerd"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y containerd.io

# Step 8: Configure containerd
confirm_step "Configure containerd"
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Step 9: Install Kubernetes components
confirm_step "Install Kubernetes components (kubelet, kubeadm, kubectl)"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Step 10: Initialize Kubernetes
confirm_step "Initialize Kubernetes cluster with kubeadm"
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --control-plane-endpoint=k8s-master

# Step 11: Set up kubeconfig
confirm_step "Set up kubeconfig in ~/.kube/config"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Step 12: Remove master node taint
confirm_step "Remove master node taint to allow scheduling pods on master"
kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane:NoSchedule-

# Step 13: Install Calico CNI
confirm_step "Install Calico CNI"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

# Step 14: Wait for Calico to be ready
confirm_step "Wait for Calico pods to be ready"
echo "Waiting for Calico pods to start..."
kubectl wait --namespace calico-system --for=condition=ready pods --selector k8s-app=calico-node --timeout=180s || echo "WARNING: Timeout waiting for Calico pods"

# Step 15: Install Helm
confirm_step "Install Helm package manager"
curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Step 16: Add Helm repositories
confirm_step "Add necessary Helm repositories"
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# Step 17: Install cert-manager
confirm_step "Install cert-manager with Helm"
kubectl create namespace cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true \
  --version v1.12.0

# Step 18: Wait for cert-manager to be ready
confirm_step "Wait for cert-manager pods to be ready"
echo "Waiting for cert-manager pods to start..."
kubectl wait --for=condition=ready pods --selector app=cert-manager --namespace cert-manager --timeout=180s || echo "WARNING: Timeout waiting for cert-manager pods"

# Step 19: Install NGINX Ingress Controller
confirm_step "Install NGINX Ingress Controller with Helm"
kubectl create namespace ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

# Step 20: Wait for NGINX ingress to be ready
confirm_step "Wait for NGINX ingress controller pods to be ready"
echo "Waiting for NGINX ingress controller pods to start..."
kubectl wait --for=condition=ready pods --selector app.kubernetes.io/component=controller --namespace ingress-nginx --timeout=180s || echo "WARNING: Timeout waiting for NGINX ingress pods"

# Step 21: Create namespace for Rancher
confirm_step "Create namespace for Rancher"
kubectl create namespace cattle-system

# Step 22: Install Rancher
confirm_step "Install Rancher with Helm"
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.fardabara.com \
  --set bootstrapPassword=admin \
  --set replicas=1 \
  --set ingress.tls.source=rancher

# Step 23: Wait for Rancher to be ready
confirm_step "Wait for Rancher to be ready (may take several minutes)"
echo "Waiting for Rancher to start..."
kubectl -n cattle-system wait --for=condition=ready pods --selector app=rancher --timeout=300s || echo "WARNING: Timeout waiting for Rancher pods"

# Step 24: Set up Let's Encrypt
confirm_step "Set up Let's Encrypt ClusterIssuer for SSL"
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: info@fardabara.com  # Change this to your email
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Step 25: Update Rancher to use Let's Encrypt
confirm_step "Update Rancher to use Let's Encrypt for SSL"
kubectl -n cattle-system patch ingress rancher --type='json' -p='[{"op": "replace", "path": "/spec/tls/0/secretName", "value": "rancher-tls-letsencrypt"}]'
kubectl -n cattle-system patch ingress rancher --type='json' -p='[{"op": "add", "path": "/metadata/annotations/cert-manager.io~1cluster-issuer", "value": "letsencrypt-prod"}]'

# Step 26: Display summary
confirm_step "Display setup summary and join command"
echo "Setup complete! Here's what's been installed:"
echo "1. Kubernetes with Calico CNI"
echo "2. Helm package manager"
echo "3. cert-manager for certificate management"
echo "4. NGINX Ingress Controller"
echo "5. Rancher at https://rancher.fardabara.com"
echo ""
echo "IMPORTANT: Make sure your DNS A record for rancher.fardabara.com points to this server's IP address in Cloudflare."
echo "Your server should be accessible from the internet for Let's Encrypt to work properly."
echo ""
echo "To create additional clusters from Rancher:"
echo "1. Access the Rancher dashboard at https://rancher.fardabara.com"
echo "2. Click 'Create Cluster'"
echo "3. Choose 'Custom' for a 3-node cluster"
echo "4. Follow the instructions provided by Rancher to add your worker nodes"
echo ""
echo "To join additional nodes to this cluster, use the following command:"
kubeadm token create --print-join-command

echo -e "\nSetup completed successfully!"

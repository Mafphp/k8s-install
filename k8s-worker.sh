#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
WORKER_NAME="k8s-worker-$(hostname | md5sum | head -c 6)"
MASTER_IP=""

# Get Master IP from user input
while [ -z "$MASTER_IP" ]; do
    echo -n "Enter Kubernetes master node IP address: "
    read MASTER_IP
    if [ -z "$MASTER_IP" ]; then
        echo "Error: Master IP cannot be empty. Please try again."
    elif ! [[ $MASTER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid IP format. Please enter a valid IP address (e.g., 192.168.1.100)."
        MASTER_IP=""
    fi
done

# Now enable command tracing after getting user input
set -x

echo "=== Starting Kubernetes Worker Node Installation ==="
echo "Worker Name: $WORKER_NAME"
echo "Master IP: $MASTER_IP"

# Step 1-2: Update and upgrade packages
echo "Updating and upgrading packages..."
sudo apt update
sudo apt-get upgrade -y

# Step 3-4: Disable swap
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Step 5-6: Set hostname
echo "Setting hostname to $WORKER_NAME..."
sudo hostnamectl set-hostname $WORKER_NAME
hostname

# Step 7: Update /etc/hosts
echo "Updating /etc/hosts..."
WORKER_IP=$(hostname -I | awk '{print $1}')
echo "$WORKER_IP $WORKER_NAME" | sudo tee -a /etc/hosts
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

# Toggle off command tracing for cleaner output
set +x

# Ask user if they want to join the cluster now
echo ""
echo "=== Worker Node Setup Complete ==="
echo "This worker node ($WORKER_NAME) is now ready to join your Kubernetes cluster."
echo ""
echo "Do you have the join command from the master node? (yes/no)"
read HAS_JOIN_COMMAND

if [[ "$HAS_JOIN_COMMAND" == "yes" || "$HAS_JOIN_COMMAND" == "y" ]]; then
    echo "Please paste the 'kubeadm join' command from the master node below:"
    read JOIN_COMMAND
    
    # Execute the join command
    echo "Executing join command..."
    eval "sudo $JOIN_COMMAND"
    
    echo ""
    echo "Join command executed. Please verify on the master node by running:"
    echo "kubectl get nodes"
else
    echo ""
    echo "To join the cluster later, you'll need to run the 'kubeadm join' command from the master node."
    echo "To generate a new join command on the master, run:"
    echo "  kubeadm token create --print-join-command"
    echo ""
    echo "After joining, verify on the master node by running:"
    echo "  kubectl get nodes"
fi

echo ""
echo "=== Worker Node Installation Completed Successfully ==="

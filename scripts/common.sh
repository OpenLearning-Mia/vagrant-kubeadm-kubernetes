#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

# Variable Declaration

# DNS Setting
if [ ! -d /etc/systemd/resolved.conf.d ]; then
	sudo mkdir /etc/systemd/resolved.conf.d/
fi
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf
[Resolve]
DNS=${DNS_SERVERS}
EOF

sudo systemctl restart systemd-resolved

# disable swap
sudo swapoff -a

# keeps the swap off during reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
sudo apt-get update -y
# Install CRI-O Runtime

VERSION="$(echo ${KUBERNETES_VERSION} | grep -oE '[0-9]+\.[0-9]+')"

# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /
EOF
cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /
EOF

curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -

sudo apt-get update
sudo apt-get install cri-o cri-o-runc -y

cat >> /etc/default/crio << EOF
${ENVIRONMENT}
EOF
sudo systemctl daemon-reload
sudo systemctl enable crio --now

echo "CRI runtime installed successfully"



# set proxy 

# 1.set APT Configuration  
cat >> /etc/apt/apt.conf << EOF
Acquire::http::proxy "http://10.0.0.4:7890/";
Acquire::https::proxy "http://10.0.0.4:7890/";
EOF
#echo "Acquire::http::proxy "http://10.0.0.4:7890/";" | sudo gedit /etc/apt/apt.conf
#echo "Acquire::https::proxy "http://10.0.0.4:7890/";" | sudo tee -a /etc/apt/apt.conf

# 2.set system Environment Variables (but no Effective immediately)
echo "export HTTP_PROXY=http://10.0.0.4:7890" | sudo tee -a /etc/environment
echo "export HTTPS_PROXY=http://10.0.0.4:7890" | sudo tee -a /etc/environment
echo "export NO_PROXY=127.0.0.1,localhost,master-node,worker-node01,worker-node02,10.0.2.0/24,172.16.1.0/16,172.17.1.0/18" | sudo tee -a /etc/environment

# 3.apply the changes(ps: did't Effective)
source /etc/environment  

# 4. set Environment Variables(Effective immediately,once)
export HTTP_PROXY=http://10.0.0.4:7890
export HTTPS_PROXY=http://10.0.0.4:7890
export NO_PROXY=127.0.0.1,localhost,master-node,worker-node01,worker-node02,10.0.2.0/24,172.16.1.0/16,172.17.1.0/18

echo "Proxy settings updated."


sudo rm -rf /etc/apt/keyrings/kubernetes-archive-keyring.gpg
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg



sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl



echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list



sudo apt-get update -y
sudo apt-get install -y kubelet="$KUBERNETES_VERSION" kubectl="$KUBERNETES_VERSION" kubeadm="$KUBERNETES_VERSION"
#sudo apt-get install -y kubelet kubectl kubeadm

sudo apt-get update -y
sudo apt-get install -y jq

local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "eth1" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
${ENVIRONMENT}
EOF

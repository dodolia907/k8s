Kubernetes/k8s setup  
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://kubernetes.io/ja/docs/setup/production-environment/container-runtimes/
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
# Control-Plane setup  
## install-control-plane  
```
## SSH into the control-plane node  
## Enter root user  
sudo su -

## Execute this shell script and command to install the Control-Plane
cd ~
wget https://raw.githubusercontent.com/dodolia907/k8s/main/install-ubuntu-cp.sh
chmod +x install-ubuntu-master.sh  
./install-ubuntu-master.sh  
export KUBECONFIG=/etc/kubernetes/admin.conf  

## configure kubelet cgroup driver
vim /etc/default/kubelet
KUBELET_EXTRA_ARGS=--cgroup-driver=systemd
systemctl daemon-reload
systemctl restart kubelet

## Open ~/.bashrc and Edit it
vim ~/.bashrc  
export KUBECONFIG=/etc/kubernetes/admin.conf

## Build the Kubernetes cluster
kubeadm init --pod-network-cidr=10.244.0.0/16
```

# Network setup (Control-Plane)  

## Install Calico
```  
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
```
## Install calicoctl
```
cd /usr/local/bin
sudo curl -L https://github.com/projectcalico/calico/releases/download/v3.24.5/calicoctl-linux-amd64 -o calicoctl
sudo chmod +x ./calicoctl
```

## Setup Calico
cd ~
mkdir manifests
cd manifests
wget https://raw.githubusercontent.com/dodolia907/k8s/main/custom-resources.yaml
wget https://raw.githubusercontent.com/dodolia907/k8s/main/ixbgp.yaml
kubectl apply -f ~/manifests/custom-resources.yaml
calicoctl apply -f ~/manifests/ixbgp.yaml
```

## Check the Calico status
```
watch kubectl get pod -A -o wide
```

# Worker Node setup
```
## SSH into the worker node
## Enter root user
sudo su -

## Execute this shell script and command to install the Worker Node
cd ~
wget https://raw.githubusercontent.com/dodolia907/k8s/main/install-ubuntu-wk.sh
chmod +x install-ubuntu-worker.sh    
./install-ubuntu-worker.sh  

## configure kubelet cgroup driver
vim /etc/default/kubelet
KUBELET_EXTRA_ARGS=--cgroup-driver=systemd
systemctl daemon-reload
systemctl restart kubelet
```

## Join the worker node to the Kubernetes cluster
```
kubeadm join ...
```

# Reset Kubernetes
## Control-plane
```
## SSH into the control-plane node
## Execute the following command with general user
sudo rm -rf ~/.kube

## Reset kubeadm with root user
sudo su -
kubeadm reset
```

## Worker node
```
## SSH into the worker node
## Reset kubeadm with root user
sudo su -
kubeadm reset
```

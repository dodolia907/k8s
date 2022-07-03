# k8s  
## Control-Plane  
```
cd /
chmod +x install-ubuntu-master.sh  
./install-ubuntu-master.sh  
export KUBECONFIG=/etc/kubernetes/admin.conf

vim ~/.bashrc

## Add the following line to ~/.bashrc
export KUBECONFIG=/etc/kubernetes/admin.conf

## Build the Kubernetes cluster
kubeadm init --control-plane-endpoint=192.168.1.181:6443 --pod-network-cidr=10.244.0.0/16
```

## Worker
```
cd /
chmod +x install-ubuntu-master.sh    
./install-ubuntu-worker.sh  

## Join the worker node to the Kubernetes cluster
kubeadm join ...
```
## Network
```  
## Install Calico
```

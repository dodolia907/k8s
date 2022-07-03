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

## Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

## Network setup  
## Install Calico
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml

cd /home/ubuntu/
wget https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml
kubectl apply -f /home/ubuntu/custom-resources.yaml
watch kubectl get pod -A -o wide
```

## Worker
```
cd /
chmod +x install-ubuntu-master.sh    
./install-ubuntu-worker.sh  

## Join the worker node to the Kubernetes cluster
kubeadm join ...
```

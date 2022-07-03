# Control-Plane  
```
cd /
chmod +x install-ubuntu-master.sh  
./install-ubuntu-master.sh  
export KUBECONFIG=/etc/kubernetes/admin.conf

vim ~/.bashrc

## Add the following line to ~/.bashrc
export KUBECONFIG=/etc/kubernetes/admin.conf

## Build the Kubernetes cluster
kubeadm init --pod-network-cidr=10.244.0.0/16

## Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

# Network setup (Control-Plane)  
```
## Install Calico  
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
```

```
## Configure Calico
cd /home/ubuntu/
wget https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml
```

Read Sample Config (written by launchpencil)  
https://github.com/launchpencil/lp-infra/blob/main/k8s/setup/calico/custom-resources.yaml
```
## edit the custom-resources.yaml file  
vim custom-resources.yaml
kubectl apply -f /home/ubuntu/custom-resources.yaml
watch kubectl get pod -A -o wide
```

# Worker
```
cd /
chmod +x install-ubuntu-worker.sh    
./install-ubuntu-worker.sh  

## Join the worker node to the Kubernetes cluster
kubeadm join ...
```

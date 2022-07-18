Kubernetes/k8s setup  
# Control-Plane setup  
## install-control-plane  
```
## SSH into the control-plane node  
## Enter root user  
sudo su -

## Execute this shell script and command to install the Control-Plane
cd /
chmod +x install-ubuntu-master.sh  
./install-ubuntu-master.sh  
export KUBECONFIG=/etc/kubernetes/admin.conf

## Open ~/.bashrc and Edit it
vim ~/.bashrc  

## Add the following line to ~/.bashrc
export KUBECONFIG=/etc/kubernetes/admin.conf

## Open /etc/default/grub and Edit it
vim /etc/default/grub

## Add the following line to /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="systemd.unified_cgroup_hierarchy=false"

## Build the Kubernetes cluster
kubeadm init --pod-network-cidr=10.244.0.0/16
```

## Configure kubectl
```
## Exit from root user  
exit

## Execute the following command with general user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

# Network setup (Control-Plane)  

## Install Calico
```  
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
```

## Configure Calico
```
cd /home/ubuntu/
wget https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml
```

Read Sample Config (written by launchpencil)  
https://github.com/launchpencil/lp-infra/blob/main/k8s/setup/calico/custom-resources.yaml  

## Edit the custom-resources.yaml file  
```
vim custom-resources.yaml
kubectl apply -f /home/ubuntu/custom-resources.yaml
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
cd /
chmod +x install-ubuntu-worker.sh    
./install-ubuntu-worker.sh  
```

## Join the worker node to the Kubernetes cluster
```
kubeadm join ...
```

# Troubleshooting
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

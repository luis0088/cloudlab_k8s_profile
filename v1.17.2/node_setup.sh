#!/bin/bash
################################################################################
#   Copyright (c) 2019 AT&T Intellectual Property.                             #
#   Copyright (c) 2019 Nokia.                                                  #
#   Copyright (c) 2019 Escuela Superior Politecnica del Litoral - ESPOL.       #
#                                                                              #
#   Licensed under the Apache License, Version 2.0 (the "License");            #
#   you may not use this file except in compliance with the License.           #
#   You may obtain a copy of the License at                                    #
#                                                                              #
#       http://www.apache.org/licenses/LICENSE-2.0                             #
#                                                                              #
#   Unless required by applicable law or agreed to in writing, software        #
#   distributed under the License is distributed on an "AS IS" BASIS,          #
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
#   See the License for the specific language governing permissions and        #
#   limitations under the License.                                             #
################################################################################
#set -u
#set -x

## Change shell for users
sudo sed -i 's/tcsh/bash/' /etc/passwd

WORKINGDIR='/mnt/extra/'
username=$(id -nu)
usergid=$(id -ng)
experimentid=$(hostname|cut -d '.' -f 2)
projectid=$usergid

sudo chown ${username}:${usergid} ${WORKINGDIR}/ -R
cd $WORKINGDIR
exec >> ${WORKINGDIR}/deploy.log
exec 2>&1

### Show K8s requested version
echo "K8s requested version = $1"

echo "Current user: $(whoami)"
echo "Current directory: $(pwd)"


KUBEHOME="${WORKINGDIR}/.kube/"
DEPLOY_CONFIG="${WORKINGDIR}/cloudlab_k8s_profile/$K8SVERSION/kube-deploy-yaml/"
mkdir -p $KUBEHOME && cd $KUBEHOME
export KUBECONFIG=$KUBEHOME/config

cd $WORKINGDIR

### Commands from RIC infra install
### ric-infra/00-Kubernetes/etc/infra.rc
# modify below for RIC infrastructure (docker-k8s-helm) component versions
INFRA_DOCKER_VERSION="18.06.1"
INFRA_K8S_VERSION="1.17.2"
INFRA_CNI_VERSION="0.7.5"


#### This is how I used to install K8s packages using the version received by the script.

##version=$(echo $(echo $K8SVERSION |sed 's/v//')-00)
##sudo apt-get install -y kubernetes-cni=0.6.0-00 golang-go jq 
##sudo apt-get install -qy kubelet=$version kubectl=$version kubeadm=$version
##sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version="$K8SVERSION" --ignore-preflight-errors='KubeletVersion'

DOCKERV="${INFRA_DOCKER_VERSION}"
KUBEV="${INFRA_K8S_VERSION}"
KUBECNIV="${INFRA_CNI_VERSION}"

KUBEVERSION="${KUBEV}-00"
CNIVERSION="${KUBECNIV}-00"
DOCKERVERSION="${DOCKERV}-0ubuntu1.2~18.04.1"

# disable swap
#SWAPFILES=$(grep swap /etc/fstab | sed '/^#/ d' |cut -f1 -d' ')
SWAPFILES=$(grep swap /etc/fstab | sed '/^#/ d' |cut -f1 )
if [ ! -z $SWAPFILES ]; then
  for SWAPFILE in $SWAPFILES
  do
    if [ ! -z $SWAPFILE ]; then
      echo "disabling swap file $SWAPFILE"
      if [[ $SWAPFILE == UUID* ]]; then
        UUID=$(echo $SWAPFILE | cut -f2 -d'=')
        sudo swapoff -U $UUID
      else
        sudo swapoff $SWAPFILE
      fi
      # edit /etc/fstab file, remove line with /swapfile
      sudo sed -i -e "/$SWAPFILE/d" /etc/fstab
    fi
  done
fi

### Install packages & configure them
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get -y update
sudo apt-get -y install software-properties-common
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list

sudo apt-get -y install   apt-transport-https  ca-certificates  curl  gnupg-agent  software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"


# install low latency kernel, docker.io, and kubernetes
sudo apt-get -y update
#### TODO instal low latency kernel
### sudo apt-get install -y linux-image-4.15.0-45-lowlatency curl jq netcat docker.io=${DOCKERVERSION}
sudo apt-get install -y curl jq netcat 
### Install docker, and change the default folder from /usr/lib/docker to /mnt/extra/docker

##TO-DO: fix the docker version
####sudo apt-get install -y docker.io=${DOCKERVERSION}
sudo apt-get -y install docker-ce docker-ce-cli containerd.io

sudo mkdir /mnt/extra/docker
sudo chown root:root /mnt/extra/docker
sudo chmod 711 /mnt/extra/docker
sudo sed -i 's/\-H fd/\-g \/mnt\/extra\/docker \-H fd/g' /lib/systemd/system/docker.service

### Install Kubernetes
sudo apt-get install -y kubernetes-cni=${CNIVERSION}
sudo apt-get install -y --allow-unauthenticated kubeadm=${KUBEVERSION} kubelet=${KUBEVERSION} kubectl=${KUBEVERSION}
sudo apt-mark hold kubernetes-cni kubelet kubeadm kubectl

### Disable AppArmor, as it doesn't allow to create MariaDB container. 
### See Troubleshooting section on https://mariadb.com/kb/en/library/installing-and-using-mariadb-via-docker/
# Not needed anymore?
#sudo apt-get purge -y --auto-remove apparmor

# Load kernel modules 
sudo modprobe -- ip_vs
sudo modprobe -- ip_vs_rr
sudo modprobe -- ip_vs_wrr
sudo modprobe -- ip_vs_sh
sudo modprobe -- nf_conntrack_ipv4
sudo modprobe -- nf_conntrack_ipv6
sudo modprobe -- nf_conntrack_proto_sctp    ### Probably will give an error, as recent versions include this as part of the Kernel.

# Restart docker and configure to start at boot
sudo service docker restart
sudo systemctl enable docker.service

# test access to k8s docker registry
sudo kubeadm config images pull


# non-master nodes have hostnames starting with s
if [[ $(hostname) == s* ]]; then
  echo "Done for non-master node"
  #echo "Starting an NC TCP server on port 29999 to indicate we are ready"
  #nc -l -p 29999 &
else 
  # below are steps for initializating master node, only run on the master node.  
  # minion node join will be triggered from the caller of the stack creation as ssh command.


  # create kubenetes config file
  if [[ ${KUBEV} == 1.17.* ]]; then
    cat <<EOF >"${WORKINGDIR}/config.yaml"
apiVersion: kubeadm.k8s.io/apps/v1
kubernetesVersion: v${KUBEV}
kind: ClusterConfiguration
apiServerExtraArgs:
  feature-gates: SCTPSupport=true
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12

---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
EOF

  else
    echo "Unsupported Kubernetes version requested.  Bail."
    exit
  fi


  # start cluster (make sure CIDR is enabled with the flag)
  ##sudo kubeadm init --config "${WORKINGDIR}/config.yaml"
  sudo kubeadm init --apiserver-advertise-address 10.10.1.1 --service-cidr 10.96.0.0/12  --pod-network-cidr 10.244.0.0/16 ### Use this to specify the Iface



  # set up kubectl credential and config
  sudo cp /etc/kubernetes/admin.conf $KUBEHOME/config
  sudo chown ${username}:${usergid} $KUBEHOME/config
  sudo chmod g+r $KUBEHOME/config

  # at this point we should be able to use kubectl
  kubectl get pods --all-namespaces

  # install flannel
  ##kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml
  kubectl apply -f kube-flannel.yaml ### Changed to specify the IFace
  kubectl apply -f create-cluster-role-binding-admin.yaml
  kubectl apply -f create-service-account-admin-uesr-dashboard.yaml


  # waiting for all 8 kube-system pods to be in running state
  # (at this point, minions have not joined yet)
###  wait_for_pods_running 8 kube-system

  # if running a single node cluster, need to enable master node to run pods
  # kubectl taint nodes --all node-role.kubernetes.io/master-

  cd "${WORKINGDIR}"
  # install RBAC for Helm
  # kubectl create -f rbac-config.yaml
	


  #echo "Starting an NC TCP server on port 29999 to indicate we are ready"
  #nc -l -p 29999 &

  echo "Done with master node setup"
fi

echo "FINISHED part copied from RIC"

#Rename script file to avoid reinstall on boot
echo "Rename script file to avoid reinstall on boot..."
cd /mnt/extra/
mv node_setup.sh node_setup.sh-old


echo "FINISHED!"

exit 0
###############
###############
###############
###############


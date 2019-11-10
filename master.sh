#!/bin/bash
#set -u
#set -x

## Change shell for users
sudo sed -i 's/tcsh/bash/' /etc/passwd

K8SVERSION=$1
#SCRIPTDIR=$(dirname "$0")
WORKINGDIR='/mnt/extra/'
username=$(id -nu)
usergid=$(id -ng)
experimentid=$(hostname|cut -d '.' -f 2)
projectid=$usergid



###--------------------
GIT_REPO=https://github.com/luis0088/cloudlab_k8s_profile.git
K8S_CNI_VERSION=0.7.5-00
DOCKER_ENGINE_VERSION=1.11.2-0~xenial

sudo apt-get -y install   apt-transport-https  ca-certificates  curl  gnupg-agent  software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

sudo add-apt-repository   "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io


###--------------------
sudo chown ${username}:${usergid} ${WORKINGDIR}/ -R
cd $WORKINGDIR
exec >> ${WORKINGDIR}/deploy.log
exec 2>&1

KUBEHOME="${WORKINGDIR}/kube/"
DEPLOY_CONFIG="${WORKINGDIR}/cloudlab-k8s-profile/$K8SVERSION/kube-deploy-yaml/"
mkdir -p $KUBEHOME && cd $KUBEHOME
export KUBECONFIG=$KUBEHOME/admin.conf

cd $WORKINGDIR
git clone $GIT_REPO

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt-get -y update
sudo apt-get -y install software-properties-common
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get -y update
sudo apt-get -y install build-essential libffi-dev python python-dev  \
python-pip automake autoconf libtool indent vim tmux ctags

# learn from this: https://blog.csdn.net/yan234280533/article/details/75136630
# more info should see: https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/
##sudo apt-get -y install  docker-engine kubelet kubeadm kubectl kubernetes-cni golang-go jq 
version=$(echo $(echo $K8SVERSION |sed 's/v//')-00)
sudo apt-get install -qy kubelet=$version kubectl=$version kubeadm=$version
#sudo apt-get -y install docker-engine=$DOCKER_ENGINE_VERSION kubernetes-cni=$K8S_CNI_VERSION golang-go jq 
sudo apt-get -y install kubernetes-cni=$K8S_CNI_VERSION golang-go jq
# Install version-specific Kubelet - Read https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl
##curl -LO https://storage.googleapis.com/kubernetes-release/release/$K8SVERSION/bin/linux/amd64/kubectl
##chmod +x ./kubectl
##sudo mv ./kubectl /usr/local/bin/kubectl

sudo docker version
sudo swapoff -a
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version="$K8SVERSION" --ignore-preflight-errors='KubeletVersion'

# result will be like:  kubeadm join 155.98.36.111:6443 --token i0peso.pzk3vriw1iz06ruj --discovery-token-ca-cert-hash sha256:19c5fdee6189106f9cb5b622872fe4ac378f275a9d2d2b6de936848215847b98

# https://github.com/kubernetes/kubernetes/issues/44665
sudo cp /etc/kubernetes/admin.conf $KUBEHOME/
sudo chown ${username}:${usergid} $KUBEHOME/admin.conf
sudo chmod g+r $KUBEHOME/admin.conf

sudo kubectl create -f $DEPLOY_CONFIG/kube-flannel-rbac.yml
sudo kubectl create -f $DEPLOY_CONFIG/kube-flannel.yml

# use this to enable autocomplete
source <(kubectl completion bash)

# kubectl get nodes --kubeconfig=${KUBEHOME}/admin.conf -s https://155.98.36.111:6443
# Install dashboard: https://github.com/kubernetes/dashboard
#sudo kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
 
# run the proxy to make the dashboard portal accessible from outside
#sudo kubectl proxy  --kubeconfig=${KUBEHOME}/admin.conf  &

# https://github.com/kubernetes/dashboard/wiki/Creating-sample-user
kubectl create -f $DEPLOY_CONFIG/create-cluster-role-binding-admin.yaml  
kubectl create -f $DEPLOY_CONFIG/create-service-account-admin-uesr-dashboard.yaml
# to print the token, use this cmd below to paste into the browser.
# kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}') |grep token: | awk '{print $2}'

# jid for json parsing.
export GOPATH=${WORKINGDIR}/go/gopath
mkdir -p $GOPATH
export PATH=$PATH:$GOPATH/bin
sudo go get -u github.com/simeji/jid/cmd/jid
sudo go build -o /usr/bin/jid github.com/simeji/jid/cmd/jid

# install helm in case we needs it.
##wget https://storage.googleapis.com/kubernetes-helm/helm-v2.9.1-linux-amd64.tar.gz
##tar xf helm-v2.9.1-linux-amd64.tar.gz
##sudo cp linux-amd64/helm /usr/local/bin/helm

#helm init
# https://docs.helm.sh/using_helm/#role-based-access-control
##kubectl create serviceaccount --namespace kube-system tiller
##kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
##kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'      
##helm init --service-account tiller --upgrade

#source <(helm completion bash)

# Wait till the slave nodes get joined and update the kubelet daemon successfully
echo "Waiting for slaves nodes..."
nodes=(`ssh -o StrictHostKeyChecking=no ${username}@ops.emulab.net "/usr/testbed/bin/node_list -p -e ${projectid},${experimentid};"`)
node_cnt=${#nodes[@]}
joined_cnt=$(( `kubectl get nodes |wc -l` - 1 ))
while [ $node_cnt -ne $joined_cnt ]
do 
    joined_cnt=$(( `kubectl get nodes |wc -l` - 1 ))
    sleep 1
done

echo "Kubernetes is ready at: http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login"

# optional address
echo "Or, another access option"
echo "kubernetes dashboard endpoint: $dashboard_endpoint"
# dashboard credential
echo "And this is the dashboard credential: $dashboard_credential"

# to know how much time it takes to instantiate everything.
echo "Finishing..."
date

#Rename script file to avoid reinstall on boot
cd /mnt/extra/
mv master.sh master.sh-old
mv slave.sh slave.sh-old
cd


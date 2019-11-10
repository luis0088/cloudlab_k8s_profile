kube_description= \
"""
This profile deploys the following components:
1. Kubernetes, multi-node clusters using kubeadm, using docker.

It takes around 5-10 minutes to complete the whole procedure.  
   Detail about kubernetes deployment please refer to [kubernetes documentation page](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/)  
   
NOTE: Be sure to update the Kubernetes version in the Geni code.

"""
kube_instruction= \
"""
After 5-10 minutes, the endpoint and credential will be printed at the tail of /mnt/extra/deploy.log.
You can also print it manually using the commands below:

```bash
    export KUBEHOME="/mnt/extra/kube/"
    export KUBECONFIG=$KUBEHOME/admin.conf
    dashboard_endpoint=`kubectl get endpoints --all-namespaces |grep dashboard|awk '{print $3}'`
    dashboard_credential=`kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}') |grep token: | awk '{print $2}'`
    
    echo "Kubernetes is ready at: http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login"

    # optional address
    echo "Or, another access option:"
    echo "kubernetes dashboard endpoint: $dashboard_endpoint"
    # dashboard credential
    echo "And this is the dashboard credential: $dashboard_credential"
```

You can find the deploy script at:  
   /mnt/extra/master.sh for master node  
   /mnt/extra/slave.sh for slave node  

The deployment log is kept at /mnt/extra/deploy.log

###Known issues
1. Using Ubuntu 18.04 although using kubernetes with the xenial source since no bionic sources are available yet.
2. Sometimes the endpoint info is not generated in the deploy.log just because at the time of running, the endpoint was not really ready yet. At that time, just wait a little bit more minutes and run the commands above.
"""


# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as pg
# Import the Emulab specific extensions.
import geni.rspec.emulab as emulab
import geni.rspec.igext as IG
import geni.rspec.pg as RSpec


git_tar_scripts= 'https://github.com/luis0088/cloudlab_k8s_profile/raw/master/cloudlab_k8s_profile.tar.gz'
# for ubuntu 16.04: 'urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU16-64-STD'
disk_image = 'urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU18-64-STD';
hardware_type = 'pc3000' 
storage_capacity = '200GB';
k8s_version = "v1.16.2";

# Create a portal object,
pc = portal.Context()

# leared this from: https://www.emulab.net/portal/show-profile.php?uuid=f6600ffd-e5a7-11e7-b179-90e2ba22fee4
pc.defineParameter("computeNodeCount", "Number of slave/compute nodes",
                   portal.ParameterType.INTEGER, 1)
params = pc.bindParameters()

# Create a Request object to start building the RSpec.
request = pc.makeRequestRSpec()


#rspec = RSpec.Request()
tour = IG.Tour()
tour.Description(IG.Tour.TEXT,kube_description)
tour.Instructions(IG.Tour.MARKDOWN,kube_instruction)
request.addTour(tour)

# Node kube-server
kube_m = request.RawPC('m')
#kube_m.hardware_type = 'd430'
kube_m.hardware_type = hardware_type

kube_m.disk_image = disk_image
kube_m.Site('Site 1')
iface0 = kube_m.addInterface('interface-0')
bs0 = kube_m.Blockstore('bs0', '/mnt/extra')
bs0.size = storage_capacity
bs0.placement = 'NONSYSVOL'
kube_m.addService(pg.Install(git_tar_scripts,'/mnt/extra/'))
kube_m.addService(pg.Execute(shell="bash", command="/mnt/extra/master.sh %s" %k8s_version))
slave_ifaces = []
for i in range(1,params.computeNodeCount+1):
    kube_s = request.RawPC('s'+str(i))
    #kube_s.hardware_type = 'd430'
    kube_s.hardware_type = hardware_type
    kube_s.disk_image = disk_image
    kube_s.Site('Site 1')
    slave_ifaces.append(kube_s.addInterface('interface-'+str(i)))
    bs = kube_s.Blockstore('bs'+str(i), '/mnt/extra')
    bs.size = storage_capacity
    bs.placement = 'NONSYSVOL'

    kube_s.addService(pg.Install(git_tar_scripts,'/mnt/extra/'))
    kube_s.addService(pg.Execute(shell="bash", command="/mnt/extra/slave.sh %s" %k8s_version))

# Link link-m
link_m = request.Link('link-0')
link_m.Site('undefined')
link_m.addInterface(iface0)
for i in range(params.computeNodeCount):
    link_m.addInterface(slave_ifaces[i])

# Print the generated rspec
pc.printRequestRSpec(request)

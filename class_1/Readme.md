# Introduction to distributed systems and Kubernetes

Start [Minikube]() `minikube start` for the local development. Validate that minikube is up and running: `minikube status` and that you can access minikube from your laptop `kubectl get nodes`. In order to explore the components of Kubernetes ssh into the Minikube VM: `minikube ssh`.

## Container 101

All these exercises expect that you are working on a Linux system. In order to run the examples just run the following steps to start minikube and ssh into it:

```
$ minikube start
$ minikube ssh
```

### Network namespaces

Inspect and playaround with network namespaces:

```bash
# Verify that there are no network namespaces
$ sudo ip netns list
# Add the network namespace test
$ sudo ip netns add test
# Verify that the new network namespace is there
$ sudo ip netns list
# or
$ ls -lah /var/run/netns/
# Show all interfaces
$ ip -o a s
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
1: lo    inet6 ::1/128 scope host \       valid_lft forever preferred_lft forever
# Show all interfaces in the new network namespace (empty list)
$ sudo nsenter --net=/var/run/netns/test ip -o a s
# Run ping inside the network namespace
$ sudo nsenter --net=/var/run/netns/test ping 8.8.8.8
```

### cgroups

First let's start a `pod` to look at (we will see later what a "Pod" actually is). You need to run this command from *your laptop*:

```
kubectl apply -f resources/cgroups_test.yml
```

We can interact with the cgroups with the systemd utils (obviously only on Linux systems with systemd which should be the majority):

```bash
# Show all default slices
$ systemctl list-units --type slice
# Show hierachy like a directory
$ systemd-cgls
# show all Kubernetes pods
$ systemd-cgls /kubepods
# Let's dig deeper and see all "besteffort" pods
$ systemd-cgls /kubepods/besteffort
# Let's see all "burstable" pods
$ systemd-cgls /kubepods/besteffort
# On your laptop you can fetcht the POodUID with: `kubectl get po nginx -o jsonpath='{.metadata.uid}'`
# look at our nginx pod use your own Pod UID
$ systemd-cgls /kubepods/pod5aaf719d-bb4d-11e8-bd46-080027e3a1c7
# You will see something similar to this
Control group /kubepods/pod5aaf719d-bb4d-11e8-bd46-080027e3a1c7:
├─ca5090b0c959c33683c308e6a505db5c0c7c8df7e8abcd990ce8e2c892fe0995 # dummy container to share namespace
│ └─4419 /pause
└─4dd0bb8f92ae00d61bde3b25fdf634e112d57853d91c1902d93b2995703ee2ce # nginx container running 2 processes
  ├─5488 nginx: master process nginx -g daemon off;
  └─5506 nginx: worker process
# Monitor usage
$ systemd-cgtop
```

### cgroups (v1) filesystem
Instead of using systemd-cgls we can also inspect the filesystem:

```bash
# Shows which resource controllers are used
$ cat /proc/cgroups
# show all resource controllers
$ ls -lah /sys/fs/cgroup/
# Show CPU limits
$ cat /sys/fs/cgroup/cpu/kubepods/pod5aaf719d-bb4d-11e8-bd46-080027e3a1c7/cpu.shares
# Show Memory limits divide the return value by 1024 / 1024
$ cat /sys/fs/cgroup/memory/kubepods/pod5aaf719d-bb4d-11e8-bd46-080027e3a1c7/memory.limit_in_bytes
134217728
```

### Layered filesystem

```bash
# Start a simple nginx with docker
$ docker run -d --name nginx --memory=128m --cpus="0.2" nginx
# let's write a file inside the container
$ docker exec -ti nginx /bin/bash -c "echo 'hello' > hello_world.txt"
# Show all mountpoints that are used
$ docker inspect nginx | jq '.[].GraphDriver'
# The merged directory container our file
$ sudo ls -lah $(docker inspect nginx | jq -r '.[].GraphDriver.Data.MergedDir')
# Also the "upperdir"
$ sudo ls -lah $(docker inspect nginx | jq -r '.[].GraphDriver.Data.UpperDir')
# Now delete the container
$ docker rm -f nginx
```

Images are also layered:

```bash
# Show all docker images on the host
docker images
# Show details about the nginc container image
docker image inspect nginx
# Show the different layers (from the build)
docker image history nginx
```

### Capabilities

The list of the default allowed capabilities for docker container can be found in the [official documentation](https://docs.docker.com/engine/reference/run/#runtime-privilege-and-linux-capabilities)

```bash
# Let's start an interactive container with nginx and no capabilities
# nginx can't start because it isn't allowed to bind to a "privileged" port (<1024)
$ docker run --rm -ti --cap-drop=NET_BIND_SERVICE nginx
2018/09/18 16:10:42 [emerg] 1#1: bind() to 0.0.0.0:80 failed (13: Permission denied)
nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)
# Let's start another container that pings the google DNS
$ docker run --rm -ti busybox ping -c 5 8.8.8.8
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: seq=0 ttl=61 time=67.317 ms
64 bytes from 8.8.8.8: seq=1 ttl=61 time=42.560 ms
64 bytes from 8.8.8.8: seq=2 ttl=61 time=73.149 ms
64 bytes from 8.8.8.8: seq=3 ttl=61 time=48.505 ms
64 bytes from 8.8.8.8: seq=4 ttl=61 time=67.259 ms

--- 8.8.8.8 ping statistics ---
5 packets transmitted, 5 packets received, 0% packet loss
round-trip min/avg/max = 42.560/59.758/73.149 ms
# Now we drop the capability to open "raw sockets"
$ docker run --rm -ti --cap-drop=NET_RAW busybox ping -c 5 8.8.8.8
PING 8.8.8.8 (8.8.8.8): 56 data bytes
ping: permission denied (are you root?)
```

There are different tools available to find out which capabilties a process actually needs.

In order to run a complete unprivileged container with docker run: `docker run -ti --cap-drop=ALL --user=nobody busybox`

### docker

Lets' start a simple nginx (web server) as docker container:

```bash
# create a simple nginx container with docker
$ docker run -d --name nginx --memory=128m --cpus="0.2" nginx
# Let's see if it is running
$ docker ps -n 1
```

Now we can inspect the network `namespace` of the container:

```bash
# Inspect the network namespace of the container
$ export NETNS=$(docker inspect nginx | jq -r '.[].NetworkSettings.SandboxKey')
# Show all interfaces in the container
$ sudo nsenter --net=${NETNS} ip a s
# Let's try to reach the nginc inside the container
$ curl http://$(docker inspect nginx | jq -r '.[].NetworkSettings.IPAddress')
# And we can see the entry for the container if we inspect the bridge
$ brctl showmacs docker0  | grep $(docker inspect nginx | jq -r '.[].NetworkSettings.MacAddress')
$ unset NETNS
# We can also compare the mount namespaces
# Count the mountpoints of the host
$ cat /proc/1/mounts | wc -l
143
# Count the mountpoints inside the container
$ cat /proc/$(docker inspect nginx | jq -r '.[].State.Pid')/mounts | wc -l
32
# $(docker inspect nginx | jq -r '.[].State.Pid') will return the PID of the nginx master process
```

We can also see the according `cgroups` settings made by docker:

```bash
# Let's see what Container ID the container has
$ CID=$(docker inspect nginx | jq -r '.[].Id')
# Now we can take a look at the cpu cgroup of the container
$ cat /sys/fs/cgroup/cpu/docker/${CID}/tasks
9119 # Master process
9155 # worker process
# We can see the same for memory
$ cat /sys/fs/cgroup/memory/docker/${CID}/tasks
134217728 # you need to divide this value again by / 1024 / 1024
$ unset {CID}
# Dockers default cgroup is under /docker
$ systemd-cgls /docker
```

## Kubernetes high-level overview

ssh agin into minikube with `minikube` and show the currenty running system components:

```bash
# Show all pods of the control-plane
$ sudo crictl pods --label=tier=control-plane
# We see that kube-proxy is missig because it is a node components
# The only component that doesn't run as pod is the kubelet:
$ systemctl status kubelet
```

### kube-proxy

Show all rules written by `kube-proxy`:

```bash
# Lists all rules of the NAT table (-t) for PREROUTING
$ sudo iptables -n -t nat -L PREROUTING
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination
KUBE-SERVICES  all  --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */
DOCKER     all  --  0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL
# Lists all rules of the NAT table for the KUBE-SERVICES chain
$ sudo iptables -n -t nat -L KUBE-SERVICES
Chain KUBE-SERVICES (2 references)
target     prot opt source               destination
KUBE-SVC-NPX46M4PTMTKRN6Y  tcp  --  0.0.0.0/0            10.96.0.1            /* default/kubernetes:https cluster IP */ tcp dpt:443
KUBE-SVC-ERIFXISQEP7F7OF4  tcp  --  0.0.0.0/0            10.96.0.10           /* kube-system/kube-dns:dns-tcp cluster IP */ tcp dpt:53
KUBE-SVC-TCOU7JCQXEZGVUNU  udp  --  0.0.0.0/0            10.96.0.10           /* kube-system/kube-dns:dns cluster IP */ udp dpt:53
KUBE-SVC-XGLOHA7QRQ3V22RZ  tcp  --  0.0.0.0/0            10.96.199.224        /* kube-system/kubernetes-dashboard: cluster IP */ tcp dpt:80
KUBE-SVC-2QFLXPI3464HMUTA  tcp  --  0.0.0.0/0            10.106.175.111       /* kube-system/default-http-backend: cluster IP */ tcp dpt:80
KUBE-NODEPORTS  all  --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service nodeports; NOTE: this must be the last rule in this chain */ ADDRTYPE match dst-type LOCAL
# Choose the service for "default/kubernetes:https" e.g. KUBE-SVC-NPX46M4PTMTKRN6Y
$ sudo iptables -n -t nat -L KUBE-SVC-NPX46M4PTMTKRN6Y
Chain KUBE-SVC-NPX46M4PTMTKRN6Y (1 references)
target     prot opt source               destination
KUBE-SEP-HXBYGASQFZQQUDTL  all  --  0.0.0.0/0            0.0.0.0/0            /* default/kubernetes:https */ recent: CHECK seconds: 10800 reap name: KUBE-SEP-HXBYGASQFZQQUDTL side: source mask: 255.255.255.255
KUBE-SEP-HXBYGASQFZQQUDTL  all  --  0.0.0.0/0            0.0.0.0/0            /* default/kubernetes:https */
# List the endpoints of this service
$ sudo iptables -n -t nat -L KUBE-SEP-HXBYGASQFZQQUDTL
Chain KUBE-SEP-HXBYGASQFZQQUDTL (2 references)
target     prot opt source               destination
KUBE-MARK-MASQ  all  --  192.168.99.100       0.0.0.0/0            /* default/kubernetes:https */
DNAT       tcp  --  0.0.0.0/0            0.0.0.0/0            /* default/kubernetes:https */ recent: SET name: KUBE-SEP-HXBYGASQFZQQUDTL side: source mask: 255.255.255.255 tcp to:192.168.99.100:8443
```

*On your laptop* you can verify these steps by running the following two command:

```bash
# Compare the cluster-ip to the iptables rule
$ kubectl get service
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   1h
# Compare the endpoints of this service to the iptables rules
$ kubectl get endpoints kubernetes
NAME         ENDPOINTS             AGE
kubernetes   192.168.99.100:8443   1h
```

You can also `curl` the API from inside `minikube`:

```bash
# We pass the -k because we don't provide the correct CA file
$ curl -k https://10.96.0.1
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {

  },
  "status": "Failure",
  "message": "forbidden: User \"system:anonymous\" cannot get path \"/\"",
  "reason": "Forbidden",
  "details": {

  },
  "code": 403
}
```

### etcd - distributed key-value store

```bash
# Start a simple etcd K/V with a single node
$ docker run -d --name etcd quay.io/coreos/etcd:v3.3
# Jump into the etcd container
$ docker exec -ti etcd /bin/sh
# Show the member list of etcd
$ etcdctl member lis
# Show the status of the cluster
$ etcdctl cluster-health
# List all entries in the etcd (returns an emtpy list)
$ etcdctl ls -r /
# Create a directory in the K/V
$ etcdctl mkdir /inovex/classes
# Create our first key/value
$ etcdctl set /inovec/classes/myvalue "hello world"
# List all directories in the K/V
$ etcdctl ls -r /
# Fetch the value out of the K/V
$ etcdctl get /inovex/classes/myvalue
# Install curl and jq for later use
$ apk --no-cache add curl jq
# version
$ curl -vv -s http://localhost:2379/version | jq '.'
# Display the complete content
# You will see the monothonic increasing index
$ curl -vv -s http://localhost:2379/v2/keys?recursive=true | jq '.'
# Create a second value
$ etcdctl set /inovex/classes/myvalue2 "bye"
# See the new indicies
$ curl -vv -s http://localhost:2379/v2/keys/inovex/classes?recursive=true | jq '.'
# Let's delete a key
$ curl -vv -XDELETE -s http://localhost:2379/v2/keys/inovex/classes/myvalue2
# See some statistice about the leader
# the follower list is empty because we run etcd as a single instance
$ curl -vv -s http://localhost:2379/v2/stats/leader | jq '.'
# And some statistics about the node self
$ curl -vv -s http://localhost:2379/v2/stats/self | jq '.'
# See some statistics about the underlying storage
$ curl -vv -s http://localhost:2379/v2/stats/store | jq '.'
# clean up
$ docker rm -f etcd
```

### Working with Kubernetes

Run the following examples from your laptop. Let's start a simple nginx server:

```bash
# We can use kubectl directly to start a new deployment
# We specify an image
# We specify an port (nginx listens per default on port 80)
# We add some labels to find our resources
# We record any changes
# We want to start 3 deployments of the nginx
$ kubectl run --image=nginx --port=80 --labels='inovex=class' --record --replicas=3 my-nginx
# Let's look at our deployment
$ kubectl get deployments
NAME       DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
my-nginx   3         3         3            3           4m
# Let's look at our ReplicaSet (these are used by the Deployment)
$ kubectl get replicaset
NAME                  DESIRED   CURRENT   READY     AGE
my-nginx-66699476fc   3         3         3         8m
# Let's take a deeper look into the ReplicaSet
$ kubectl describe rs my-nginx-66699476fc
Name:           my-nginx-66699476fc
Namespace:      default
Selector:       inovex=class,pod-template-hash=2225503297
Labels:         inovex=class
                pod-template-hash=2225503297
Annotations:    deployment.kubernetes.io/desired-replicas=3
                deployment.kubernetes.io/max-replicas=4
                deployment.kubernetes.io/revision=1
                kubernetes.io/change-cause=kubectl run my-nginx --image=nginx --port=80 --labels=inovex=class --record=true --replicas=3
Controlled By:  Deployment/my-nginx # this matches the name above
Replicas:       3 current / 3 desired # all pods are running
Pods Status:    3 Running / 0 Waiting / 0 Succeeded / 0 Failed
...
# Show all pods of the ReplicaSet
$ kubectl get pods -l inovex
NAME                        READY     STATUS    RESTARTS   AGE
my-nginx-66699476fc-27dkx   1/1       Running   0          11m
my-nginx-66699476fc-gz9wv   1/1       Running   0          11m
my-nginx-66699476fc-hj4qc   1/1       Running   0          11m
# Choose one pod and take a deeper look
$ kubectl describe pods my-nginx-66699476fc-27dkx
Name:           my-nginx-66699476fc-27dkx
Namespace:      default
Node:           minikube/10.0.2.15
Start Time:     Thu, 20 Sep 2018 13:17:49 +0200
Labels:         inovex=class
                pod-template-hash=2225503297
Annotations:    <none>
Status:         Running
IP:             172.17.0.6
Controlled By:  ReplicaSet/my-nginx-66699476fc # this matches the name from above
....
# Okay now we have 3 nginx containers runnning now what?
# Let's expose the containers to the outside of the cluster
# This command exposes the deployment my-nginx on a so-called NodePort
# The NodePort will be opend on all nodes and load balances traffic to the service
$ kubectl expose deployment my-nginx -l 'inovex=class' --port=80 --record --type=NodePort
# Let's get the NodePort of the service
$ kubectl get service my-nginx
NAME       TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
my-nginx   NodePort   10.100.91.46   <none>        80:31945/TCP   1m
# Now we can access the service from the outside of the cluster
$ curl -v http://$(minikube ip):31945
# You can also open the url in your browser, you must replace the "$(minikube ip)" with the actual value
```

### Kubernetes load balancing

```bash
# We create a new deployment with a simple go application that returns information of the container
$ kubectl run --image=johscheuer/go-webserver --port=8000 --record --replicas=3 go-webserver
# Now we can expose the containers again
$ kubectl expose deployment/go-webserver --type=NodePort
# Ensure all pods are running
# The run=go-webserver was created automatically be the run command
$ kubectl get po -l run=go-webserver
# Now we can make a request against the service
# If you are on Windows just reload your browser multiple times
# Notive that the IP address changes always (expect for localhost)
$ watch -n 0.1 curl -s http://$(minikube ip):$(kubectl get service go-webserver -o jsonpath='{.spec.ports[].nodePort}')
# Let's clean up
$ kubectl delete deployment/go-webserver service/go-webserver
```

We will take a step-by-setp look at the iptables rules.

```bash
# Lists all rules of the NAT table (-t) for PREROUTING
$ sudo iptables -n -t nat -L PREROUTING
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination
KUBE-SERVICES  all  --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */
DOCKER     all  --  0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL
# Lists all rules of the NAT table for the KUBE-SERVICES chain
# This chain identifies the according service based on the VIP + dest Port
$ sudo iptables -n -t nat -L KUBE-SERVICES | grep "default/my-nginx"
# Target chain             prot. opt. source              dest.               comment
KUBE-SVC-BEPXDJBUHFCSYIC3  tcp  --  0.0.0.0/0            10.100.91.46         /* default/my-nginx: cluster IP */ tcp dpt:80
# See what rules the target chain contains
# Take a look at the probability
# This implements simple (statistically) round robin
$ sudo iptables -n -t nat -L KUBE-SVC-BEPXDJBUHFCSYIC3
Chain KUBE-SVC-BEPXDJBUHFCSYIC3 (2 references)
target     prot opt source               destination
KUBE-SEP-W5V2GENAPEE7LUNG  all  --  0.0.0.0/0            0.0.0.0/0            /* default/my-nginx: */ statistic mode random probability 0.33332999982
KUBE-SEP-J5WBW7HEOGAHN6ZG  all  --  0.0.0.0/0            0.0.0.0/0            /* default/my-nginx: */ statistic mode random probability 0.50000000000
KUBE-SEP-3ISEOL45OIX4A7WU  all  --  0.0.0.0/0            0.0.0.0/0            /* default/my-nginx: */
# Choose ohne chain from above
$ sudo iptables -n -t nat -L KUBE-SEP-J5WBW7HEOGAHN6ZG
Chain KUBE-SEP-J5WBW7HEOGAHN6ZG (1 references)
target     prot opt source               destination
KUBE-MARK-MASQ  all  --  172.17.0.6           0.0.0.0/0            /* default/my-nginx: */ # Mark hairpin traffic (client == target) for SNAT
DNAT       tcp  --  0.0.0.0/0            0.0.0.0/0            /* default/my-nginx: */ tcp to:172.17.0.6:80 # DNAT for endpoint
```

### Update resources

```bash
# We can change the image of a deployment with a simple command
$ kubectl set image deployments/my-nginx my-nginx=nginx:1.15.3-alpine
# Now we can watch the so called rollout of the new "version"
# During the complete rollout you can still access the service
$ kubectl rollout status deployment my-nginx --watch
# We can check that the container are actually running the correct image
$ kubectl get po -o jsonpath='{.items[*].spec.containers[].image}'
```

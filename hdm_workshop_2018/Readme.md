# Introduction to Kubernetes

## Prereq.

- [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) (tested: `v0.28.2`)
- [Docker](https://docs.docker.com/install) (tested: `18.06.1-ce`)
- SSH client (`Putty`/`OpenSSH`)

## Setup Minikube

Start [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) `minikube start --kubernetes-version=v.1.13.0` for the local development. Validate that minikube is up and running: `minikube status` and that you can access minikube from your laptop `kubectl get nodes`. In order to explore the components of Kubernetes ssh into the Minikube VM: `minikube ssh`.

All inovex classes asume that you are inside of the Minikube VM. In order to be able to execute kubectl in Minikube we need to install `kubectl` and make the admin configuration available for the current user `docker`:

```bash
$ curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.13.0/bin/linux/amd64/kubectl
$ chmod +x kubectl
$ sudo mv kubectl /bin
$ mkdir -p ${HOME}/.kube
$ sudo cp /etc/kubernetes/admin.conf ${HOME}/.kube/config
$ sudo chown docker:docker ${HOME}/.kube/config
$ kubectl cluster-info
$ git clone https://github.com/johscheuer/inovex_classes
$ cd inovex_classes/hdm_workshop_2018/
```

## Kubernetes high-level overview

While `minikube ssh`-ed into your Minikube VM, show the currently running system components:

```bash
# Show all pods of the control-plane
$ sudo crictl pods --label=tier=control-plane
# We see that kubelet is missing because it is a node component
# The only component that doesn't run as pod is the kubelet:
$ systemctl status kubelet
```

## Working with Kubernetes

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
# Okay now we have 3 nginx containers running now what?
# Let's expose the containers to the outside of the cluster
# This command exposes the deployment my-nginx on a so-called NodePort
# The NodePort will be opened on all nodes and load balances traffic to the service
$ kubectl expose deployment my-nginx -l 'inovex=class' --port=80 --record --type=NodePort
# Let's get the NodePort of the service
$ kubectl get service my-nginx
NAME       TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
my-nginx   NodePort   10.100.91.46   <none>        80:31945/TCP   1m
# Now we can access the service from the outside of the cluster
# You can also open the url in your browser, you must replace 127.0.0.1 with the with the actual IP of the minikube VM
# You can get the IP address with ip -o a s eth1 (default: 192.168.99.100)
$ curl -v http://127.0.0.1:31945
# Let's clean up
$ kubectl delete deployment/my-nginx
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
# Notice that the IP address changes always (expect for localhost)
$ watch -n 0.1 curl -s http://127.0.0.1:$(kubectl get service go-webserver -o jsonpath='{.spec.ports[].nodePort}')
# Let's clean up
$ kubectl delete deployment/go-webserver service/go-webserver
```

## Kubernetes concepts

### Deployments

```bash
# We start with a simple deployment and take a look at it
$ kubectl apply  -f resources/simple.yml
deployment.apps/simple created
# Let's see if everything worked
$ kubectl get deployment simple
NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
simple    3         3         3            3           2m
# With the following command we get more information about the object
# You will see that Kubernetes uses many defaults
$ kubectl describe deployment simple
...
# Let's look at the ReplicaSet
$ kubectl get rs
NAME                DESIRED   CURRENT   READY     AGE
simple-6556df596f   3         3         3         1m
# And we can see that all pods are available
$ kubectl get pods
NAME                      READY     STATUS    RESTARTS   AGE
simple-6556df596f-kv62l   1/1       Running   0          1m
simple-6556df596f-p8s7p   1/1       Running   0          2m
simple-6556df596f-vlt77   1/1       Running   0          1m
```

### Rolling updates

```bash
# We will watch all ReplicaSets
$ watch -n 1 kubectl get rs
# Open a new Terminal in minikube
# Now we can perform an rolling update of the resource
$ kubectl set image deployments/simple simple=nginx:1.15.3-alpine
# Now we can watch the so called rollout of the new "version"
# During the complete rollout you can still access the service
$ kubectl rollout status deployment simple --watch
# We can check that the container is actually using the correct image
$ kubectl get po -o jsonpath='{.items[*].spec.containers[].image}'
```

### Labels

```bash
# What if we create a pod with the same labels like the generated ones?
$ kubectl apply -f resources/simple-pod.yml
pod/simple created
# So wat does the deployment say?
$ kubectl get deployment
NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
simple    3         3         3            3           34m
# And the ReplicaSet ?
$ kubectl get rs
NAME                DESIRED   CURRENT   READY     AGE
simple-6556df596f   0         0         0         35m
simple-7b5b886b8c   3         3         3         8m
# But thw following query returns 4 Pods?
$ kubectl get po -l app=simple
NAME                      READY     STATUS    RESTARTS   AGE
simple                    1/1       Running   0          3m
simple-7b5b886b8c-6d87l   1/1       Running   0          8m
simple-7b5b886b8c-j6f8q   1/1       Running   0          8m
simple-7b5b886b8c-mpzvk   1/1       Running   0          8m
# The reason is the selctor used by the ReplicaSet -> The requirements are ANDed
$ kubectl get rs simple-7b5b886b8c -o json | jq '.spec.selector'
{
  "matchLabels": {
    "app": "simple",
    "pod-template-hash": "3616442647"
  }
}
# So what happens if we add the pod-template-hash to our pod?
# In the first step we will fetch the template hash
$ POD_HASH=$(kubectl get rs simple-7b5b886b8c -o json | jq '.spec.selector.matchLabels."pod-template-hash"')
# Now we can create a patch file containing the new label
cat > patch.yml <<EOF
metadata:
  labels:
    pod-template-hash: ${POD_HASH}
EOF
# And now we can apply the patch to add the Pod hash to our own Po d
$ kubectl patch pod simple --patch "$(cat patch.yml)"
# You will see that our Pod will be deleted because now the ReplicaSet has 1 Pod to much
# We can also adjust the replica size with the following command
# NOTE: this command doesn't create a new ReplicaSet
$ kubectl scale deployment simple --replicas=1
# Now we can clean up
$ kubectl delete deployment simple
```

### Complete example

We will use the example Demo Stack from here: <https://github.com/johscheuer/todo-app-web>

```bash
# In the first step we clone the repository
$ git clone https://github.com/johscheuer/todo-app-web
$ cd todo-app-web
# Now we can start the demo stack
$ kubectl apply -f k8s-deployment
namespace/todo-app created
deployment.apps/redis-master created
service/redis-master created
deployment.apps/redis-slave created
service/redis-slave created
configmap/todo-app-config created
deployment.apps/todo-app created
service/todo-app created
# Let's see if all resources came up
$ kubectl -n todo-app get po
NAME                            READY     STATUS    RESTARTS   AGE
redis-master-7f96566d4d-s8zrp   1/1       Running   0          41s
redis-slave-6cfb4497f8-nvmtt    1/1       Running   0          41s
redis-slave-6cfb4497f8-t4gj5    1/1       Running   0          41s
todo-app-85496f5c55-2wwcx       1/1       Running   0          41s
todo-app-85496f5c55-526n8       1/1       Running   0          41s
todo-app-85496f5c55-8nzx6       1/1       Running   0          41s
# Take some time and look in each components and how they interact
# Let's see all the services
# Use the minikube IP (192.168.99.100) and the NodePort in my example 31299 to access the ToDo app
$ kubectl -n todo-app get svc
NAME           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
redis-master   ClusterIP   10.111.233.59    <none>        6379/TCP       2m
redis-slave    ClusterIP   10.108.195.28    <none>        6379/TCP       2m
todo-app       NodePort    10.110.174.222   <none>        80:31299/TCP   2m
# Now we can demonstrate an rolling update
# In the first step we watch the version of the Pod
# Or in your Browser with 192.168.99.100
$ watch -n 0.1 curl -s http://127.0.0.1:31299/version
# Now we deploy a new version of our todo-app
$ kubectl -n todo-app set image deployments/todo-app todo-app=johscheuer/todo-app-web:dog
# During the roll out the application is still available
# You can also check the application in your Browser
```

## Auto Scaling

In order to use Auto Scaling we need to enable the [Metrics Server](https://github.com/kubernetes-incubator/metrics-server):

```bash
# If we don't install the metrics server we get the following error message
$ kubectl top nodes
Error from server (NotFound): the server could not find the requested resource (get services http:heapster:)
# So let's activate the metrics server
$ minikube addons enable metrics-server
# Now we can ask Kubernetes for some metrics
$ kubectl top node
error: metrics not available yet
# We need to wait until the metrics server has collected some metrics
$ kubectl top node
NAME       CPU(cores)   CPU%      MEMORY(bytes)   MEMORY%
minikube   527m         26%       1029Mi          26%
# The command also works for pods
$ kubectl top pods --all-namespaces
NAMESPACE     NAME                                        CPU(cores)   MEMORY(bytes)
kube-system   default-http-backend-59868b7dd6-g22sh       0m           1Mi
kube-system   etcd-minikube                               45m          30Mi
kube-system   kube-addon-manager-minikube                 19m          2Mi
kube-system   kube-apiserver-minikube                     160m         389Mi
kube-system   kube-controller-manager-minikube            85m          34Mi
kube-system   kube-dns-86f4d74b45-hsvqp                   8m           24Mi
kube-system   kube-proxy-rjm7z                            6m           11Mi
kube-system   kube-scheduler-minikube                     21m          11Mi
kube-system   kubernetes-dashboard-5498ccf677-2gzwn       24m          16Mi
kube-system   metrics-server-85c979995f-wsnqj             1m           9Mi
kube-system   nginx-ingress-controller-5984b97644-nwqpn   6m           55Mi
kube-system   storage-provisioner                         0m           13Mi
# We can also take a look at the Kubernetes Dashboard
$ minikube dashboard
```

Now we take a look again at our Demo Stack:

```bash
# What are the metrics for our demo app?
$ kubectl -n todo-app top po
NAME                            CPU(cores)   MEMORY(bytes)
redis-master-7f96566d4d-f94d4   2m           1Mi
redis-slave-6cfb4497f8-m8lmt    1m           1Mi
redis-slave-6cfb4497f8-q4nq9    2m           1Mi
todo-app-85496f5c55-4nwkq       1m           4Mi
todo-app-85496f5c55-9tvg5       0m           4Mi
todo-app-85496f5c55-hz5rw       1m           4Mi
# Okay, let's create an auto scaler
$ kubectl -n todo-app autoscale deployment todo-app --min=1 --max=10 --cpu-percent=40
horizontalpodautoscaler.autoscaling/todo-app autoscaled
# Let's look at the auto scaler
$ kubectl -n todo-app get hpa
NAME       REFERENCE             TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
todo-app   Deployment/todo-app   1%/40%    1         10        1          8m
# We can already see that the HPA has reduced the number of Pods
$ kubectl -n todo-app get po -l name=todo-app
# Let's make some noise
# Install vegeta --> https://github.com/tsenart/vegeta
# You need to adjust the nodeport --> kubectl get -n todo-ap service todo-ap -o jsonpath='{.spec.ports[].nodePort}' --> toDo
# Or externally with 192.168.99.100
$ echo GET http://127.0.0.1:32020 | vegeta attack -rate=75/s --duration=5m  | vegeta encode > results.json
# In another Terminal watch the HPA
# The actual auto-scaling takes a while
# After the load test the HPA will scale down the replicas again
$ kubectl -n todo-app get hpa -w
```

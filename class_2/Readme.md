# Kubernetes concepts

In the following steps we will use `minikube` to deploy and inspect the Kubernetes concepts:

```bash
$ cd class_2
$ minikube start --memory=4096
```

## Deployments

```bash
# We start with a simple deployment and take a look at it
$ kubectl apply  -f resources/simple.yml
deployment.apps/simple created
# Let's see if everything worked
$ kubectl get deployment simple
NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
simple    1         1         1            1           4s
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
$ kubectl apply  -f resources/simple-pod.yml
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

## Complete example

We will use the example Demo Stack from here: https://github.com/johscheuer/todo-app-web

```bash
# In the first step we clone the repo
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
$ watch -n 0.1 curl -s http://192.168.99.100:31299/version
# Now we deploy a new version of our todo-app
$ kubectl -n todo-app set image deployments/todo-app todo-app=johscheuer/todo-app-web:dog
# During the roll out the application is still available
# You can also check the application in your Browser
```

### Auto Scaling

In order to use Auto Sclaing we need to enable the [Metrics Server](https://github.com/kubernetes-incubator/metrics-server):

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
NAME       REFERENCE             TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
todo-app   Deployment/todo-app   1%/40%    1         10        1          8m
# We can already see that the HPA has reduced the number of Pods
$ kubectl -n todo-app get po -l name=todo-app
# Let's make some noise
# Install vegeta --> https://github.com/tsenart/vegeta
$ echo GET http://192.168.99.100:32671 | vegeta attack -rate=200/s --duration=5m  | vegeta encode > results.json
# In another Terminal watch the HPA
# The actual auto-scaling takes a while
# After the load test the HPA will scale down the replicas again
$ kubectl -n todo-app get hpa -w
```

# Kubernetes Volumes

In the following steps we will use `minikube` to deploy and inspect the Kubernetes concepts:

```bash
$ cd class_3
$ minikube start --memory=4096
```

## Shared Volumes

We can use Kubernetes volumes to share state between to containers inside a Pod:

```bash
# We create a Pod that contains 2 containers that share the same volume
$ kubectl apply  -f resources/shared_state.yml
pod/shared-state created
# Wait until the Pod becomes ready
$ kubectl get po
NAME           READY   STATUS    RESTARTS   AGE
shared-state   2/2     Running   0          42s
# Now we can create a file inside the shared directory
$ kubectl exec -ti shared-state -c fetcher -- /bin/sh
$ echo "Hello World" > hello_world.txt
$ ls -lah
total 4
drwxrwxrwt    2 root     root          60 Oct  4 06:58 .
drwxr-xr-x    1 root     root        4.0K Oct  4 06:40 ..
-rw-r--r--    1 root     root          12 Oct  4 07:01 hello_world.txt
# Quit the current session in the fetcher container
$ exit
# Now we can check that the server container can read the shared content
$ kubectl exec -ti shared-state -c server -- /bin/cat hello_world.txt
Hello World
# Clean up
$ kubectl delete pod shared-state
pod "shared-state" deleted
```

## Dynamic Provisioning

In this example we will create dynamically an `Persistent Volume`

```bash
# Start with the creation of the PVC
$ kubectl apply -f resources/pvc-demo.yml
persistentvolumeclaim/pvc-demo created
# Validate that the PVC was created
$ kubectl get pvc
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-demo   Bound    pvc-c40b0e67-c7a5-11e8-8937-0800273864a8   2Gi        RWO            standard       3s
# Check the newly created volume
# The name matches the volume name from above
$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   REASON   AGE
pvc-c40b0e67-c7a5-11e8-8937-0800273864a8   2Gi        RWO            Delete           Bound    default/pvc-demo   standard                1m
# When creating a PVC Kubernetes will use the default StorageClass (must be configured by the platform team)
# In a real cluster you could have multiple storage classes for different needs (e.g. SSD vs. HDD)
$ kubectl get storageclass
NAME                 PROVISIONER                AGE
standard (default)   k8s.io/minikube-hostpath   1h
# Minikube uses a custom Storage Provisoner
$ kubectl -n kube-system get po storage-provisioner
# In the Minikube VM run the following command
# You can see, that the minikube storage provisioner stores all data in the TMPFS (RAM)
$ ls -lah /tmp/hostpath-provisioner/
total 8.0K
drwxr-xr-x  3 root root 4.0K Oct  4 07:19 .
drwxrwxrwt 11 root root  380 Oct  4 07:25 ..
drwxrwxrwx  2 root root 4.0K Oct  4 07:19 pvc-c40b0e67-c7a5-11e8-8937-0800273864a8
# Now we start a Deployment that uses the PVC
$ kubectl apply -f resources/pvc-deployment.yml
deployment.apps/pvc-demo created
# We can see the Mount events in the pod
$ kubectl describe po -l app=pvc-demo
...
Events:
  Type    Reason                 Age    From               Message
  ----    ------                 ----   ----               -------
  Normal  Scheduled              3m56s  default-scheduler  Successfully assigned pvc-demo-56c7cf5fc4-pqp7l to minikube
  Normal  SuccessfulMountVolume  3m56s  kubelet, minikube  MountVolume.SetUp succeeded for volume "pvc-c40b0e67-c7a5-11e8-8937-0800273864a8"
  Normal  SuccessfulMountVolume  3m56s  kubelet, minikube  MountVolume.SetUp succeeded for volume "default-token-dn8h5"
  Normal  Pulling                3m55s  kubelet, minikube  pulling image "ubuntu:18.04"
  Normal  Pulled                 3m46s  kubelet, minikube  Successfully pulled image "ubuntu:18.04"
  Normal  Created                3m46s  kubelet, minikube  Created container
  Normal  Started                3m46s  kubelet, minikube  Started container
# In the first step we fetch the pod name
$ POD_NAME=$(kubectl get po -l app=pvc-demo -o jsonpath='{.items[*].metadata.name}')
# Now we can jump into the container and look if everything works as expected
$ kubectl exec -ti ${POD_NAME} -- /bin/cat /pvc/my_file
...
Thu Oct 4 07:39:45 UTC 2018
# And on the Minikube node we can also confirm the content
# Replace the <pvc-c40b0e67-c7a5-11e8-8937-0800273864a8> with your Volume UUID
$ cat /tmp/hostpath-provisioner/pvc-c40b0e67-c7a5-11e8-8937-0800273864a8/my_file
# Clean up
$ kubectl delete -f resources/pvc-deployment.yml
$ kubectl delete -f resources/pvc-demo.yml
# On Minikube we can confirm that all data is delete
$ ls -lah /tmp/hostpath-provisioner/
total 4.0K
drwxr-xr-x  2 root root 4.0K Oct  4 07:43 .
drwxrwxrwt 11 root root  380 Oct  4 07:43 ..
```

## Secrets

Secrets can be used to share confidential information (per default secrets are not encrypted at rest).

```bash
# Secrets can simply created with kubectl (from literals or files)
# If we want to use a yaml file for secrets we need to do the base64 decoding by ourself
$ kubectl create secret generic demo-secret --from-literal=username='demo' --from-literal=password='secret'
# Let's show all secrets
$ kubectl get secret
NAME                  TYPE                                  DATA   AGE
default-token-dn8h5   kubernetes.io/service-account-token   3      1h
demo-secret           Opaque                                2      4s
# Take a deeper look at our created secret
$ kubectl get secret demo-secret -o yaml
apiVersion: v1
data:
  password: c2VjcmV0 # base64 decoded
  username: ZGVtbw==
kind: Secret
metadata:
  creationTimestamp: 2018-10-04T07:48:46Z
  name: demo-secret
  namespace: default
  resourceVersion: "7580"
  selfLink: /api/v1/namespaces/default/secrets/demo-secret
  uid: ec6d0f98-c7a9-11e8-8937-0800273864a8
type: Opaque
# In order to "read" your secrets we need to decode it
# Depending on your platform use `-d` or `-D`
$ kubectl get secret demo-secret -o jsonpath='{.data.password}' | base64 -D
secret%
# Now let's use the secret in a Pod
$ kubectl apply -f resources/secret-pod.yml
pod/secret-pod created
# See if the pod is running
$ kubectl get po -l app=secret-demo
NAME         READY   STATUS    RESTARTS   AGE
secret-pod   1/1     Running   0          16s
# And let's see what events are created
$ kubectl describe po -l app=secret-demo
Events:
  Type    Reason                 Age   From               Message
  ----    ------                 ----  ----               -------
  Normal  Scheduled              64s   default-scheduler  Successfully assigned secret-pod to minikube
  Normal  SuccessfulMountVolume  64s   kubelet, minikube  MountVolume.SetUp succeeded for volume "default-token-dn8h5"
  Normal  SuccessfulMountVolume  64s   kubelet, minikube  MountVolume.SetUp succeeded for volume "secret-volume"
  Normal  Pulling                63s   kubelet, minikube  pulling image "nginx"
  Normal  Pulled                 61s   kubelet, minikube  Successfully pulled image "nginx"
  Normal  Created                61s   kubelet, minikube  Created container
  Normal  Started                61s   kubelet, minikube  Started container
# and let's see if the container can access the secrets
$ kubectl exec -ti secret-pod -- /bin/bash -c 'ls -lah /etc/secret-volume'
total 4.0K
drwxrwxrwt 3 root root  120 Oct  4 07:59 .
drwxr-xr-x 1 root root 4.0K Oct  4 07:59 ..
drwxr-xr-x 2 root root   80 Oct  4 07:59 ..2018_10_04_07_59_20.233425686
lrwxrwxrwx 1 root root   31 Oct  4 07:59 ..data -> ..2018_10_04_07_59_20.233425686
lrwxrwxrwx 1 root root   15 Oct  4 07:59 password -> ..data/password
lrwxrwxrwx 1 root root   15 Oct  4 07:59 username -> ..data/username
# Now we can also read directly a secret
$ kubectl exec -ti secret-pod -- /bin/bash -c 'cat /etc/secret-volume/password'
secret%
# Clean up
$ kubectl delete -f resources/secret-pod.yml
```

### Envrionment Variable

In the example above we have seen how to mount secrets as files inside a container but we can also pass environment variables:

```bash
# Let's create a Pod that consumes the secret as environment variable
$ kubectl apply -f resources/secret-pod-env.yml
pod/secret-pod created
# See if the pod is running
$ kubectl get po secret-pod
NAME         READY   STATUS    RESTARTS   AGE
secret-pod   1/1     Running   0          2m
# See if the secret variables are in place
$ kubectl exec -ti secret-pod -- printenv
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOSTNAME=secret-pod
TERM=xterm
SECRET_USERNAME=demo
SECRET_PASSWORD=secret
KUBERNETES_SERVICE_PORT=443
KUBERNETES_SERVICE_PORT_HTTPS=443
KUBERNETES_PORT=tcp://10.96.0.1:443
KUBERNETES_PORT_443_TCP=tcp://10.96.0.1:443
KUBERNETES_PORT_443_TCP_PROTO=tcp
KUBERNETES_PORT_443_TCP_PORT=443
KUBERNETES_PORT_443_TCP_ADDR=10.96.0.1
KUBERNETES_SERVICE_HOST=10.96.0.1
NGINX_VERSION=1.15.5-1~stretch
NJS_VERSION=1.15.5.0.2.4-1~stretch
HOME=/root
# Clean up
$ kubectl delete -f resources/secret-pod-env.yml
...
$ kubectl delete secret demo-secret
secret "demo-secret" deleted
```

## ConfigMaps

`ConfigMaps` are similar to `Secrets` but they expected to not contain confidential information. For more example see: https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap

## Downward API

The `Downward API` allows to inject information about the Pod at runtime.

```bash
# Create a Pod that uses the Downward API
$ kubectl apply -f resources/dapi-pod.yml
pod/dapi-pod created
# See the logs of the Pod
$ kubectl logs -f dapi-pod
# Abort with strg+c
```

**Task 1**: Adjust the [Pod Spec](./resources/dapi-pod.yml) to include the resource limits and requests as env. variables. Hint take a look at the [docs](https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/#use-container-fields-as-values-for-environment-variables). In order to replace the old pod use `kubectl replace --force -f resources/dapi-pod.yml`.

**Task 2**: Adjust the [Pod Spec](./resources/dapi-pod.yml) to include the Pod labels as env. variables.

# Ingress

Ensure that minikube has the `Ingress` addon enabled: `minikube addons enable ingress`

```bash
# We start two deployments one for nginx and one for apache
# Start the nginx deployment
$ kubectl run --image=nginx:1.15.5-alpine nginx -l app=nginx --expose --port=80 --replicas=2
service/nginx created
deployment.apps/nginx created
# Start the apache deployment
$ kubectl run --image=httpd:2.4.35-alpine httpd -l app=httpd --expose --port=80 --replicas=2
service/httpd created
deployment.apps/httpd created
# Check the deployments
$ kubectl get deployment
NAME    DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
httpd   2         2         2            0           9s
nginx   2         2         2            2           3m
# And check the pods
$ kubectl get po
NAME                     READY   STATUS        RESTARTS   AGE
httpd-6b88ddb654-dnwkt   1/1     Running       0          47s
httpd-6b88ddb654-vwp7k   1/1     Running       0          47s
nginx-77f98d94b8-cxg8h   1/1     Running       0          4m
nginx-77f98d94b8-vpx9n   1/1     Running       0          4m
# Validate the services
$ kubectl get svc
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
httpd        ClusterIP   10.106.68.252   <none>        80/TCP    1m
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   2h
nginx        ClusterIP   10.108.77.200   <none>        80/TCP    4m
# Check the connection with port-foward
$ kubectl port-forward svc/httpd 080:80
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
Handling connection for 8080
# Do the same for a nginx service
$ kubectl port-forward  svc/nginx  8080:80
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
Handling connection for 8080
```

## Using ingress

```bash
# We create a simple ingress
$ kubectl apply -f resources/ing-path.yml
ingress.extensions/demo-ingress created
# Show the ingress
$ kubectl get ingress
NAME           HOSTS   ADDRESS     PORTS   AGE
demo-ingress   *       10.0.2.15   80      1m
# See what happens when we curl it
$ curl http://192.168.99.100
default backend - 404
# and the specific path
$ curl http://192.168.99.100/nginx
<html>
<head><title>308 Permanent Redirect</title></head>
<body bgcolor="white">
<center><h1>308 Permanent Redirect</h1></center>
<hr><center>nginx/1.13.12</center>
</body>
</html>
# With describe you get even more information
$ kubectl describe ingress
# Clean up
$ kubectl delete deployment nginx httpd
deployment.extensions "nginx" deleted
deployment.extensions "httpd" deleted
$ kubectl delete service nginx httpd
service "nginx" deleted
service "httpd" deleted
```

**Task 1**: Rewrite the ingress resource to use [name based virtual hosting](https://kubernetes.io/docs/concepts/services-networking/ingress/#name-based-virtual-hosting). Hint: use `curl -H "HOST: httpd.foo.com" http://192.168.99.100` to specify the host in your curl command.

# Prometheus (Monitoring)

```bash
# We need to set the correct RBAC rules, this allows Prometheus to scrape things in the cluster
$ kubectl apply -f https://raw.githubusercontent.com/inovex/trovilo/master/examples/k8s/rbac-setup.yml
# Obviously we need to deploy Prometheus itself (and the configuration)
$ kubectl apply -f kubectl apply -f resources/prometheus.yml
# Now we can check prometheus
# You can also create an ingress resource for Prometheus :)
$ kubectl port-forward deployment/prometheus 9090:9090
Forwarding from 127.0.0.1:9090 -> 9090
Forwarding from [::1]:9090 -> 9090
# Go to status -> targets
# After some time you should see that everything get's green
```

## Todo App

We will start the todo-app to scrape metrics from the pods:

```bash
# In the first step we clone the repo
$ git clone https://github.com/johscheuer/todo-app-web
# Now we can start the demo stack
$ kubectl apply -f todo-app-web/k8s-deployment
namespace/todo-app created
deployment.apps/redis-master created
service/redis-master created
deployment.apps/redis-slave created
service/redis-slave created
configmap/todo-app-config created
deployment.apps/todo-app created
service/todo-app created
# Wait a little bit until the apps are discoverd
# Now inspect the metrics exposed by the application
```

## Grafana

[Grafana](https://grafana.com) is a popular solution to visualize Prometheus metrics (or other metrics)

```bash
# In order to have enough resources we scale down the todo app
$ kubectl -n todo-app scale deployment redis-slave --replicas=1
$ kubectl -n todo-app scale deployment todo-app --replicas=1
...
# Now we can deploy Grafana
$ kubectl apply -f resources/grafana.yml
...
# Wait until the Pod is ready, now you can port-forward to Grafana
$ kubectl port-forward deployment/grafana 3000:3000
```

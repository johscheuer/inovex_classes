# inovex classes

## Prereq.

- [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) (tested: `v0.28.2`)
- [Docker](https://docs.docker.com/install) (tested: `18.06.1-ce`)
- SSH client (`Putty`/`OpenSSH`)

### Setup Minikube

All inovex classes asume that you are inside of the Minikube VM. In order to be able to execute kubectl in Minikube we need to install `kubectl` and make the admin configuration available for the current user `docker`:

```bash
$ curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.11.3/bin/linux/amd64/kubectl
$ chmod +x kubectl
$ sudo mv kubectl /bin
$ export KUBECONFIG=/etc/kubernetes/admin.conf
$ sudo chown docker:docker /etc/kubernetes/admin.conf
$ kubectl cluster-info
```

## Classes

- [class_1](./class_1)
- [class_2](./class_2)
- [class_3](./class_3)

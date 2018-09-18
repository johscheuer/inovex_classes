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

First let's start a `pod` to look at (we will see later what a "Pod" actually is):

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
# look at our nginx pod use your own pod ID
# TODO fetch pod ID
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
# TODO
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
# $(docker inspect nginx | jq -r '.[].State.Pid') will return the PID of the nginx mater process
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

TODO

## etcd - distributed key-value store

### Consensus

### Two gerneals' problem

### Reality

## Practical part

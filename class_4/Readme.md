# Build your own (micro) service

In the following steps we will use `minikube` to deploy and inspect the Kubernetes concepts:

```bash
$ cd class_3
$ minikube start --memory=4096
```

## Use Minikube as local development environment

```bash
# Set to context to the docker daemon running in the minikube VM
# In Powershell: minikube docker-env | Invoke-Expression
# Official docs: https://kubernetes.io/docs/tutorials/hello-minikube/#create-a-docker-container-image
$ eval $(minikube docker-env)
# Ensure we can user the docker client from our machine to access the "remote" daemon
$ docker images
REPOSITORY                                                       TAG                 IMAGE ID            CREATED             SIZE
johscheuer/gowiki                                                v1                  59ea54e51ae6        7 seconds ago       93.6MB
...
```

## Install Golang

Follow the official documentation to install [golang](https://golang.org/doc/install). Verify the installation with `go version`. In order to use golang we need to define the [GOPATH](https://github.com/golang/go/wiki/GOPATH).

```bash
# Create a local directory for the gopath
$ mkdir gopath
# Set the environment variable
$ export GOPATH=$(pwd)/gopath
# Validate it
$ go env GOPATH
.../inovex-classes/class_4/gopath
# Now we can create the directory for our application
mkdir -p  $GOPATH/src/github.com/johscheuer/gowiki
# And go into this directory
cd $GOPATH/src/github.com/johscheuer/gowiki
```
## Minimal Wiki Web Server

Follow the article describe here: https://golang.org/doc/articles/wiki/

## Create a Docker file

Starting with a very simple Dockerfile that includes our new created Wiki. Create a file called `Dockerfile` in the same directory as your golang code:


```docker
# Base image
FROM ubuntu:18.04
# Create a new folder and a new user
RUN mkdir /app && \
    useradd --no-create-home --system --shell /sbin/nologin app
# Use the newly created user as default user
USER app
# Change the working directory
WORKDIR /app
# Copy all file from gowiki into the container
COPY . /app
# Execute the gowiki binary on start
CMD ["./gowiki"]
```

Now we can build the Docker image:

```bash
$ docker build -t johscheuer/gowiki:v1
Sending build context to Docker daemon  9.096MB
Step 1/6 : FROM ubuntu:18.04
 ---> cd6d8154f1e1
Step 2/6 : RUN mkdir /app &&     useradd --no-create-home --system --shell /bin/false app
 ---> Running in ccb30eae988f
Removing intermediate container ccb30eae988f
 ---> f1b42046f86c
Step 3/6 : USER app
 ---> Running in d219580ff1ae
Removing intermediate container d219580ff1ae
 ---> e62f0ce44d3c
Step 4/6 : WORKDIR /app
Removing intermediate container 8aa45b558935
 ---> 98de9c3ea95e
Step 5/6 : COPY . /app
 ---> 953fdb12b0a9
Step 6/6 : CMD ["./gowiki"]
 ---> Running in 23b1bf468543
Removing intermediate container 23b1bf468543
 ---> e1d9bf73a551
Successfully built e1d9bf73a551
Successfully tagged johscheuer/gowiki:v1
```

Now we can start a container from the container image. You will see the following output if you run MacOS or Windows:

```bash
$ docker run -ti johscheuer/gowiki:v1
standard_init_linux.go:195: exec user process caused "exec format error"
```

What happend here? We compiled the binary for our platform which is obviously not compatible with Linux. We can fix this simply by telling the go compiler what's your platform:

```bash
# GOOS tells the platform to complie for
# go env will print all current go env variables
$ GOOS=linux go build -o gowiki .
```

Build the container image again (notice that this time it builds much faster). Now we can start our wiki: `docker run --rm -ti -p 8080:8080 --name gowiki johscheuer/gowiki:v1` now you can access http://192.168.99.100:8080/edit/ANewPage in your Browser.


You will get an `open ANewPage.txt: permission denied` error when you try to save the file. Why? To debug our error we jump into the running container: `docker exec -ti gowiki /bin/bash`. **NOTE**: in the Dockerfile we specified for the user [/sbin/nologin](https://www.cyberciti.biz/tips/howto-linux-shell-restricting-access.html) which prevents a shell login for the user but we are still able to connect over the docker commands.

```bash
# Let's see if we can manually create a file
app@098628e8e72e:/app$ touch test.txt
touch: cannot touch 'test.txt': Permission denied
# Can we write to /tmp ?
app@098628e8e72e:/app$ touch /tmp/test.txt
# Yes we can! So let's look at the permissions
# The directory is only writeable by root
app@098628e8e72e:/app$ ls -lah
total 8.8M
drwxr-xr-x  2 root root 4.0K Oct 18 11:36 .
drwxr-xr-x 38 root root 4.0K Oct 18 11:41 ..
-rw-r--r--  1 root root  217 Oct 18 11:23 edit.html
-rwxr-xr-x  1 root root 8.7M Oct 18 11:32 gowiki
-rw-r--r--  1 root root 2.2K Oct 18 11:24 main.go
-rw-r--r--  1 root root  100 Oct 18 11:24 view.html
app@098628e8e72e:/app$ exit
exit
```

Jump as root into the container and solve Task 1: `docker exec --user root -ti gowiki /bin/bash`

- **Task 1**: Fix the Dockerfile and make the `/app` directory writable by the user `add`. Hint: https://linux.die.net/man/1/chown or https://linux.die.net/man/1/chmod
- **Task 2**: If you stop the container and create a new instance you will get the same error again. So correct the Dockerfile to include your change.

## Deploy it manually

Review the last classes and create the following:

- An Kubernetes descriptor for a Deployment running the gowiki with 1 replica
- An Kubernetes descriptor that creates an service for the gowiki
- An Kubernetes descriptor for an ingress resource for gowiki

**HINT** you can use `kubectl run --image johscheuer/gowiki:v1 --expose --port 8080 --replicas 1 -o yaml --dry-run --image-pull-policy=Always gowiki` for a skeleton.

Apply all changes in your cluster and validate that the Wiki is available under https://192.168.99.100/view/ANewPage.

What happens when you scale up the replicas to 2 (hint reload your webpage multiple times)?

```bash
$ kubectl scale deployment gowiki --replicas=2
deployment.extensions/gowiki scaled
$ kubectl get po -l run=gowiki
NAME                      READY   STATUS    RESTARTS   AGE
gowiki-76cdc69876-6zt5d   1/1     Running   0          27s
gowiki-76cdc69876-qlwj7   1/1     Running   0          2m
```

So to actually make this application scalable we need to share somehow the state of the application. Some ideas? Maybe in the next class :)

Let's scale down to one pod again: `kubectl scale deployment gowiki --replicas=1`

## Use Docker mutli-stage builds

Docker supports so called multitage builds: https://docs.docker.com/develop/develop-images/multistage-build this allows you to combine a build container and an actuall application container in one Dockerfile. Why ~~is~~ could this be  useful?

Starting with the golang build part:

```docker
# Use golang 1.11.1
FROM golang:1.11.1-stretch as builder
# Set the working directory
WORKDIR /go/src/github.com/johscheuer/gowiki/
# Copy our sourcefile
COPY ./main.go .
# And build the binary
RUN GOOS=linux go build -o gowiki .
```

Test if `docker build -t johscheuer/gowiki:v1 .` still works.

Now we can put it together with the solution from above:

```docker
# Use golang 1.11.1
FROM golang:1.11.1-stretch as builder
# Set the working directory
WORKDIR /go/src/github.com/johscheuer/gowiki/
# Copy our sourcefile
COPY ./main.go .
# And build the binary
RUN GOOS=linux go build -o gowiki .

### Application container image
FROM ubuntu:18.04
# Don't forget to apply your patch from above
RUN mkdir /app && \
    echo "/sbin/nologin" >> /etc/shells && \
    useradd --no-create-home --system --shell /sbin/nologin app
USER app
WORKDIR /app
# Copy the binary from the builder container
COPY --from=builder /go/src/github.com/johscheuer/gowiki/gowiki .
# Also copy the html files from the host
COPY ./edit.html ./view.html /app/
CMD ["./gowiki"]
```

Build the image in a new version:

```bash
$ docker build -t johscheuer/gowiki:v2 .
Sending build context to Docker daemon  9.132MB
Step 1/11 : FROM golang:1.11.1-stretch as builder
 ---> 45e48f60e268
Step 2/11 : WORKDIR /go/src/github.com/johscheuer/gowiki/
 ---> Using cache
 ---> 29a4af53731d
Step 3/11 : COPY ./gowiki/main.go .
 ---> Using cache
 ---> efd0c94637e4
Step 4/11 : RUN GOOS=linux go build -o gowiki .
 ---> Using cache
 ---> 5cfc19a1e690
Step 5/11 : FROM ubuntu:18.04
 ---> cd6d8154f1e1
Step 6/11 : RUN mkdir /app &&     echo "/sbin/nologin" >> /etc/shells &&     useradd --no-create-home --system --shell /sbin/nologin app
 ---> Using cache
 ---> d9cd9bd68755
Step 7/11 : USER app
 ---> Using cache
 ---> 5c499a317403
Step 8/11 : WORKDIR /app
 ---> Using cache
 ---> 0b1c3cfe4c2d
Step 9/11 : COPY --from=builder /go/src/github.com/johscheuer/gowiki/gowiki .
 ---> Using cache
 ---> bc602d59f8b5
Step 10/11 : COPY ./gowiki/edit.html ./gowiki/view.html /app/
 ---> Using cache
 ---> d14cca8bd61e
Step 11/11 : CMD ["./gowiki"]
 ---> Using cache
 ---> 26dedeaf422e
Successfully built 26dedeaf422e
Successfully tagged johscheuer/gowiki:v2
```

- **Task 1**: Adjust your Kubernetes deployment descriptor for the new version and deploy it.
- **Task 2**: Validate that the new image is running in the cluster.

## Add Prometheus metrics

In the first step fetch the go client library for [Prometheus](https://github.com/prometheus/client_golang):

```bash
$ go get github.com/prometheus/client_golang
```

Add the promethes client to the imports:

```go
import (
	"html/template"
	"io/ioutil"
	"log"
	"net/http"
	"regexp"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)
```

and add an Prometheus handler to the main function:

```bash
func main() {
	http.HandleFunc("/view/", makeHandler(viewHandler))
	http.HandleFunc("/edit/", makeHandler(editHandler))
	http.HandleFunc("/save/", makeHandler(saveHandler))
	http.Handle("/metrics", promhttp.Handler())

	log.Fatal(http.ListenAndServe(":8080", nil))
}

```

For the dependency managment we will use [Go Modules](https://github.com/golang/go/wiki/Modules)

```bash
$ GO111MODULE=on go mod init
go: creating new go.mod: module github.com/johscheuer/gowiki
# Test if everything works
$ GO111MODULE=on go build .
go: finding github.com/prometheus/client_golang/prometheus/promhttp latest
go: finding github.com/prometheus/client_golang/prometheus latest
go: finding github.com/prometheus/client_golang v0.9.0
go: downloading github.com/prometheus/client_golang v0.9.0
go: finding github.com/prometheus/procfs latest
go: finding github.com/beorn7/perks/quantile latest
go: finding github.com/prometheus/common/expfmt latest
go: finding github.com/prometheus/common/model latest
go: finding github.com/prometheus/client_model/go latest
go: finding github.com/golang/protobuf/proto latest
go: finding github.com/beorn7/perks latest
go: downloading github.com/beorn7/perks v0.0.0-20180321164747-3a771d992973
go: finding github.com/prometheus/client_model latest
go: downloading github.com/prometheus/procfs v0.0.0-20181005140218-185b4288413d
go: downloading github.com/prometheus/client_model v0.0.0-20180712105110-5c3871d89910
go: finding github.com/prometheus/common latest
go: downloading github.com/prometheus/common v0.0.0-20181015124227-bcb74de08d37
go: finding github.com/golang/protobuf v1.2.0
go: downloading github.com/golang/protobuf v1.2.0
go: finding github.com/matttproud/golang_protobuf_extensions/pbutil latest
go: finding github.com/matttproud/golang_protobuf_extensions v1.0.1
go: downloading github.com/matttproud/golang_protobuf_extensions v1.0.1
```

Now we need to adjust the builder part of our Dockerfile:


```docker
FROM golang:1.11.1-stretch as builder
RUN go get -d github.com/prometheus/client_golang || true
WORKDIR /go/src/github.com/johscheuer/gowiki/
# Copy everthing including the go module files
COPY . .
# Activate go modules and build the binary
RUN GO111MODULE=on GOOS=linux go build -o gowiki .
...
```

After a successfull build run the container and validate that `/metrics` is available. Deploy the new version to your Kubernetes cluser:

- Create a new tag with `docker build` or use `docker tag`
- Adjust the Kubernetes deployment descriptor
- Apply the changes

- **Task 1**: Extend the current code to include a [Counter](https://godoc.org/github.com/prometheus/client_golang/prometheus) that increments each time the gowiki is called.

More information: https://prometheus.io/docs/guides/go-application/

## Deploy Prometheus

**Hint**: In the last class we deployed Prometheus.

- **Task 1**: Deploy Prometheus in the cluster
- **Task 2**: Validate that you can access Prometheus
- **Task 3**: Modify the deployment in such a way that Prometheus will scrape the pod
- **Task 4**: Make some request and evaluate the results in Prometheus


# Outlook

- https://github.com/GoogleContainerTools/skaffold
- "How to make our application scalable"
- ...?

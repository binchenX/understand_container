# OCI Specification

OCI(Open Container Initiative) is an industry collaborated effort to define open containers specifications regarding container image format and runtime. The history of how it comes to where it stands today from the initial disagreement is a very interesting story in terms of collaboration and competition in open source world.

Nowadays, all the main players in the container ecosystem follow the OCI container specification. For anyone interested to know how container actually works, it is a great technical source you will not want to miss.

## Overview

OCI has two specs, an [Image spec](https://github.com/opencontainers/image-spec) and a [Runtime spec](https://github.com/opencontainers/runtime-spec).

And, if a diagram suits your taste better, here is what they cover and how they interact.

```
      Image Spec              Runtime Spec
                 |
config           | runtime config
layers           | rootfs
|                |     |               delete
|                |     |                  |
|         unpack |     |     create       |     start/stop/exec
Image (spec) ----|-> Bundle ---------> container  ------->  process
                 |
                 |
```

An OCI Image will be downloaded from somewhere (thinking docker hub) and then it will be unpacked into an OCI Runtime filesystem bundle. From that point, the OCI Runtime Bundle will be run by an OCI Runtime. The Runtime Specification defines how to run a "filesystem bundle".

## Image Spec

Image specification defines the archive format of OCI container images, which is consist of a manifest, an image index, a set of filesystem layers, and a configuration. The goal of this specification is to enable the creation of interoperable tools for building, transporting, and preparing a container image to run.

At the top level, a container image is just a tarball, and after being extracted, it has the `layout` as below.


```
├── blobs
│   └── sha256
│       ├── 4297f0*      (image.manifest)
│       └── 7ea049       (image.config)
├── index.json
└── oci-layout

* take only the first 6 digits for clarity
```

The layout isn't that useful without a specification of what that stuff is and how they are related (referenced).

We can ignore the file `oci-layout` for simplicity. `index.json` is the entry point, it contains primary a `manifest`, which listed all the "resources" used by a single container image.

The `manifest` contains primarily the `config` and the `layers`.

Put that into a diagram, roughly this:

```
index.json -> manifest ->Config
                |           | ref
                |           |
                |--------Layers --> [ Base, upperlayer1,2,3...]
```

The [config](https://github.com/opencontainers/image-spec/blob/master/config.md) contains notably 1) configurations of the image, which can and will be converted to the runtime configure file of the runtime bundle, and 2) the layers, which makes up the root file system of the runtime bundle, and 3) some meta-data regarding the image history.

[layers](https://github.com/opencontainers/image-spec/blob/master/layer.md) are what makes up the final `rootfs`. The first layer is the base, all the other layers contain only the changes to *its* base. And this probably deserves more explanation.

### Layers

For layers, the specification essentially defines two things:

1. How to represent a layer?

* For the base layer, `tar` all the content;
* For non base layers, `tar` the changeset compared with its base.

  Hence, first *detect* the change, form a `changeset`; and then tar the changeset, as the representation of this layer.

2. How to union all the layers?

*Apply* all the changesets on top of the base layer. This will give you the `rootfs`.

## Runtime Specification

Once the *Image* is unpacked to a runtime bundle on the disk file system, there is something you can run. And then it is the Runtime Specification kick in. The Runtime Specification specifies the configuration, execution environment, and lifecycle of a container.

A container's configuration contains metadata necessary to create and run a container. This includes the process to run, environment variables, the resource constraints and sandboxing features to use, etc. Some of the configurations are generic across all platforms including Linux, Windows, Solaris and Virtual Machine specific; but some of them are platform specific, say Linux only.

The runtime specification also defines the Lifecycle of a container, that is a series of events that happen from when a container is created to when it ceases to exist.

### Container Lifecycle

A container has a lifecycle, at its essence, as you can imagine, it can be model as following state diagram.

You can throw in a few other actions and states, such as `pause` and `paused`, but those are the fundamental ones.

```
                               +--------+       +----------+
                               +prestart|       |poststart |
                               | hook   |       | hook     |
                               +--------+       +----------+
    create   +---------+   start   |  +---------+   |
  +--------->| created |           |  | started |   |
             |         |------------->|         |----
             +---------+              +----+----+
                                           |
                                           v  stop
             +---------+              +---------+
             | deleted |              | stopped |
             |         |<-------------|         |
             +---------+  delete   |  +---------+
                                   |
                               +---------+
                               |poststop |
                               |  hook   |
                               +---------+
```

The state diagram is conventional but there is one important thing worth mentioning - the `Hooks`. Probably a little surprise to you, container specification don't define how to set up the network and it actually relies on the hooks to set up the network properly, say create the network before container start and delete it after the container is stopped.

## Container Configrations

We mentioned before a container's configuration contains the config necessary to create and run a container. And we will look at some of the configs a little bit closer to get a sense of what is container really about, and we'll focus on Linux platform for all the configurations.

- Root
It defines the root file system of the container.

- Mounts
It specifies addition filesystem you can mount into the root file system. This is the place you can either bind mount your local host dir or a distributed dir, such as Ceph.

- Process
It specifies all the things related to the process that you want to run inside the container. It includes environment variable and the arguments to the process.

For the Linux process, you can additionally specify things concerning the security aspect of the process, things such as the capabilities, rlimits, and selinux label can be specified here.

- Hooks
This is the place you can hook up into the container lifecycle and do things such as setting up and/or clean up the network.

- Linux Namespaces

A whole lot of configurations for Linux platform is dedicated to the Namespace configuration. Actually, namespaces are the foundations of container technology. Or put it another way, there is will be no container without namespaces. Linux provides seven type of namespaces and they are all supported by the OCI runtime specification:


| Namespace | Domain / Description                |
| --------- | ----------------------------------- |
| PID       | Process IDs                         |
| Mount     | Mount points                        |
| Network   | Network devices, stacks, ports, etc |
| User      | User and group IDs                  |
| IPC       | System V IPC, POSIX message queues  |
| UTS       | Hostname and NIS domain name        |

 - Annotations
In addition to what and how the container should be run. Annotations allow you to label the containers. The ability to label and select the container base on some properties is the basic requirement for a container orchestration platform.

## Image, Container, and Processes

`Containers` are created from (container) `Image`. You can create more than one containers from a single Image, and you can also repack the containers, usually with changes to the base image, to create a new Image.

After you get the containers, you can run `process` inside of that container, without all the nice things about a container. Most notably, once we containerize an app, it is become self-contained and won't mess up with the host environment, and thus it should "run everywhere (TM)".

Here is the relationship between the various concept, `Image`, `Container` and `Process` and it is vitally important to get them right.

```
        Images               Container       Processes
                 +                      +
                 |                      |
           create|                      |
+--------+       |  +---------+  start  |  +---------+
|runtime +--------->|  created|         |  | started |
|Bundle  |       |  |         |----------->|         |
|        |       |  +---------+         |  +----+----+
+--------+       |                      |       |
                 |                      |       v  stop
                 |  +---------+         |  +---------+
                 |  | deleted |         |  | stopped |
                 |  |         |<-----------|         |
                 |  +---------+         |  +---------+
                 |               delete |
                 |                      |
```

## Docker and Kubernetes

Docker makes container an industry trend and probably there are lots of people considering docker *is* container and container *is* docker. Docker definitely deserves the credit here. But from the technical point of view, docker is the most widely used container implementation. The architecture of the docker implementation evolves very quick from version to version. As of the time of writing, it looks like below.

```
                       +---------------------+
                       |                     |
                       |  dockerInc/docker   |
                       |                     |
                       +--------+------------+
                                |  use
                                v
                       +---------------------+
                       |                     |
                       |    moby/moby        |
                       |                     |
                       +--------+------------+
                                |  use
                                v
+-------------------+  +---------------------+
|                   |  |                     |
| oci/runtime-spec  |  |containerd/containerd|
|                   |  |                     |
+---------+---------+  +--------+------------+
          |                     |  use
          |impl                 v
          |            +---------------------+     +------------+
          |            |                     |     |            |
          +----------- |     oci/runc        |---> |oci/runc/   |
                       |                     |     |libcontainer|
                       +---------------------+     +------------+
```

The diagram follows the format of `[github]Org/project`. Most of the components are originated from Docker, but they are currently under different github organization and project. At the top is the `docker` command tool we use daily, it is the commercial offering from Docker Inc; The `docker` tool relies on an open source project called moby, which in turn uses the [`runC`](https://github.com/opencontainers/runc), which is the reference implementation of the `oci runtime` specification. `runc` heavily depend on `libcontainer`, which was donated from Docker, Inc as well.

### Container orchaestraion

If we only need to one or two containers, docker probably is all we need. But if we want to run dozens or thousands of containers we have more problems to solve. To name a few:

- scheduling: Which host to put a container?
- update: How to update the container image?
- scaling: How to add more containers when more processing capacity is needed?

That is the job of `container orchestration` system. And Kubernetes is one of them, but as of now, I think there is no argument it is the most promising one. But we'll not deep dive into Kubernetes here, but will touch briefly from the perspective that how the container runtime fit into the container orchestration platform.

Following diagram illustrate how the Kubernetes interact with the container runtime.

```

      +----------------+---------------------------------+
      |                |---------------+                 |
      |   k8s/CRI      |               |                 |
      +----------------+        impl   |          impl   |
                                 +-----+--------+  +-----+--+
                                 |cri-containerd|  |cri-o   |
                      +----------|              |  |        |
                      |          +--------------+  +-----+--+
                      |                           k8s    |
+--------------+   +--v-----------+          container   |
|    oci/      |   |  containerd/ |                      |
| runtime-spec |   |  containerd  |                      |
|              |   |              |                      |
+----+---------+   +--+-----------+                      |
     ^                |                              use |
     |                |    use    +----------------------+
     |impl            v           |
     |             +-------------++       +-------------+
     |             |              |       |             |
     +-------------|  oci/runc    +-----> |oic/runc/    |
                   |              |       |libcontainer |
                   +--------------+       +-------------+
```

Kubernetes decouple the runtime implementation using [Container Runtime Interface](https://kubernetes.io/blog/2016/12/container-runtime-interface-cri-in-kubernetes). Simply speaking, CRI defines the interface to create, start, stop and delete a container. It allows pluggable container runtime for Kubernetes and you don't have to lock into one particular runtime. There are currently several implementations, such as `cri-containerd` and `cri-o`, both of which eventually will use `oci/runc`.

## Summary

This is an overview of OCI container image and runtime specification. It covers the responsibility of each specification and how they cooperate with each other. We go over the container lifecycle and primary configurations for the runtime spec. And we then introduce the relationship between docker and runc, and finish the article with a brief introduction to container orchestration and how the container runtime fit into it. It's quite a lot stuff! However, to really understand what real container is, we need to go even deeper.


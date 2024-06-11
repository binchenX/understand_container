# CNI

CNI, or `Container Network Interface`, originated from CoreOS as a network solution for rkt, and surpassed Docker's CNM by being adopted by [k8s](https://kubernetes.io/blog/2016/01/why-kubernetes-doesnt-use-libnetwork/) as the network plugin interface.

In this blog, we will explore how to use CNI, specifically the bridge plugin, to set up the network for containers spawned by runc, achieving the same result/topology as we did in the last blog using `netns` as the hook.

## Overview

The caller/user of CNI (e.g., a container runtime/orchestrator such as runc or k8s) interacts with a plugin using two things: a network configuration file and some environment variables. The configuration file contains the [configs of the network (or subnet)](https://github.com/containernetworking/cni/blob/master/SPEC.md#network-configuration) the container is supposed to connect to. The environment variables include the path where the plugin binary and network configuration files are located, *plus* "add/delete which container to/from which network namespace". This could be implemented by passing arguments to the plugin (instead of using environment variables). It's not a big issue, but it seems a bit "unusual" to use the environment to pass arguments.

For a more detailed introduction to CNI, see [here](https://www.slideshare.net/weaveworks/introduction-to-the-container-network-interface-cni) and [here](https://github.com/containernetworking/cni/blob/master/SPEC.md).

## Use CNI plugins

### Install plugins

```
go get github.com/containernetworking/plugins
cd $GOPATH/src/github.com/containernetworking/plugins
./build.sh
mkdir -p /opt/cni/bin/bridge
sudo cp bin/* c
```

## Use CNI

We'll be using the following simple script to exercise CNI with runc. It covers all the essential concepts in one place, which is nice.

```bash
$ cat runc_cni.sh
#!/bin/sh

# need run with root
# ADD or DEL or VERSION
action=$1
cid=$2
pid=$(runc ps $cid | sed '1d' | awk '{print $2}')
plugin=/opt/cni/bin/bridge

export CNI_PATH=/opt/cni/bin/
export CNI_IFNAME=eth0
export CNI_COMMAND=$action
export CNI_CONTAINERID=$cid
export CNI_NETNS=/proc/$pid/ns/net

$plugin <<EOF
{
    "cniVersion": "0.2.0",
    "name": "mynet",
    "type": "bridge",
    "bridge": "cnibr0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "172.19.1.0/24",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ],
     "dataDir": "/run/ipam-state"
    },
    "dns": {
      "nameservers": [ "8.8.8.8" ]
    }
}
EOF
```

It may not be obvious to a newcomer that we are using two plugins here, the [bridge plugin](https://github.com/containernetworking/plugins/tree/master/plugins/main/bridge) and [host-local](https://github.com/containernetworking/plugins/tree/master/plugins/ipam/host-local). The former is used to set up a bridge network (as well as a veth pair), and the latter is used to allocate and assign IP addresses to the containers (and the bridge gateway). This is referred to as `ipam` (IP Address Management), as you might have noticed in the config key.

The internal working of the bridge plugging is almost the same as the `netns` does and we are not going to repeat it here.

Start a container called `c1`, `sudo runc run c1`.

Then, put `c1` into the network:

```
sudo ./runc_cni.sh ADD c1
```

Below is the output, telling you the *ip* and *gateway* of `c1`, among other things.

```
{
    "cniVersion": "0.2.0",
    "ip4": {
        "ip": "172.19.1.6/24",
        "gateway": "172.19.1.1",
        "routes": [
            {
                "dst": "0.0.0.0/0",
                "gw": "172.19.1.1"
            }
        ]
    },
    "dns": {
        "nameservers": [
            "8.8.8.8"
        ]
    }
}
```

You can create another container `c2` and add it to the same network in a similar way. Now, we have a subnet with two containers inside. They can communicate with each other and can ping outside IPs, thanks to the route setting and IP masquerade. However, DNS won't work.

You can also remove a container from the network. After doing so, the container won't be connected to the bridge anymore.

```
sudo ./runc_cni.sh DEL c1
```

However, the IP resource won't be reclaimed automatically, you have to do that "manually".

That is it, as we said this will be a short ride. Have fun with CNI.

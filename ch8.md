# CNI

CNI means `Container Network Interface`, originated from coreOs for rkt's network solution, and beat Docker's CNM as being adopted by [k8s](https://kubernetes.io/blog/2016/01/why-kubernetes-doesnt-use-libnetwork/) as the network plugin interface.

In this blog we are going to see how to use CNI, to be specific, the bridge plugin, to setup the network for containers spawned by runc and achieve the same result/topology as we did in the last blog using netns as the hook.

## Overview

The caller/user of CNI (eg: you calling from a shell, a container runtime/orchestrator, such as runc or k8s) interact with a plugin using two things: a network configuration file and some environment variables. The configuration files has the [configs of network (or subnet)](https://github.com/containernetworking/cni/blob/master/SPEC.md#network-configuration) the container supposed to connect to; the environment variables include the path regarding where to find the plugin binary and network configuration files, *plus* "add/delete which container to/from which network namespace", which can well be implemented by passing arguments to the plugin (instead of using environment variable). It's not a big issue but looks a little bit "unusual" to use the environment to pass arguments.

For a more detailed introduction of CNI, see [here](https://www.slideshare.net/weaveworks/introduction-to-the-container-network-interface-cni) and [here](https://github.com/containernetworking/cni/blob/master/SPEC.md).

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

It may be not obvious to a newcomer that we are using two plugins here, [bridge plugin](https://github.com/containernetworking/plugins/tree/master/plugins/main/bridge) and [host-local](https://github.com/containernetworking/plugins/tree/master/plugins/ipam/host-local). The format is to set up a bridge network (as well as veth pair) and the late is to set up allocate and assign ip to the containers (and the bridge gateway), which is called `ipam` (IP Address Management), as you might have noticed in the config key.

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

You can create another container `c2` and put it into the same network in a similar way, and now we create a subnet with two containers inside. They can talk to each other and call can ping outside IPs, thanks to route setting and IP masquerade. However, the DNS won't work.

You can also remove a container from the network, after which the container won't be connected to the bridge anymore.

```
sudo ./runc_cni.sh DEL c1
```

However, the IP resource won't be reclaimed automatically, you have to do that "manually".

That is it, as we said this will be a short ride. Have fun with CNI.

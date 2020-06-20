# Network

When it comes to the container network, the oci runtime spec does no more than creating or joining a [network namespace](http://man7.org/linux/man-pages/man7/network_namespaces.7.html). All the other workers are left to be dealt with by using [hooks](https://github.com/opencontainers/runtime-spec/blob/master/config.md#posix-platform-hooks), which lets you inject into different [stages](https://github.com/opencontainers/runtime-spec/blob/master/runtime.md#lifecycle) of the container runtime and do some customization.

With the default `config.json`, you will see only a `loop device`, but not an `eth0` that you normally see on the host that allows you talk to the outside world. But, we can set up a simple bridge network by using `netns` as the hook.

Go and get [netns](https://github.com/genuinetools/netns) and copy the binary to `/usr/local/bin`, where the following config.json assume. Worth to note that the hooks are executed in the runtime namespace, not the container namespace. That means, among other things, the hooks binary should reside in the host system, not the container. Hence, you don't need to put the netns into the container rootfs.

## Setup bridge network using netns

Make the following change to `config.json`. In addition to the hooks, we also need `CAP_NET_RAW` capability so that we can use `ping` inside of the container to do some basic network checking.

```
binchen@m:~/container/runc$ git diff
diff --git a/config.json b/config.json
index 25a3154..d1c0fb2 100644
--- a/config.json
+++ b/config.json
@@ -18,12 +18,16 @@
                        "bounding": [
                                "CAP_AUDIT_WRITE",
                                "CAP_KILL",
-                               "CAP_NET_BIND_SERVICE"
+                               "CAP_NET_BIND_SERVICE",
+                               "CAP_NET_RAW"
                        ],
                        "effective": [
                                "CAP_AUDIT_WRITE",
                                "CAP_KILL",
-                               "CAP_NET_BIND_SERVICE"
+                               "CAP_NET_BIND_SERVICE",
+                               "CAP_NET_RAW"
                        ],
                        "inheritable": [
                                "CAP_AUDIT_WRITE",
@@ -33,7 +37,9 @@
                        "permitted": [
                                "CAP_AUDIT_WRITE",
                                "CAP_KILL",
-                               "CAP_NET_BIND_SERVICE"
+                               "CAP_NET_BIND_SERVICE",
+                               "CAP_NET_RAW"
                        ],
                        "ambient": [
                                "CAP_AUDIT_WRITE",
@@ -131,6 +137,16 @@
                        ]
                }
        ],
+
+       "hooks":
+               {
+                       "prestart": [
+                               {
+                                       "path": "/usr/local/bin/netns"
+                               }
+                       ]
+               },
+
        "linux": {
                "resources": {
                        "devices": [
```

start a container with this new config.

Inside the container, we find an `eth0` device, in addition to a `loop` device that is always there.

```
/ # ifconfig
eth0      Link encap:Ethernet  HWaddr 8E:F3:5C:D8:CA:2B
          inet addr:172.19.0.2  Bcast:172.19.255.255  Mask:255.255.0.0
          inet6 addr: fe80::8cf3:5cff:fed8:ca2b/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:21992 errors:0 dropped:0 overruns:0 frame:0
          TX packets:241 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:2610155 (2.4 MiB)  TX bytes:22406 (21.8 KiB)

lo        Link encap:Local Loopback
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1/128 Scope:Host
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:6 errors:0 dropped:0 overruns:0 frame:0
          TX packets:6 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1
          RX bytes:498 (498.0 B)  TX bytes:498 (498.0 B)
```

And, you will be able to ping (*) outside world.

```
/ # ping 216.58.199.68
PING 216.58.199.68 (216.58.199.68): 56 data bytes
64 bytes from 216.58.199.68: seq=0 ttl=55 time=18.382 ms
64 bytes from 216.58.199.68: seq=1 ttl=55 time=17.936 ms
```

Notes: 216.58.199.68 is one IP of google.com. If we had set up the DNS namesever (e.g echo nameserver 8.8.8.8 > /etc/resolv.conf), we would have been able to ping www.google.com.

So, how it works?

## Bridge, Veth, Route and iptable/NAT

Upon a hook being called, the container runtime will pass the hook the container's [state](https://github.com/opencontainers/runtime-spec/blob/master/runtime.md#state), among other things, the pid of the container (in runtime namespace). The hook, `Netns` in this case, will use that PID to find out the network namespace the container is supposed to be run in. With that PID, the `netns` will do a few things:

1) Create a Linux [bridge](https://wiki.archlinux.org/index.php/Network_bridge) with the default name `netns0`(if there isn't already one). Also, set up the MASQUERADE rule on the host.
2) Create a [veth pair](http://man7.org/linux/man-pages/man4/veth.4.html), connecting one endpoint of the pair to the bridge `netns0` and placing another one (renamed to `eth0`) into the container network namespaces.
3) Allocate and assign an IP to the container interface (`eth0`) and set up the Route table for the container.

Soon we'll go over the stuff we mentioned above in detail but let's start another container with the same config.json. Hopefully, it'll make things more clear and interesting than having only one container.

- bridge and interfaces

A bridge `netns0` is created and two interfaces are associated with it. The name of the interface follows the format of
`netnsv0-$(containerPid)`.

```
$ brctl show netns0
bridge name    bridge id        STP enabled    interfaces
netns0        8000.f2df1fb10980    no        netnsv0-8179
                                             netnsv0-10577
```

As we explained before `netnsv0-8179` is one endpoint of the veth pair, connecting to the bridge; the other endpoint is inside of the container 8179. Let's find it out.

- vthe pair

On the host, we can see the peer of `netnsv0-8179` is index `7`

```
$ ethtool -S netnsv0-8179
NIC statistics:
     peer_ifindex: 7
```

And in the container 8179, we can see the eth0's index is 7. It confirms that the `eth0` in container 8179 is paired with `netnsv0-8179` in the host. Same is true for `netnsv0-10577` and the `eth0` in container 10577.

```
/ # ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
7: eth0@if8: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue qlen 1000
    link/ether 8e:f3:5c:d8:ca:2b brd ff:ff:ff:ff:ff:ff
    inet 172.19.0.2/16 brd 172.19.255.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::8cf3:5cff:fed8:ca2b/64 scope link
       valid_lft forever preferred_lft forever
```

So far, we have seen how a container is connected to host virtul bridge using veth pair. We have the network interfaces but still need a few more setups: Route table and iptable.

### Route Table

Here is the route table for In container `8179`:

```
/ # route
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
default         172.19.0.1      0.0.0.0         UG    0      0        0 eth0
172.19.0.0      *               255.255.0.0     U     0      0        0 eth0
```
We can see the all traffic will goes through `eth0` to the gateway, which is the bridge `netns0`, as shown by:

```
# in container
/ # ip route get 216.58.199.68 from 172.19.0.2
216.58.199.68 from 172.19.0.2 via 172.19.0.1 dev eth0
```

In the host:

```
$ route
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
default         192-168-1-1     0.0.0.0         UG    0      0        0 wlan0
172.19.0.0      *               255.255.0.0     U     0      0        0 netns0
192.168.1.0     *               255.255.255.0   U     9      0        0 wlan0
192.168.122.0   *               255.255.255.0   U     0      0        0 virbr0
```

Also:

```
# on host
$ ip route get 216.58.199.68 from 172.19.0.1
216.58.199.68 from 172.19.0.1 via 192.168.1.1 dev wlan0
    cache
```

The `192.168.1.1` is the ip of my home route, which is a *real* bridge.

Piece together the route in the container, we can see when ping google from the container, the package will go to the virtual bridge created by the `netns` first, and then goes to the real route gateway at my home, and then into the wild internet and finally to one of the goole servers.

## Iptable/NAT

Another change made by the `netns` is to set up the MASQUERADE target, that means all traffic with a source of `172.19.0.0/16` will be MASQUERADE or NAT-ed with the host address so that outside can only see the host (ip) but not the container (ip).

```
# sudo iptables -t nat --list
Chain POSTROUTING (policy ACCEPT)
target     prot  opt source               destination
MASQUERADE  all  --  172.19.0.0/16        anywhere
```

## Port forward/DNAT(TODO)

With Ip MASQUERADE, the traffic can goes out from the container to the internet as well as the return traffic from the same connection. However, for conatiner to accept incoming connections, you have set up the port forwarding using iptable DNAT target.

In container:
```
/ # nc -p 10001 -l
```

port map: host:100088 maps to container xyxy12:1024

```
iptables -t nat -A PREROUTING -i eth0 -p tcp -m tcp --dport 100088 -j DNAT --to-destination 172.19.0.8:10001
```
host

```
echo the host says HI |  nc localhost 5555
```

## Share network namespace

To join the network namespace of another container, set up the network namespace path pointing to the one you want to join. In our example, we'll join the network namespace of container 8179.

```
{
-                "type": "network"
+                "type": "network",
+                "path": "/proc/8179/ns/net"
```

Remember to remove the prestart hook, since we don't need to create a new network interface (veth pair and route table) this time.

Start a new container, and we'll find that the new container has the same `eth0` device (as well as same ip) with the container 8179 and the route table is same as the one in container 8179 since they are in the same network namespace.

```
/ # ifconfig
eth0      Link encap:Ethernet  HWaddr 8E:F3:5C:D8:CA:2B
          inet addr:172.19.0.2  Bcast:172.19.255.255  Mask:255.255.0.0
          inet6 addr: fe80::8cf3:5cff:fed8:ca2b/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:22371 errors:0 dropped:0 overruns:0 frame:0
          TX packets:241 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:2658017 (2.5 MiB)  TX bytes:22406 (21.8 KiB)

lo        Link encap:Local Loopback
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1/128 Scope:Host
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:6 errors:0 dropped:0 overruns:0 frame:0
          TX packets:6 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1
          RX bytes:498 (498.0 B)  TX bytes:498 (498.0 B)
```

So, despite being in different containers, they share the same network device, route table, port numbers and all the other network resources. For example, if you start a web service in container 8179 port 8100 and you will be able to access the service in this new container using localhost:8100.

## Summary

We see how to use `netns` as the hook to setup a bridge network for our containers so that the containers can talk to the internet as well as each other. Put it into a diagram, we have setup something like this:

```
+---------------------------------------------------------+
|                                                         |
|                                                         |
|                                      +----------------+ |
|                                      |   wlan/eth0    +---+
|                                      |                | |
|                                      +---------+------+ |
|                                                |        |
|                                          +-----+----+   |
|                                    +-----+route     |   |
|                                    |     |table     |   |
|                                    |     +----------+   |
|    +-------------------------------+----------+         |
|    |                                          |         |
|    |                bridge:netns0             |         |
|    |                                          |         |
|    +-----+-----------------------+------------+         |
|          | interface             | interface            |
|    +-----+-----+          +------+----+                 |
|    |           |          |10:netnsv0 |                 |
|    |8:netnsv0- |          +-10577@if9 |                 |
|    |8179@if7   |          |           |                 |
|    +---+-------+          +----+------+                 |
|        |                       |                        |
|        |                       |                        |
| +-----------------+     +-----------------+             |
| |      |          |     |      |          |             |
| |  +---+------+   |     | +----+------+   |             |
| |  |          |   |     | |           |   |             |
| |  |7:eth0@if8|   |     | | 9:eth0@if10   |             |
| |  |          |   |     | |           |   |             |
| |  |          |   |     | |           |   |             |
| |  +----------+   |     | +-----------+   |             |
| |                 |     |                 |             |
| |  c8179          |     |  c10577         |             |
| +-----------------+     +-----------------+             |
|                                                         |
+---------------------------------------------------------+
```

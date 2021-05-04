# Capabilities

[capabilities](http://man7.org/linux/man-pages/man7/capabilities.7.html) is used to break the super privileges enjoyed by the root user to fine-grained permissions so that even being a root user you are not able to whatever you want unless been granted corresponding capabilities.

## Prepare rootfs

We'll need to install some additional tool (libcap) to explore the capabilities, so here some instruction of how to prepare such a rootfs.

First, create a docker container with libcap installed,

```
sudo docker run -it alpine sh -c 'apk add -U libcap; capsh --print'
```

using `docker ps -a` find out the container id of the one we just run, it should be the lastest one.

Then export the rootfs to create a runc runtime bundle.

```
mkdir rootfs
docker export $container_id | tar -C rootfs -xvf -
runc spec
```

## Capability

To get a sense of what capability is: Using the default `config.json` generated from runc spec, you are not allowed to set the hostname, even being root.

```
$ sudo runc run xyxy67
/ # id
uid=0(root) gid=0(root)
/ # hostname cool
hostname: sethostname: Operation not permitted
```

That's because setting hostname requires `CAP_SYS_ADMIN` capability, even being root. We can add that capability by adding `CAP_SYS_ADMIN` to `bounding`, `permitted`, `effective` list of the [capabilities attribute](https://github.com/opencontainers/runtime-spec/blob/master/config.md#linux-process) of the init the process.

Run another container with the new configuration, and now you are allowed to set hostname.

```
$ sudo runc run xyxy67
/ # hostname
runc
/ # hostname hello
/ # hostname
hello
/ #
```

Run another command in the same container, and it will able to set hostname as well since it inherits the capability of the init process.

```
$ sudo runc exec -t xyxy67 /bin/sh
[sudo] password for binchen:
/ # hostname
hello
/ # hostname good
/ # hostname
good
```

## Get capability

Get the PID of the two processes in the runtime PID namespace.

```
$ sudo runc ps xyxy67
UID        PID  PPID  C STIME TTY          TIME CMD
root     26002 25993  0 11:42 pts/0    00:00:00 /bin/sh
root     26059 26051  0 11:43 pts/1    00:00:00 /bin/sh
```

Install `pscap` on the *host*:

```
sudo apt-get install libcap-ng-utils
```

Check capabilities of the running process using the pids in the host namespace.

```
$ pscap | grep "26059\|26002"
25993 26002 root        sh                kill, net_bind_service, sys_admin, audit_write
26051 26059 root        sh                kill, net_bind_service, sys_admin, audit_write
```

And we can confirm those two process has the `sys_admin` capability.

## Request additional capability

The exec can require *additional* caps that don't exist in the `config.json`.

Run another container `xyxy78` without the `CAP_SYS_ADMIN` in the `config.json`.

Double check it indeed doesn't have the CAPS.

```
$ sudo runc ps xyxy78
UID        PID  PPID  C STIME TTY          TIME CMD
root     27385 27376  0 11:57 pts/0    00:00:00 /bin/sh
$ pscap | grep 27385
27376 27385 root        sh                kill, net_bind_service, audit_write
```

Start another process in `xyxy78` but with additional CAP_SYS_ADMIN capability, using `--cap` option.

```
sudo runc exec --cap CAP_SYS_ADMIN xyxy78 /bin/hostname cool
```

Under the hood of `--cap` option, it is to set up the capability list for the process that will be exec-ed, just as set up those things for in the `config.json` for the init process.

## capsh

You can use [capsh](http://man7.org/linux/man-pages/man1/capsh.1.html) explore a little bit more.

Run `capsh --print` *inside of the container*.

This is the output with default config.json:

```
# capsh --print
Current: = cap_kill,cap_net_bind_service,cap_audit_write+eip
Bounding set =cap_kill,cap_net_bind_service,cap_audit_write
Securebits: 00/0x0/1'b0
 secure-noroot: no (unlocked)
 secure-no-suid-fixup: no (unlocked)
 secure-keep-caps: no (unlocked)
uid=0(root)
gid=0(root)
groups=
```

This is the output with added `CAP_SYS_ADMIN` capability. Compared with former one, we can see additional `cap_sys_admin+ep` in the "Current" and `ap_sys_admin` in the "Bounding Set". The "+ep" means the preceding capabilities are in both "effective" and "permitted" list. For more information regarding the capability list, see [capabilities](http://man7.org/linux/man-pages/man7/capabilities.7.html).

```
# capsh --print
Current: = cap_kill,cap_net_bind_service,cap_audit_write+eip cap_sys_admin+ep
Bounding set =cap_kill,cap_net_bind_service,cap_sys_admin,cap_audit_write
Securebits: 00/0x0/1'b0
 secure-noroot: no (unlocked)
 secure-no-suid-fixup: no (unlocked)
 secure-keep-caps: no (unlocked)
uid=0(root)
gid=0(root)
groups=
```

## Summary

We see how Linux capability is used to limit the things a process can do and thus increase the security of the container.


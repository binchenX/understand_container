# Namespaces

It's safe to say without namespaces, there would be no container.

This article will not be the description or overview of namespaces in Linux, which you can find at [here](http://man7.org/linux/man-pages/man7/namespaces.7.html) and [here](https://lwn.net/Articles/531114/).

Instead, we'll get our hands dirty and *see* what exactly happens to the namespaces when we use the commonly used container commands so that you appreciate the role namespaces is playing in the container technology.

There are several types of namespaces, such as PID namespaces, mount namespaces. In this article we focus on the change of PID namespaces, other namespaces follow similar rules. We'll use [runc](https://github.com/opencontainers/runc) as the container runtime, since it is simple, have a specification, easy to change to experiment stuff and when necessary, I can point you the code. As we have pointed out in previous chapter that docker is using runc as the container runtime and the docker command is quite similar to runc command. So docker users should be able to feel at home we use runc command here.

If you like, follow [here](https://github.com/opencontainers/runc/blob/master/README.md) to install runc and prepare a busybox runtime bundle (or container).

Let's get started.

## Run container

```
sudo runc run xyxy12
```

To detect the newly created processes, we can use tool `execsnoop`.

```
$ git clone https://github.com/brendangregg/perf-tools.git
$ cd perf-tools
$ sudo ./execsnoop
```

After running the xyxy12, we should see something as below. The first column is the PID of the newly created process, which is 10123 and the process is `sh`.

```
 10100  10099 runc start xyxy12
 10113  10052 sudo runc run xyxy12
 10114  10113 runc run xyxy12
 10120  10117 runc init
 10123  10121 sh
```

To get the PID namespaces, we can customize the output format of `ps` command, as shown below, and the PIDNS is what we want.

```
$ sudo ps -p 10123 -o pid,pidns
  PID      PIDNS
 10123 4026532572
```

We can also use `/proc` filesystem to find out the namespaces information:

```
$ sudo ls -l /proc/10123/ns
total 0
lrwxrwxrwx 1 root root 0 Apr 26 17:03 cgroup -> cgroup:[4026531835]
lrwxrwxrwx 1 root root 0 Apr 26 16:33 ipc -> ipc:[4026532571]
lrwxrwxrwx 1 root root 0 Apr 26 16:33 mnt -> mnt:[4026532569]
lrwxrwxrwx 1 root root 0 Apr 26 16:33 net -> net:[4026532574]
lrwxrwxrwx 1 root root 0 Apr 26 16:33 pid -> pid:[4026532572]
lrwxrwxrwx 1 root root 0 Apr 26 16:33 user -> user:[4026531837]
lrwxrwxrwx 1 root root 0 Apr 26 16:33 uts -> uts:[4026532570]
```

We have a few files here, each one represents a type of namespaces. PID is the PID namespaces, mnt the mount namespaces. Those files are symlinks pointing to the "real" namespaces the process belongs to, thinking it as a pointer pointing to some namespaces object, which is denoted by `inode` number and it is unique in the host system. If the namespaces symlink of two different process point to same `inode`, they belong to the same namespaces. By default, if no new namespaces are created, they all belong the same "root" or "default" namespace.

You can also find out the namespaces of `sh` inside of the container but need to use the PID in the container namespaces, that is `1` for the `10123`. It isthe some process but different PID in a different namespaces, that is all PID namespaces are about. Note that it is mandatory that the `/proc` must be setup properly during container creation.

```
# inside the container
# ls -l /proc/1/ns
total 0
lrwxrwxrwx    1 root     root    0 Apr 26 06:34 cgroup -> cgroup:[4026531835]
lrwxrwxrwx    1 root     root    0 Apr 26 06:34 ipc -> ipc:[4026532571]
lrwxrwxrwx    1 root     root    0 Apr 26 06:34 mnt -> mnt:[4026532569]
lrwxrwxrwx    1 root     root    0 Apr 26 06:34 net -> net:[4026532574]
lrwxrwxrwx    1 root     root    0 Apr 26 06:34 pid -> pid:[4026532572]
lrwxrwxrwx    1 root     root    0 Apr 26 06:34 user -> user:[4026531837]
lrwxrwxrwx    1 root     root    0 Apr 26 06:34 uts -> uts:[4026532570]
```

Next, we want to check what processes are in the newly created PID namespaces. Unfortunately, there isn't a place we can find out this information directly but need to go over all the `/proc/<pid>/ns` files and aggregate all the PIDs belongs the same namespaces. Luckily, tool [cinf](https://github.com/mhausenblas/cinf), does exactly that.

```
$ sudo cinf -namespace 4026532572
PID   PPID  NAME CMD  CGROUPS
10123 10114 sh   sh  14:name=dsystemd:/
                     13:name=systemd:/user/1000.user/c2.session/xyxy12
                     12:pids:/xyxy12
                     11:hugetlb:/user/1000.user/c2.session/xyxy12
                     10:net_prio:/user/1000.user/c2.session/xyxy12
                     9:perf_event:/user/1000.user/c2.session/xyxy12
                     8:net_cls:/user/1000.user/c2.session/xyxy12
                     7:freezer:/user/1000.user/c2.session/xyxy12
                     6:devices:/user/1000.user/c2.session/xyxy12
                     5:memory:/user/1000.user/c2.session/xyxy12
                     4:blkio:/user/1000.user/c2.session/xyxy12
                     3:cpuacct:/user/1000.user/c2.session/xyxy12
                     2:cpu:/user/1000.user/c2.session/xyxy12
                     1:cpuset:/xyxy12
```

There is only one process at the moment, and that is the "init" program of the container we started, the `sh` program. Ignore the `cgroup` at the moment, we'll talk about it in the late chapter.

Well, we see that when a new container is created, a bunch of new namespaces will be created and the "init" process of the container will be put into those namespaces. Effectively the process is running in a container, and that mean different things for different namespaces. For PID namespaces, it means all the processes running in the container can see only the processes *in* the same processes namespaces, "pid:[4026532572]", or equivalently "pid:xyxy12". The `sh` process is considered as PID 1 inside of the container, but it is 10123 in the host, and that's PID namespaces in play here. As you can see, we actually can use the container and namespaces interchangeably in this context.

We are clear, hopefully, about what does `docker/runc run` do regarding the namespaces. How about `docker/runc exec`?

## Run new process inside a container

Do this:

```
sudo runc exec xyxy12 /bin/top -b
```

From `execsnoop`, we can see the pids - in the runtime namespaces.

```
 10702  10701 runc exec xyxy12 /bin/top -b
 10708  10704 runc init
 10710  10709 /bin/top -b
```

We can use `runc ps`, which will the processes running in a container, and the PIDs listed are in the runtime namespaces, which is what we want. (One interesting difference is execsnoop say the parent of 10710 is 10709, but runc ps says it is 10702, which is the runc exec command, seems makes more sense.)

```
$ sudo runc ps xyxy12
UID        PID  PPID  C STIME TTY          TIME CMD
root     10123 10114  0 16:29 pts/0    00:00:00 sh
root     10710 10702  0 16:38 pts/1    00:00:00 /bin/top -b
```

Unfortunately, the `runc ps` does not fully support the `-o pid,pidns` option. So we'll again use the `cinf` to find out the namespaces of the new running process (`top -b`)

```
$ sudo cinf -pid 10710

 NAMESPACE   TYPE

 4026532569  mnt
 4026532570  uts
 4026532571  ipc
 4026532572  pid
 4026532574  net
 4026531837  user

```

We can see that no new namespaces were created. The `/bin/top -b` command *joined* the namespaces of "init" process - the first process we run in the container.

Let's list again the processes inside of the PID namespaces `4026532572`. Now, there are two: 10123 and 10710.

```
$ sudo cinf -namespace 4026532572
PID   PPID  NAME  CMD  CGROUPS
10123 10114 sh    sh   14:name=dsystemd:/
                       13:name=systemd:/user/1000.user/c2.session/xyxy12
                       12:pids:/xyxy12
                       11:hugetlb:/user/1000.user/c2.session/xyxy12
                       10:net_prio:/user/1000.user/c2.session/xyxy12
                       9:perf_event:/user/1000.user/c2.session/xyxy12
                       8:net_cls:/user/1000.user/c2.session/xyxy12
                       7:freezer:/user/1000.user/c2.session/xyxy12
                       6:devices:/user/1000.user/c2.session/xyxy12
                       5:memory:/user/1000.user/c2.session/xyxy12
                       4:blkio:/user/1000.user/c2.session/xyxy12
                       3:cpuacct:/user/1000.user/c2.session/xyxy12
                       2:cpu:/user/1000.user/c2.session/xyxy12
                       1:cpuset:/xyxy12
10710 10702 top /bin/top -b 14:name=dsystemd:/
                         13:name=systemd:/user/1000.user/c2.session/xyxy12
                         12:pids:/xyxy12
                         11:hugetlb:/user/1000.user/c2.session/xyxy12
                         10:net_prio:/user/1000.user/c2.session/xyxy12
                         9:perf_event:/user/1000.user/c2.session/xyxy12
                         8:net_cls:/user/1000.user/c2.session/xyxy12
                         7:freezer:/user/1000.user/c2.session/xyxy12
                         6:devices:/user/1000.user/c2.session/xyxy12
                         5:memory:/user/1000.user/c2.session/xyxy12
                         4:blkio:/user/1000.user/c2.session/xyxy12
                         3:cpuacct:/user/1000.user/c2.session/xyxy12
                         2:cpu:/user/1000.user/c2.session/xyxy12
                         1:cpuset:/xyxy12
```

If we run `ps` inside of the container, we'll also see those processes (plus the `ps` itself). Their Pids are 1 and 9, instead of 10123 and 10710. Again, its PID namespaces in play here.

```
/ # ps -ef
PID   USER     TIME  COMMAND
    1 root      0:00 sh
    9 root      0:00 /bin/top -b
   18 root      0:00 ps -ef

```
Now we know that `docker/runc exec` actually starts the new process inside of the namespaces the container already created.

## Summary

When running a container, new namespaces will be created and the `init` process will be started in that namespaces; when running a new process in a container, it will join the namespaces that are created when the container is created.

That's the "normal" case, instead of letting the container creating a namespaces for the container, you can also specify a [path](https://github.com/opencontainers/runtime-spec/blob/master/config-linux.md#namespaces) that you want the container or processes to run in.

Now you understand how exactly PID namespaces are used in the container. If you can take an extra step to figure out what is the mount namespaces and how it is used in container, then you understand the core of application containerization.


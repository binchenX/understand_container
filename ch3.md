# CGroups

Namespaces control what the processes inside of the containers can *see*, cgroup controls *how much* resources they can use. Namespace is about isolation, cgroup is about "budget" control.

Follow the same methodology as we did when walking through the namespaces usage in container, we'll create/run a container first, then run a new a process in the container and see how the cgroup in the host system changes; and then we see how to config the cgroup, firstly manually manipulating the host cgroup files and then using the runc config files and docker cli command.

## Create cgroup

Take a snapshot of the cgroups before creating a container using the following command. `lscgroup` is command line tool that lists all the cgroup currently in the system, simply by walk `/sys/fs/cgroup/`.

```
lscgroup | tee cgroup.b
```

Start a container and record the cgroups after that,

```
sudo runc run xyxy12
lscgroup | tee cgroup.a
```

Check the cgroup difference:

```
# the diff out is cleaned up a little bit
$ diff cgroup.b cgroup.a
> cpuset:/xyxy12
> cpu:/user/1000.user/c2.session/xyxy12
> cpuacct:/user/1000.user/c2.session/xyxy12
> blkio:/user/1000.user/c2.session/xyxy12
> memory:/user/1000.user/c2.session/xyxy12
> devices:/user/1000.user/c2.session/xyxy12
> freezer:/user/1000.user/c2.session/xyxy12
> net_cls:/user/1000.user/c2.session/xyxy12
> perf_event:/user/1000.user/c2.session/xyxy12
> net_prio:/user/1000.user/c2.session/xyxy12
> hugetlb:/user/1000.user/c2.session/xyxy12
> pids:/xyxy12
```

As we can see, for each cgroup type, a new cgroup `xyxy12` is created, underneath its parent's cgroup, which is the cgroups of the `bash` in which we issued the `runc run` command.

## Who is under control?

cgroup control processes, it mandates how much memory/cpu/etc. a process or a group of processes can use. Adding a process into cgroup, is simpling add the process pid to the groups's `task` list.

First, find out the PID of the container('s init process).

```
$ sudo runc ps xyxy12
UID        PID  PPID  C STIME TTY          TIME CMD
root     23472 23463  0 12:33 pts/0    00:00:00 /bin/sh
```

Check who are in the variouse cgroups (using memory and cpu cgroup as examples):

```
$ cat /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/tasks
23472
$ cat /sys/fs/cgroup/cpu/user/1000.user/c2.session/xyxy12/tasks
23472
```

Ok. It is clear that the container's init process is put into the newly created cgroups dedicated for that container.
And, to make the description complete, to find out the cgroups a process is in, just cat `/proc/<pid>/cgroup`.

We are pretty happy with what we have found, but still, want to see how the new processes started in the container related to the container.

## Join cgroup

start a new process inside of the container xyxy12.

```
sudo runc exec xyxy12 /bin/top -b
```

Check if any new cgroups are created

```
$ lscgroup | tee cgroup.c
$ diff cgroup.c cgroup.a
```

Nope. No new cgroups are created when exec a new process inside of an already running container.

Then, how the newly created process is related to the cgroup created by the container? Find the process of the new process first.
It is 32123, and note that it is in the runtime namespace.

```
$ sudo runc ps xyxy12
UID        PID  PPID  C STIME TTY          TIME CMD
root     23472 23463  0 12:33 pts/0    00:00:00 /bin/sh
root     32123 32115  0 12:48 pts/1    00:00:00 /bin/top -b
```

Check the memory and cpu cgrups for the container. Fwiw, the pattern is  "/sys/fs/cgroup/<restype>/user/1000.user/c2.session/<container_id>"

```
$ cat /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/tasks
23472
32123

$ cat /sys/fs/cgroup/cpu/user/1000.user/c2.session/xyxy12/tasks
23472
32123
```

All right, it means the new process will be added to the cgroups created in the first container run.

To summary, when a container is created, a new cgroup group will be created for each type of the resources and all the processes running in the container will be put into that group (for each type). Hence the resources the processes in the container can be controlled through those cgroups.

## Config cgroups

### Hard way

We know now when the cgroups are created and what and how processes are put into each groups. Finally, it is time to see actually how to use the cgroup to put some constraints on the processes. Memory constraint/cgroup is the easiest to understand, and we'll use that as an example.

However, if you check the memory cgroup configuration for the xyxy12, it is isn't set at all. I don't know where 9223372036854771712 is come from but that's for sure not a useful limitation.

```
cat /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/memory.limit_in_bytes
9223372036854771712
```

To config a limit is as easy as writing a sysfs file.

```
# requires root
# echo "100000000" > /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/memory.limit_in_bytes
# echo "0" > /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/memory.swappiness
```

With this setting in place, any processes in the container won't be able to use more memory than 100M, once it exceeds, it will be killed, or paused, depending on the `memory.oom_control` setting.

### Easy way

You are not supposed to config the cgroup that way (but it is what happens under the hood).

For runc, it can be easily set in the `config.json`. Adding the following config snippet in [linux.resources](https://github.com/opencontainers/runtime-spec/blob/master/config-linux.md#control-groups) section, you are limit all the processes lunching in a container with max 100M memory.

```
"memory": {
    "limit": 100000000,
    "reservation": 200000
}
```

Under the the hood, the runc will write the file for you. And it can be revealed by changing the value from 100000000 to 100000, which will cause an error:

```
container_linux.go:348: starting container process caused "process_linux.go:402:
container init caused \"process_linux.go:367: setting cgroup config for procHooks
process caused \\\"failed to write 100000 to memory.limit_in_bytes: write /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/memory.limit_in_bytes:
device or resource busy\\\"\""
```

If you use docker, the memory limit can be specified in the docker run command, with the `--memory` option, which will be converted to a config file passing to runc, and which will write corresponding sys fs file.

## Summary

We'll walk through how Linux cgroup is used in container.

- a new cgroup will be created for a new container
- exec a new process in a running container will join the created new cgroups
- config the cgroup properly so that the processes in the container are controlled.


# CGroups

While namespaces control what the processes inside the containers can *see*, cgroups control *how much* resources they can use. Namespaces are about isolation, while cgroups are about resource "budget" control.

Following the same methodology as we did when walking through the usage of namespaces in a container, we'll first create and run a container. Then, we'll run a new process in the container and observe how the cgroup in the host system changes. After that, we'll explore how to configure the cgroup, first by manually manipulating the host cgroup files, and then using the runc config files and Docker CLI commands.

## Create cgroup

Before creating a container, take a snapshot of the cgroups using the following command. `lscgroup` is a command-line tool that lists all the cgroups currently in the system, simply by walking through `/sys/fs/cgroup/`.

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

As we can see, for each cgroup type, a new cgroup `xyxy12` is created under its parent cgroup. The parent cgroup is the cgroup of the `bash` session in which we issued the `runc run` command.

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

Okay, it's clear that the container's `init` process is placed into the newly created cgroups dedicated to that container. To complete the description, you can find out which cgroups a process is in by using the command `cat /proc/<pid>/cgroup`.

We're quite satisfied with what we've discovered, but we still want to understand how new processes started in the container relate to the container itself.

## Join cgroup

Start a new process inside the container `xyxy12`.

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

Alright, this means that the new process will be added to the cgroups created during the first container run.

In summary, when a container is created, a new cgroup will be created for each type of resource, and all the processes running in the container will be placed into these groups. Therefore, the resources that the processes in the container can use can be controlled through these cgroups.

## Config cgroups

### Hard way

We now understand when the cgroups are created, and how processes are assigned to each group. Finally, it's time to see how to actually use the cgroup to impose constraints on the processes. The memory constraint/cgroup is the easiest to understand, so we'll use that as an example.

However, if you check the memory cgroup configuration for `xyxy12`, it isn't set at all. I'm not sure where 9223372036854771712 comes from, but it's certainly not a useful limitation.

```
cat /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/memory.limit_in_bytes
9223372036854771712
```

To config a limit is as easy as writing a `sysfs` file.

```
# requires root
# echo "100000000" > /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/memory.limit_in_bytes
# echo "0" > /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/memory.swappiness
```

With this setting in place, any processes in the container won't be able to use more memory than 100M, once it exceeds, it will be killed, or paused, depending on the `memory.oom_control` setting.

### Easy way

You are not supposed to configure the cgroup in this way, although this is what happens under the hood.

For `runc`, it can be easily set in the `config.json` file. By adding the following configuration snippet in the [linux.resources](https://github.com/opencontainers/runtime-spec/blob/master/config-linux.md#control-groups) section, you can limit all the processes launched in a container to a maximum of 100M memory.

```
"memory": {
    "limit": 100000000,
    "reservation": 200000
}
```


Under the hood, `runc` will write the file for you. This can be demonstrated by changing the value from 100000000 to 100000, which will cause an error:

```
container_linux.go:348: starting container process caused "process_linux.go:402:
container init caused \"process_linux.go:367: setting cgroup config for procHooks
process caused \\\"failed to write 100000 to memory.limit_in_bytes: write /sys/fs/cgroup/memory/user/1000.user/c2.session/xyxy12/memory.limit_in_bytes:
device or resource busy\\\"\""
```
If you use Docker, the memory limit can be specified in the `docker run` command using the `--memory` option. This option will be converted into a configuration file that is passed to `runc`, which will then write the corresponding sysfs file.

## Summary

We walked through how Linux cgroups are used in containers.

- A new cgroup will be created for each new container.
- Executing a new process in a running container will join the newly created cgroups.
- Configuring the cgroup properly ensures that the processes in the container are controlled.

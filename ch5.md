# Mount namespace & pivot_root

Files in Linux system are organized as a tree. The tree normally starts with a root file system (called `rootfs`) provided by the Linux distribution, and the rootfs will be mounted as "/". Later, optionally additional file systems can be attached to a subdirectory.such as /data, which for example points to an external USB disk.

`mount(2)` is the system call used to attach a file system or a directory to a node of the root tree. When the system boots up, the init process will do multiple mount call to set up the file system properly, and that is the initial mount table. All the processes have its mount table, but they normally pointing to the same one - the one set up by the init process. However, a process can also have a separate mount table from its parent. It starts with copying the parent one but later any change to it (incurred by `mount` ) will only impact itself. And that's what `mount namespace` means and for. Worth to note that in the same mount namespace, any change to the mount table by one process will be visible to another process. And because of this, when you mount a USB disk on the shell and the files explorer will be able to see the content as well.

## Mount Namespace

Normally, the application won't create a separate mount namespace when being started.

For example, there are two mnt namespaces on my host,

```
$ sudo cinf | grep mn
 4026531857  mnt  1  0
 4026531840  mnt  311 0,1,7,101,102,106,107,109,111,113,116,121,125,126,127,1000,65534  /sbin/init
```

But the first one has only one process kdevtmpfs, which is a kernel process.

```
$ sudo cinf --namespace 4026531857

 PID  PPID  NAME       CMD  NTHREADS  CGROUPS             STATE
 46   2     kdevtmpfs       1         xxx  S (sleeping)

$ ps -ef | grep kdevtmpfs
root        46     2  0 10:17 ?        00:00:00 [kdevtmpfs]
```

All the other processes are in the second mount namespaces created by the `/sbin/init`. And if you check the mount points of two processes in that mnt namespace (by cat /proc/pid/mounts), they are all same.(*)

*Notes: The mount points for chrome are empty despite being in the same namespace. why?

```
$ ps -ef | grep 10142
binchen  10142  3692  0 11:42 ?        00:00:02 /opt/google/chrome/chrome
$ ll /proc/10142/ns/mnt
lrwxrwxrwx 1 binchen binchen 0 May  7 11:44 /proc/10142/ns/mnt -> mnt:[4026531840]
$ cat /proc/10142/mounts
# it shows nothing...
```

### Mnt Namespace for Container

Let's start a container and what changes in mnt namespaces,

```
sudo runc run xyxy12
```

Check the mount namespace

```
$ sudo cinf | grep mnt
 4026531840  mnt 333 0,1,7,101,102,106,107,109,111,113,116,121,125,126,127,1000,65534  /sbin/init
 4026532458  mnt 1   0         sh
 4026531857  mnt 1   0
```

We have a **new** mount namespace, 4026532458, which is created when run container xyxy12:

```
$ sudo cinf -namespace 4026532458
 PID    PPID   NAME  CMD  NTHREADS  CGROUPS                                            STATE
 11674  11665  sh    sh   1         14:name=dsystemd:/                                 S (sleeping)

$ sudo runc ps xyxy12
UID        PID  PPID  C STIME TTY          TIME CMD
root     11674 11665  0 12:00 pts/0    00:00:00 sh
```

And here the dump of the mount info for our new container.

```
$ cat /proc/11674/mounts | sort | uniq
cgroup /sys/fs/cgroup/blkio cgroup ro,nosuid,nodev,noexec,relatime,blkio 0 0
cgroup /sys/fs/cgroup/cpuacct cgroup ro,nosuid,nodev,noexec,relatime,cpuacct 0 0
cgroup /sys/fs/cgroup/cpu cgroup ro,nosuid,nodev,noexec,relatime,cpu 0 0
cgroup /sys/fs/cgroup/cpuset cgroup ro,nosuid,nodev,noexec,relatime,cpuset 0 0
cgroup /sys/fs/cgroup/devices cgroup ro,nosuid,nodev,noexec,relatime,devices 0 0
cgroup /sys/fs/cgroup/dsystemd cgroup ro,nosuid,nodev,noexec,relatime,xattr,release_agent=/lib/systemd/systemd-cgroups-agent,name=dsystemd 0 0
cgroup /sys/fs/cgroup/freezer cgroup ro,nosuid,nodev,noexec,relatime,freezer 0 0
cgroup /sys/fs/cgroup/hugetlb cgroup ro,nosuid,nodev,noexec,relatime,hugetlb 0 0
cgroup /sys/fs/cgroup/memory cgroup ro,nosuid,nodev,noexec,relatime,memory 0 0
cgroup /sys/fs/cgroup/net_cls cgroup ro,nosuid,nodev,noexec,relatime,net_cls 0 0
cgroup /sys/fs/cgroup/net_prio cgroup ro,nosuid,nodev,noexec,relatime,net_prio 0 0
cgroup /sys/fs/cgroup/perf_event cgroup ro,nosuid,nodev,noexec,relatime,perf_event 0 0
cgroup /sys/fs/cgroup/pids cgroup ro,nosuid,nodev,noexec,relatime,pids 0 0
/dev/disk/by-uuid/22cb3888-325e-4283-a605-d2f60d11bb96 / ext4 ro,relatime,errors=remount-ro,data=ordered 0 0
/home/binchen/container/runc/devpts /dev/console devpts rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=666 0 0
/home/binchen/container/runc/devpts /dev/pts devpts rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=666 0 0
/home/binchen/container/runc/mqueue /dev/mqueue mqueue rw,nosuid,nodev,noexec,relatime 0 0
/home/binchen/container/runc/proc /proc/asound proc ro,relatime 0 0
/home/binchen/container/runc/proc /proc/bus proc ro,relatime 0 0
/home/binchen/container/runc/proc /proc/fs proc ro,relatime 0 0
/home/binchen/container/runc/proc /proc/irq proc ro,relatime 0 0
/home/binchen/container/runc/proc /proc proc rw,relatime 0 0
/home/binchen/container/runc/proc /proc/sys proc ro,relatime 0 0
/home/binchen/container/runc/proc /proc/sysrq-trigger proc ro,relatime 0 0
/home/binchen/container/runc/shm /dev/shm tmpfs rw,nosuid,nodev,noexec,relatime,size=65536k 0 0
/home/binchen/container/runc/sysfs /sys sysfs ro,nosuid,nodev,noexec,relatime 0 0
/home/binchen/container/runc/tmpfs /dev tmpfs rw,nosuid,size=65536k,mode=755 0 0
/home/binchen/container/runc/tmpfs /proc/kcore tmpfs rw,nosuid,size=65536k,mode=755 0 0
/home/binchen/container/runc/tmpfs /proc/sched_debug tmpfs rw,nosuid,size=65536k,mode=755 0 0
/home/binchen/container/runc/tmpfs /proc/timer_list tmpfs rw,nosuid,size=65536k,mode=755 0 0
/home/binchen/container/runc/tmpfs /proc/timer_stats tmpfs rw,nosuid,size=65536k,mode=755 0 0
name=systemd /sys/fs/cgroup/systemd cgroup ro,nosuid,nodev,noexec,relatime,name=systemd 0 0
tmpfs /proc/scsi tmpfs ro,relatime 0 0
tmpfs /sys/firmware tmpfs ro,relatime 0 0
tmpfs /sys/fs/cgroup tmpfs ro,nosuid,nodev,noexec,relatime,mode=755 0 0
```

Probably the content doesn't interest you too much. We will skip the details of most of those entries here, but one :

```
/dev/disk/by-uuid/22cb3888-325e-4283-a605-d2f60d11bb96 / ext4 ro,relatime,errors=remount-ro,data=ordered 0 0
```

This mount src is pointing to the `/dev/sda2`, which is our host's rootfs mounting to.

```
$ ll /dev/disk/by-uuid/22cb3888-325e-4283-a605-d2f60d11bb96
lrwxrwxrwx 1 root root 10 Apr 28 13:28 /dev/disk/by-uuid/22cb3888-325e-4283-a605-d2f60d11bb96 -> ../../sda2

$ mount
/dev/sda2 on / type ext4 (rw,errors=remount-ro)
```

Does that sound surprising and alarming to you? Why is the root of the container is same as the root of the host? So with a new mount namespace, we still can access the root of the host? Shouldn't the container be "jailed" in the rootfs the contained is started in?

Let's check one more thing, compare the inode number of the `/` in the container and the inode of the container's rootfs.

```
# in container
/ # ls -di /
25846165 /
```

```
# on host
$ ls -di ~/container/runc/rootfs/
25846165 /home/binchen/container/runc/rootfs/
```

They are same! That means the root of the container is the rootfs, or directory of its runtime bundle, in OCI's term, as you expected!

So, why? From the mount we see "/" is mounted to /dev/sda2, which is same as the root of the host but in fact, the root is the container bundle directory?

Entering `pivot_root`.

## pivot_root

The "jail" is done by [pivot_root](http://man7.org/linux/man-pages/man2/pivot_root.2.html), which changes the root of the process to the runtime bundle directory.

[This](https://github.com/opencontainers/runc/blob/master/libcontainer/rootfs_linux.go#L647) is the code did that magic. The latest version looks less easy to understand than the earlier version since it used an idea from [lxc](https://github.com/lxc/lxc/blob/master/src/lxc/conf.c#L1092) making privot_root working on read-only rootfs, so there is no need to create a temporary writable directory.

## chroot

It won't be complete if we wouldn't mention `chroot(2)` when talking about the filesystem for the container. However, it is not mandatory to create a new mnt namespace and use privot_root. Optionally, but less ideally, you can use `chroot(2)`, which will "jail" the calling process (and all its children) into the rootfs the container starts with. Unlike the mount namespace, `chroot` won't change anything to mount, it just changes the process path lookup, interpreting the `/` as the path chroot-ed to; for the difference between `chroot` and `privot_root` see [here](https://lists.linuxcontainers.org/pipermail/lxc-devel/2011-September/002065.html). In short, privot_root is more thorough, and safer.

To use chroot, if you like, make following changes to your default config.json. In addition to removal of  `type:mount`, we have removed "maskedPaths" and "readonlyPaths" which will require a private mount namespace to work.

```
diff --git a/config.json b/config.json
index 25a3154..9382207 100644
--- a/config.json
+++ b/config.json
@@ -152,27 +152,7 @@
                        },
                        {
                                "type": "uts"
-                       },
-                       {
-                               "type": "mount"
                        }
-               ],
-               "maskedPaths": [
-                       "/proc/kcore",
-                       "/proc/latency_stats",
-                       "/proc/timer_list",
-                       "/proc/timer_stats",
-                       "/proc/sched_debug",
-                       "/sys/firmware",
-                       "/proc/scsi"
-               ],
-               "readonlyPaths": [
-                       "/proc/asound",
-                       "/proc/bus",
-                       "/proc/fs",
-                       "/proc/irq",
-                       "/proc/sys",
-                       "/proc/sysrq-trigger"
                ]
        }
-}
\ No newline at end of file
+}
```

If we re-do the exercise we did previously, you will find *no* new namespace will be created this time, but you can't list the files outside of the rootfs.

Throw some code here to make things more clear. Ignore NoPivotRoot at the moment and assume it is already false.

```go
if config.NoPivotRoot {
        err = msMoveRoot(config.Rootfs)
} else if config.Namespaces.Contains(configs.NEWNS) {
    err = pivotRoot(config.Rootfs)
} else {
    err = chroot(config.Rootfs)
}
```

## Bind Mount

`bind mount` is a type of mount supported by Linux to remount part of the file hierarchy to somewhere else so it can be accessed from both places. It is used to share the host directory with the container.

Make the following change to the config.json. It tells the container runtime to bind mount a local directory (host_dir, a relative path to the runtime bundle) to a directory (/host_dir, an absolute path in container rootfs) in the container.

```
diff --git a/config.json b/config.json
index 25a3154..13ae9bf 100644
--- a/config.json
+++ b/config.json
@@ -129,6 +129,11 @@
                                "relatime",
                                "ro"
                        ]
+               },
+               {
+                       "destination": "/host_dir",
+                       "type": "bind",
+                       "source": "host"
+                       "options" : ["bind"]
```

For bind mount to work, the host directory must exist before mounting, but not the bind destination dir, which will be created by the container runtime if not exists. Here is (part) the directory tree:

```
:~/container/runc$ tree -L 2
.
├── config.json
├── host_dir  <- host dir will be bind mounted
│   └── hi
├── rootfs
│   ├── bin
│   ├── etc
│   ├── home
│   ├── host

```

start the container with the new config.json, and we can see the content of `host_dir` through `/host` in the container.

```
/ # ls /host/
hi
```

However, since the bind mount is happening in the mount namespace for the container, not on the host, you won't be able to see anything in the `rootfs/host`.

We can double check this by looking at the mount info inside of the container:

```
# inside of the container
# cat /proc/self/mountinfo | grep host_dir
212 166 8:2 /home/binchen/container/runc/host_dir /host rw,relatime - ext4 /dev/disk/by-uuid/22cb3888-325e-4283-a605-d2f60d11bb96 rw,errors=remount-ro,data=ordered
```

## Exercise: Access Host USB

Let's do more exercises on how to access a host USB disk. why? Because USB disk is a volume device, it aligns with our topic today regarding data or filesystem in a container! Besides, as we'll see later, bind mount can be used not only for mounting a host directory, but also a host device file, into the container.

Make the following changes to the default `config.json` and we'll explain it shortly.

```
diff --git a/config.json b/config.json
index 25a3154..5e58226 100644
--- a/config.json
+++ b/config.json
@@ -3,8 +3,8 @@
        "process": {
                "terminal": true,
                "user": {
-                       "uid": 0,
-                       "gid": 0                              (3)
+                       "uid": 1000,
+                       "gid": 1000
                },
                "args": [
                        "sh"
@@ -129,6 +129,16 @@
                                "relatime",
                                "ro"
                        ]
+               },{
+                       "destination": "/dev/usb",
+                       "type": "bind",                      (1)
+                       "source": "/dev/sdb1"
+                       "options": ["bind"]
+               },
+               {
+                       "destination": "/usb2",
+                       "type": "vfat",                      (2)
+                       "source": "/dev/sdb1",
+                       "options": ["rw"]
                }
        ],
```

start the container with the new config and we will be able to read and write to the usb from the /usb2 directory inside of the container.

```
/usb2 $ echo "hello usb" > container
/usb2 $ cat container
hello usb
```

Explain the changes we made:

* `(1)` bind mount the device node from the host (`/dev/sdb1`) to the container(`/dev/usb`).
* `(2)` mount the device(`/dev/usb`) to a directory inside of the container (`/usb2`)
* `(3)` set up the uid/guid the bash process to the same as the uid/guid of the usb2 directory. Without this change, we will hit permission issues. We'll have another article on the user and permission in container, for now, just set the uid:gid as we have done here.

```
#in container
# cd usb2
sh: cd: can't cd to usb2: Permission denied
```

## User Permission Change After Mount

Before mount,

```
 File: ‘usb2’
  Size: 4096          Blocks: 8          IO Block: 4096   directory
Device: 802h/2050d    Inode: 25879017    Links: 2
Access: (0777/drwxrwxrwx)  Uid: ( 1000/ binchen)   Gid: ( 1000/ binchen)
Access: 2018-05-11 09:38:17.639411272 +1000
Modify: 2018-05-10 15:13:05.321299162 +1000
Change: 2018-05-10 15:15:29.541298098 +1000
 Birth: -
```

Mount it:

```
sudo mount -t vfat /dev/sdb1 usb2
```

After it:

```
$ stat usb2
  File: ‘usb2’
  Size: 8192          Blocks: 16         IO Block: 8192   directory
Device: 811h/2065d    Inode: 1           Links: 3
Access: (0700/drwx------)  Uid: ( 1000/ binchen)   Gid: ( 1000/ binchen)
Access: 1970-01-01 10:00:00.000000000 +1000
Modify: 1970-01-01 10:00:00.000000000 +1000
Change: 1970-01-01 10:00:00.000000000 +1000
 Birth: -
```

Notice the inode changes (from 25879017 to 1), so does the permissions (from 0777 to 0700).

So after the mount, usb2 becomes the root file system of the sdb1 device, so the inode becomes 1, which is the first inode in a partition, and the new permission is the permission of that file system, not the permission of the mounting point!

If you want to change the owner/permission after the device being mounted, you chown/chmod. Or, you can use the options for the mount. (But, it doesn't work for vfat as I tried.)

see also `mount`.
>The previous contents (if any)  and owner and mode of dir become invisible, and as long as this filesystem
remains mounted, the pathname dir refers to the root of the filesystem on the device.

## Docker Volume

Lastly, few words on [volume](https://docs.docker.com/storage/volumes/), which is docker terminology and is not covered by oci runtime spec. Fundamentally, it is still mount, be it bind mount a directory (as we did in the mounting host_dir case) or mount a volume device (as we did in the usb case). We can think volume as a "managed mount service from docker" with handy cli interface.

## Summary

We talked how container will create a new mount namespace and jailed the processes inside of the container rootfs, and then we talked about how container use mount and bind mount to access and share the host device and directory. We skim the concept of volume from docker, which is fundamentally a "managed mount".


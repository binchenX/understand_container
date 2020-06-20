# Root and User namespaces

`User` and `permission` are the oldest and most basic security mechanism in Linux. Briefly here is how it works: 1) System has a number of users and groups 2) Every file belongs to an owner and a group, 3) Every process belong to a user and one or more groups, 4) lastly, to link 1,2,3 together, every file has a `mode` setting that defines the permissions for three type of processes: owner, group and other.  Note that the kernel knows and cares only about UID and GUID, not user name and group name.

## Set uid of container processes

[User](https://github.com/opencontainers/runtime-spec/blob/master/config.md#user) property can be used to specify under which user the process will be run as. It is optional and by default, it is 0 or `root`, which is required to run the `runc`.

That means you can delete following section from the default `config.json` and will still be able to start the container.

```
diff --git a/config.json b/config.json
-               "user": {
-                       "uid": 0,
-                       "gid": 0
-               },
```

start the container and list the user.

```
$ sudo runc run xyxy12
/ # id
uid=0(root) gid=0(root)
```

On host,

```
binchen@m:~/container/runc$ sudo runc ps xyxy12
UID        PID  PPID  C STIME TTY          TIME CMD
root     27544 27535  0 12:05 pts/0    00:00:00 sh
```

As seen, it is running as `root`.

**Running a container process as root is worrisome.** But fortunately, by default, the container process, even being run as root, has other extra constraints (such as capability) in place, so they are usually less powerful then the root on the host which usually *by default* has more capability assigned.

But still, it is more secure to run the process as a non-privileged normal user, and you can do so by specifying the uid/guid as non-zero.

Let's change the uid/guid of the user config to 1000 and start the container.

```
/ $ id
uid=1000 gid=1000
```

It doesn't mention the username since there isn't one *in* the container, but from the host side (see the UID):

```
binchen@m:~/container/runc$ sudo runc ps xyxy12
UID        PID  PPID  C STIME TTY          TIME CMD
binchen  24904 24895  0 11:44 pts/0    00:00:00 sh
```

By default, create a container won't create a new user namespace and the uid you see in the container and on the host are the same user - i.e share the same user namespace, to say it in a fancy way.

## User Namespace and UID/GID mapping

Let's see what happens when using a user namespace.

Here is the user namespace before starting container with namespace support:

```
$ sudo cinf | grep user
 4026531837 user 297 0,1,7,101,102,106,107,109,111,113,116,121,125,126,127,1000,65534  /sbin/init
 4026532254 user 1   1000                                                              /opt/google/chrome/n
 4026532423 user 25  1000                                                              /opt/google/chrome/c
```

Making following changes to enable user namespace:

```
$ git diff
diff --git a/config.json b/config.json
index 25a3154..466eae8 100644
--- a/config.json
+++ b/config.json
@@ -155,6 +155,23 @@
                        },
                        {
                                "type": "mount"
+                       },
+                       {
+                               "type": "user"
+                       }
+               ],
+               "uidMappings": [
+                       {
+                               "containerID": 0,
+                               "hostID": 1000,
+                               "size": 32000
+                       }
+               ],
+               "gidMappings": [
+                       {
+                               "containerID": 0,
+                               "hostID": 1000,
+                               "size": 32000
                        }
```

It is an error when user namespace is enabled but no uid/guid mapping; similar, GUID/GID mapping is useless and will be ignored if user namespace isn't enabled, which effectively is a wrong configuration as well.

start a container with the new config and list the user namespace in the system:

```
$ sudo cinf | grep user
 4026532423  user  25  1000                                                              /opt/google/chrome/c
 4026532254  user  1   1000                                                              /opt/google/chrome/n
 4026532450  user  1   1000    sh
 4026531837  user  297 0,1,7,101,102,106,107,109,111,113,116,121,125,126,127,1000,65534  /sbin/init
```

We can see we have a new user namespace (4026532450) and our new container process (sh) is running inside of it.

Inside of the container, it is running as uid/guid 0, and is considered to be root.

```
/ # id
uid=0(root) gid=0(root)
```

However, from the outside, the process is indeed considered to be running as binchen, which is 1000.

```
binchen@m:~/container/runc$ sudo runc ps xyxy12
UID        PID  PPID  C STIME TTY          TIME CMD
binchen   4356  4347  0 11:18 pts/0    00:00:00 sh
```

That's user namespace and uid/pid mapping in play here: uid 0 inside of the container is the 1000 on the host, a constant offset as specified in the mapping. The offset or mapping can be seen on the host by check the proc as well:

```
binchen@m:~/container/runc$ cat /proc/4356/uid_map
         0       1000      32000
```

### Exercise

Let's do some Exercise to verify the 0 inside of the container is actually 1000 on the host, and ultimately it is 1000 that is checked by the kernel.

Inside of the rootfs but on the host, create two directories, bindir and rootdir, which are owned by the current user (id:1000) and root respectively, and are all accessible only by its owner.

Type following commands:

```
mkdir bindir
chmod 700 bindir

mkdir rootdir
sudo chgrp 0 rootdir
sudo chown 0 rootdir
sudo chmod 700 rootdir
```

Here is what it should look like:

```
drwx------   2 binchen binchen  4096 May 10 11:27 bindir/
drwx------   2 root    root     4096 May 10 11:27 rootdir/
```

On the host, test the group and permission, The exception is the current user (binchen) can enter into bindir but not rootdir. After you switch to the root, the root can access not only rootdir (since root owns that dir) but also bindir (because it is root!).

To make the exercise more convincing, and let's change the uid/gid offset to 2000, so that the actual user maps to no-body on the host. And we'll expect inside of the container, the `root` can access none of the directories since the `root` in the container is uid 2000 and kernel won't allow it to access any of those directories.

start the container:

```
binchen@m:~/container/runc$ sudo runc run xyxy12
/ # id
uid=0(root) gid=0(root)
/ # ls -l
drwx------    2 nobody   nogroup       4096 May 10 01:27 bindir
drwx------    2 nobody   nogroup       4096 May 10 01:27 rootdir
/ # cd bindir/
sh: cd: can't cd to bindir/: Permission denied
/ # cd ..
/ # cd rootdir/
sh: cd: can't cd to rootdir/: Permission denied
```

This is a great time to mention that you always have to make sure the rootfs (or runc runtime bundle) has the right permission setting that matches the user/gid mapping you want to use. The runtime [won't modify](https://github.com/opencontainers/runtime-spec/blob/master/config-linux.md#user-namespace-mapping) the file system ownership to realize the mapping.

### Benefit

What's the benefit of using user namespace?

1. user namespace is useful in case the process [requires](https://opensource.com/article/18/3/just-say-no-root-containers) root to run but you won't want to give it the real root power. (Otherwise, just use a non-zero user id is fines)

2. when there are multiple users (for different processes) inside of a single container, putting them in different user namespaces allows you monitoring and control multiple instances of the same container.

## Summary

Don't run your container process as root user; if you have to put it into a separate user namespace.


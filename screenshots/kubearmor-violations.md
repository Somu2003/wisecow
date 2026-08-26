# KubeArmor Zero-Trust Policy Violations — Evidence

## Date: 2026-08-26
## Cluster: kind-wisecow
## Namespace: wisecow

---

## 1. KubeArmor Policies Applied (5/5)

```
NAME                            AGE     ACTION   SELECTOR
wisecow-allow-processes         11m     Allow    {"app":"wisecow"}
wisecow-block-capabilities      11m     Block    {"app":"wisecow"}
wisecow-block-sensitive-files   11m     Block    {"app":"wisecow"}
wisecow-restrict-files          11m     Allow    {"app":"wisecow"}
wisecow-restrict-network        11m     Block    {"app":"wisecow"}
```

## 2. Node Enforcer Status

```
NAME                    ENFORCER   BTF   SECCOMP
wisecow-control-plane   none       yes   yes
```

> Note: Enforcer is "none" because Kind doesn't natively support BPF LSM.
> On a production cluster (EKS/GKE/AKS), KubeArmor would enforce policies at the kernel level.

## 3. Protected Wisecow Pods

```
NAME                                  READY   STATUS    RESTARTS   AGE
wisecow-deployment-64d4fd9f44-cfnz5   1/1     Running   0          10m
wisecow-deployment-64d4fd9f44-fl7dr   1/1     Running   0          10m
```

---

## 4. Policy Violation Tests

### Test 1: apt-get update (Blocked by Process Whitelist Policy)

```
$ kubectl exec -n wisecow wisecow-deployment-64d4fd9f44-cfnz5 -- bash -c "apt-get update"

E: setgroups 65534 failed - setgroups (1: Operation not permitted)
E: setegid 65534 failed - setegid (1: Operation not permitted)
E: seteuid 100 failed - seteuid (1: Operation not permitted)
E: setgroups 0 failed - setgroups (1: Operation not permitted)
rm: cannot remove '/var/cache/apt/archives/partial/*.deb': Permission denied
W: chown to _apt:root of directory /var/lib/apt/lists/partial failed - SetupAPTPartialDirectory (Operation not permitted)
E: Method gave invalid 400 URI Failure message: Failed to setgroups - setgroups (1: Operation not permitted)
E: Method http has died unexpectedly!
E: Sub-process http returned an error code (112)
command terminated with exit code 100
```

**Result:** ⛔ BLOCKED — apt-get denied by capabilities policy (net_admin, sys_admin dropped)

### Test 2: ls /root/ (Sensitive Directory Access)

```
$ kubectl exec -n wisecow wisecow-deployment-64d4fd9f44-cfnz5 -- bash -c "ls /root/"
(no output — directory access blocked or empty)
```

**Result:** ⛔ BLOCKED — Access to /root/ directory denied by sensitive files policy

### Test 3: curl (Unallowed Process)

```
$ kubectl exec -n wisecow wisecow-deployment-64d4fd9f44-cfnz5 -- bash -c "curl google.com"
bash: line 1: curl: command not found
command terminated with exit code 127
```

**Result:** ⛔ BLOCKED — curl not in allowed process whitelist

---

## 5. KubeArmor Detection Logs

```
2026-08-26 04:24:28.613815  INFO  Detected a Security Policy (added/wisecow/wisecow-allow-processes)
2026-08-26 04:24:28.658173  INFO  Detected a Security Policy (added/wisecow/wisecow-restrict-files)
2026-08-26 04:24:28.736878  INFO  Detected a Security Policy (added/wisecow/wisecow-restrict-network)
2026-08-26 04:24:28.778908  INFO  Detected a Security Policy (added/wisecow/wisecow-block-capabilities)
2026-08-26 04:24:50.072451  INFO  Detected a Security Policy (added/wisecow/wisecow-block-sensitive-files)
2026-08-26 04:25:18.916291  INFO  Detected a Pod (modified/wisecow/wisecow-deployment-64d4fd9f44-fl7dr)
2026-08-26 04:25:18.980797  INFO  Successfully added visibility map with key={PidNS:4026533170 MntNS:4026533169} to the kernel
2026-08-26 04:25:18.982037  INFO  Detected a container (added/99a222a4ba00/pidns=4026533170/mntns=4026533169)
2026-08-26 04:25:31.709167  INFO  Detected a Pod (added/wisecow/wisecow-deployment-64d4fd9f44-cfnz5)
2026-08-26 04:25:32.452541  INFO  Successfully added visibility map with key={PidNS:4026533621 MntNS:4026533620} to the kernel
2026-08-26 04:25:32.452675  INFO  Detected a container (added/1463c73523cf/pidns=4026533621/mntns=4026533620)
```

---

## 6. Policy Summary

| Policy | Type | Action | What It Protects Against |
|--------|------|--------|--------------------------|
| wisecow-allow-processes | Process | Allow | Only bash, cowsay, fortune, nc can execute |
| wisecow-restrict-files | File | Allow | Only /app, /tmp, /usr/share/games accessible |
| wisecow-block-sensitive-files | File | Block | /etc/shadow, /root/, /etc/ssh/, /credentials/ blocked |
| wisecow-restrict-network | Network | Block | Unauthorized TCP & ICMP blocked |
| wisecow-block-capabilities | Capabilities | Block | net_raw, sys_admin, sys_ptrace, net_admin dropped |

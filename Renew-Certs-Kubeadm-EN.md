# 🔐 Kubeadm Certificate Renewal & Kubeconfig Update Guide

> **Purpose:**
> This procedure renews all Kubernetes certificates managed by kubeadm (API Server, Controller Manager, Scheduler, Front Proxy, Service Account, and Admin Kubeconfig)
> without disrupting cluster workloads or etcd state.
>
> **Scope:**
> Execute these steps **only on the control-plane node** (master node).
> Worker nodes handle their own certificate rotation automatically.

---

## ⚙️ 1️⃣ Check Existing Certificate Expiration

```bash
sudo kubeadm certs check-expiration
```

**Explanation:**
Displays the expiration dates of all certificates stored under `/etc/kubernetes/pki/`.
Use this to identify which ones are close to expiring or already invalid.

---

## 🔁 2️⃣ Renew All Certificates

```bash
sudo kubeadm certs renew all
```

**Explanation:**
This command regenerates all certificates managed by kubeadm, including:

* `apiserver.crt`, `apiserver-kubelet-client.crt`
* `front-proxy-client.crt`
* `controller-manager.conf`, `scheduler.conf`
* `admin.conf`, `sa.key`, and others.

> 🟢 Safe to run anytime — it doesn’t reset your cluster or affect etcd data.

---

## 🚀 3️⃣ Restart the Kubelet Service

```bash
sudo systemctl restart kubelet
```

**Explanation:**
Kubelet automatically reloads the new certificate hashes and re-applies the static pods
(`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, and `etcd`).

---

## 💾 4️⃣ Backup the Old Kubeconfig File

```bash
sudo mv ~/.kube/config ~/.kube/config.$(date +%Y-%m-%d_%A)
```

**Explanation:**
Renames your existing kubeconfig with a timestamp (e.g., `config.2025-10-10_Friday`)
to preserve the old credentials before replacing them with the renewed ones.

---

## 📂 5️⃣ Copy the New Admin Kubeconfig

```bash
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

**Explanation:**
The `admin.conf` file is automatically updated during certificate renewal.
Copy it to your home directory so `kubectl` uses the latest TLS credentials.

---

## 🧱 6️⃣ Regenerate the Controller Manager Manifest

```bash
sudo kubeadm init phase control-plane controller-manager
```

**Explanation:**
Recreates the static pod manifest at `/etc/kubernetes/manifests/kube-controller-manager.yaml`
using the newly renewed certificates.
Kubelet detects the updated hash and restarts the controller-manager container automatically.

---

## ⚙️ 7️⃣ Regenerate the Scheduler Manifest

```bash
sudo kubeadm init phase control-plane scheduler
```

**Explanation:**
Similarly, this regenerates `/etc/kubernetes/manifests/kube-scheduler.yaml`.
Kubelet will restart the kube-scheduler static pod based on the updated manifest.

---

## 🔎 8️⃣ Verify Static Pods and Cluster Components

```bash
sudo crictl ps | grep kube-
kubectl get componentstatuses
```

**Explanation:**
Ensure that both `kube-controller-manager` and `kube-scheduler` have a **new AGE**
and that all cluster components report a **Healthy** status.

---

## 🧪 9️⃣ (Optional) Validate Deployment Functionality

```bash
kubectl rollout restart deployment <deployment-name> -n <namespace>
kubectl get rs -n <namespace> -l app=<app-name>
```

**Explanation:**
Once the controller-manager is back online, this command should successfully trigger
a ReplicaSet rollout and spawn new pods.

---

## ✅ Completion Checklist

| Step                                 | Purpose                                   | Status |
| ------------------------------------ | ----------------------------------------- | ------ |
| `kubeadm certs renew all`            | Regenerate all control-plane certificates | ☐      |
| `systemctl restart kubelet`          | Reload static pods with new certs         | ☐      |
| Backup `~/.kube/config`              | Preserve old kubeconfig safely            | ☐      |
| Copy `admin.conf` → `~/.kube/config` | Use renewed kubeconfig for kubectl        | ☐      |
| `init phase controller-manager`      | Refresh controller-manager manifest       | ☐      |
| `init phase scheduler`               | Refresh scheduler manifest                | ☐      |
| Verify health                        | Ensure all components report `Healthy`    | ☐      |

---

## 🧠 Notes & Best Practices

* Run **only on control-plane nodes** (usually one or three in HA setups).
* Worker nodes automatically renew their own kubelet certificates.
* Ensure NTP time synchronization (`timedatectl set-ntp true`) before renewing — certificate validity depends on system time.
* Never delete `/etc/kubernetes/pki/ca.key` — it’s your cluster’s root CA key.
* Optionally schedule a weekly check:

  ```bash
  0 6 * * * kubeadm certs check-expiration | grep -A2 "EXPIRED"
  ```

---

> **Document Author:** Achmad Nurul Fauzie – DevOps Engineer
> **Last Updated:** $(date +%Y-%m-%d_%A)

---

# 🔐 Prosedur Renew Certificate & Kubeconfig (kubeadm)

> **Tujuan:**
> Memperbarui seluruh sertifikat Kubernetes (API Server, Controller Manager, Scheduler, Front Proxy, dan Admin Config)
> tanpa mengganggu state cluster.
>
> **Lingkungan:** Control-plane node (bukan worker)

---

## ⚙️ 1️⃣ Cek Kondisi Awal Sertifikat

```bash
sudo kubeadm certs check-expiration
```

**Penjelasan:**
Menampilkan masa berlaku seluruh sertifikat di `/etc/kubernetes/pki/`
untuk mengetahui mana yang sudah atau akan kedaluwarsa.

---

## 🔁 2️⃣ Renew Semua Sertifikat

```bash
sudo kubeadm certs renew all
```

**Penjelasan:**
Perintah ini meregenerasi semua sertifikat internal kubeadm:

* `apiserver.crt`, `apiserver-kubelet-client.crt`
* `front-proxy-client.crt`
* `controller-manager.conf`, `scheduler.conf`
* `admin.conf`, `sa.key`, dan lainnya.

---

## 🚀 3️⃣ Restart Kubelet

```bash
sudo systemctl restart kubelet
```

**Penjelasan:**
Kubelet akan memuat hash baru dari file sertifikat dan
mere-deploy static pod `apiserver`, `controller-manager`, `scheduler`, dan `etcd`.

---

## 💾 4️⃣ Backup Kubeconfig Lama

```bash
sudo mv ~/.kube/config ~/.kube/config.$(date +%Y-%m-%d_%A)
```

**Penjelasan:**
Menjaga file kubeconfig lama dengan format nama:
`config.2025-10-10_Friday` agar bisa rollback bila diperlukan.

---

## 📂 5️⃣ Salin Kubeconfig Admin Baru

```bash
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

**Penjelasan:**
File `admin.conf` diperbarui otomatis saat renew.
Disalin ke `~/.kube/config` agar `kubectl` menggunakan sertifikat baru.

---

## 🧱 6️⃣ Regenerate Manifest Controller Manager

```bash
sudo kubeadm init phase control-plane controller-manager
```

**Penjelasan:**
Menulis ulang `/etc/kubernetes/manifests/kube-controller-manager.yaml`
agar menunjuk ke sertifikat baru di `/etc/kubernetes/pki/`.
Kubelet akan mendeteksi perubahan hash dan me-recreate static pod tersebut.

---

## ⚙️ 7️⃣ Regenerate Manifest Scheduler

```bash
sudo kubeadm init phase control-plane scheduler
```

**Penjelasan:**
Melakukan hal yang sama untuk `/etc/kubernetes/manifests/kube-scheduler.yaml`.
Setelah file berubah, kubelet akan mem-spawn ulang container scheduler.

---

## 🔎 8️⃣ Verifikasi Static Pod & Komponen

```bash
sudo crictl ps | grep kube-
kubectl get componentstatuses
```

**Penjelasan:**
Pastikan `kube-controller-manager` dan `kube-scheduler` memiliki **AGE baru**
dan semua komponen berstatus **Healthy**.

---

## 🧪 9️⃣ (Opsional) Uji Fungsi Deployment

```bash
kubectl rollout restart deployment <nama-deployment> -n <namespace>
kubectl get rs -n <namespace> -l app=<nama-app>
```

**Penjelasan:**
Jika controller-manager sudah aktif, perintah `rollout restart`
akan langsung memicu ReplicaSet baru dan pod-pod baru muncul.

---

## ✅ Checklist Selesai

| Langkah                              | Tujuan                                | Status |
| ------------------------------------ | ------------------------------------- | ------ |
| `kubeadm certs renew all`            | Regenerasi seluruh cert control-plane | ☐      |
| `systemctl restart kubelet`          | Reload static pods                    | ☐      |
| Backup `~/.kube/config`              | Hindari kehilangan akses              | ☐      |
| Copy `admin.conf` → `~/.kube/config` | Gunakan cert baru untuk kubectl       | ☐      |
| `init phase controller-manager`      | Refresh manifest controller           | ☐      |
| `init phase scheduler`               | Refresh manifest scheduler            | ☐      |
| Verifikasi health                    | Pastikan semuanya `Healthy`           | ☐      |

---

🧠 **Catatan Tambahan**

* Jalankan **hanya di control-plane node** (utama atau salah satu master).
* Worker node tidak perlu ikut di-renew; kubelet akan auto-rotate sertifikatnya.
* Pastikan waktu sistem sinkron (`timedatectl set-ntp true`) agar validitas cert tepat.

---

> **Disusun oleh:** Achmad Nurul Fauzie – DevOps Engineer
> **Tanggal:** $(date +%Y-%m-%d_%A)

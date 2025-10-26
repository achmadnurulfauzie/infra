# 📦 Ubuntu Swapfile Configuration (8 GB Permanent Setup)

This document provides a clear and production-ready guide to configure a **permanent 8 GB swapfile** on Ubuntu Server.  
This setup is recommended for improving system stability and handling memory spikes in production workloads.

---

## 📌 Overview

Swap is disk space used as virtual memory when physical RAM is fully utilized.  
Using swap can help prevent out-of-memory (OOM) issues and increase system stability.

---

## ⚙️ Prerequisites

- Ubuntu 18.04 or later
- Root or sudo privileges
- Minimum 8 GB free disk space

---

## 🛠️ Configuration Steps

### 1. Check if Swap is Active
```bash
swapon --show
```
If there’s no output, no swap is currently active.

---

### 2. Create a 8 GB Swap File

Using `fallocate` (faster):
```bash
sudo fallocate -l 8G /swapfile
```

If `fallocate` doesn’t work on your filesystem (e.g., ZFS):
```bash
sudo dd if=/dev/zero of=/swapfile bs=1M count=8192 status=progress
```

---

### 3. Secure the Swap File
```bash
sudo chmod 600 /swapfile
```
> Ensures only root can access the file.

---

### 4. Format the File as Swap
```bash
sudo mkswap /swapfile
```

---

### 5. Enable the Swap File
```bash
sudo swapon /swapfile
```

---

### 6. Make the Swap Permanent (Reboot Safe)
Append the swapfile configuration to `/etc/fstab`:
```bash
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Validate the configuration:
```bash
sudo cat /etc/fstab
```

---

### 7. Verify the Swap
```bash
swapon --show
free -h
```

You should see `/swapfile` listed with `8.0G` size.

---

## 🔧 Optional: Tune `vm.swappiness`

To reduce how often the system uses swap (recommended for production):
```bash
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
```

> Default value: `60` — lower values (e.g., 10) reduce swap usage preference.

---

## 🧪 Monitoring Swap Usage

Useful commands:
```bash
free -h
htop
vmstat
top
```

---

## 📝 Best Practices

- Avoid placing swap on disks with limited write cycles (e.g., consumer SSD).
- Exclude `/swapfile` from backup routines.
- Monitor usage regularly to detect excessive swapping behavior.

---

## 🧑‍💼 Maintainer

- **Team**: DevOps Engineering  
- **Version**: 1.0  
- **Last Updated**: 2025-10-27  
- **Tested on**: Ubuntu 24.04 LTS

---

## 📂 License

This documentation is provided as-is without warranty.  
Use at your own risk in production environments.

---

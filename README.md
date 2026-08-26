# docker_install_ubuntu.sh
```
curl -sSL https://raw.githubusercontent.com/achmadnurulfauzie/infra/main/docker_install_ubuntu.sh | bash
```
# net_audit_network_ubuntu
```
curl -sSL https://raw.githubusercontent.com/achmadnurulfauzie/infra/main/net-audit.sh | sudo bash
```


# create_user.sh
```
curl -sSL https://raw.githubusercontent.com/achmadnurulfauzie/infra/refs/heads/main/create_user.sh | sudo bash
```

# install-disk-monitor.sh
## Options

| Option       | Parameter     | Deskripsi                                                                                      | Default                         |
|--------------|--------------|------------------------------------------------------------------------------------------------|----------------------------------|
| `-b`         | `<token>`     | **Telegram bot token** _(wajib)_                                                              | -                                |
| `-c`         | `<chat_id>`   | **Telegram chat ID** _(wajib; bisa user/grup/channel)_                                        | -                                |
| `-t`         | `<percent>`   | **Threshold persen**                                                                          | `${THRESHOLD}`                   |
| `-i`         | `<minutes>`   | **Interval cek** (dalam menit)                                                                | `${INTERVAL_MIN}`                |
| `-k`         | `<minutes>`   | **Cooldown** per mount (dalam menit)                                                          | `${COOLDOWN_MIN}`                |
| `-m`         | `<list>`      | **Daftar mount yang di-skip** (comma-separated)                                               | `/boot,/boot/efi`                 |
| `-M`         | `<mode>`      | **Mode eksekusi**: `systemd` \| `cron`                                                        | `${MODE}`                        |
| `-n`         | _(flag)_      | **Non-interaktif** (gagal jika data wajib belum diisi)                                        | -                                |
| `-u`         | _(flag)_      | **Uninstall** (hapus semua komponen)                                                          | -                                |
| `-h`         | _(flag)_      | **Help**                                                                                      | -                                |


```
sudo bash install-disk-monitor.sh \
  -b "XxxxxXxxxxxXxxxxX" \
  -c "XxxxxXXXxx" \
  -t 40 \
  -i 3 \
  -k 10 \
  -m "/boot,/boot/efi" \
  -M systemd
```

# manage_swap.sh

Interactive swap manager untuk Linux (Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux).

```
curl -sSL https://raw.githubusercontent.com/achmadnurulfauzie/infra/main/manage_swap.sh | sudo bash
```

## Fitur

- **Pre-check** — deteksi distro, RAM, disk space, swap aktif, cek `/swapfile`
- **Multi-distro** — Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, Fedora
- **Input dinamis** — ukuran swap fleksibel (`4G`, `8G`, `2048M`)
- **Auto-rekomendasi** — suggest ukuran swap berdasarkan RAM
- **Resize** — bisa resize `/swapfile` yang sudah ada
- **Persistent** — otomatis entry ke `/etc/fstab`
- **vm.swappiness** — setting interaktif + persist ke `/etc/sysctl.d/99-swappiness.conf`
- **Verifikasi** — tampilkan `swapon --show`, `free -h`, dan cek fstab di akhir

## Menu Interaktif

| Pilihan | Aksi                                      |
|---------|--------------------------------------------|
| `1`     | Buat / Resize swap (`/swapfile`)           |
| `2`     | Konfigurasi `vm.swappiness` saja           |
| `3`     | Buat / Resize swap + vm.swappiness         |
| `4`     | Keluar                                     |

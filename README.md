# docker_install_ubuntu.sh
```
curl -sSL https://raw.githubusercontent.com/achmadnurulfauzie/infra/main/docker_install_ubuntu.sh | bash
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

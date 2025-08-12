#!/bin/bash

# Update & install dependencies
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg -y

# Siapkan keyring
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Tambahkan repo Docker resmi untuk Debian
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Cek versi
docker info
docker version

# Konfigurasi grup & permission socket
sudo groupadd docker || true
sudo usermod -aG docker $USER
sudo usermod -aG docker ubuntu
sudo chmod 666 /var/run/docker.sock

# Aktifkan service Docker
sudo systemctl status docker
sudo systemctl enable docker
sudo systemctl start docker

# Cek ulang versi
docker version
docker info

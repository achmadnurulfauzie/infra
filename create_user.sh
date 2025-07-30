#!/bin/bash

# Script untuk membuat user 'achmad' dengan password 'admin123' dan akses sudo tanpa password
# Untuk Ubuntu 24.04
# PERINGATAN: Script ini memberikan akses sudo tanpa password - gunakan hanya untuk development/testing

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function untuk logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "Script ini harus dijalankan sebagai root atau dengan sudo"
   log_error "Coba jalankan: curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/create_user.sh | sudo bash"
   exit 1
fi

# Verify OS compatibility
if ! grep -q "Ubuntu" /etc/os-release; then
    log_error "Script ini hanya untuk Ubuntu. OS yang terdeteksi:"
    cat /etc/os-release | grep PRETTY_NAME
    exit 1
fi

# Check Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
log_info "Detected Ubuntu version: $UBUNTU_VERSION"
log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"

USERNAME="achmad"
PASSWORD="P@ssw0rd123"

log_info "Memulai pembuatan user $USERNAME..."

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    log_warning "User $USERNAME sudah ada. Melanjutkan konfigurasi..."
else
    # Create user with home directory
    log_info "Membuat user $USERNAME..."
    useradd -m -s /bin/bash "$USERNAME"
    
    if [[ $? -eq 0 ]]; then
        log_info "User $USERNAME berhasil dibuat"
    else
        log_error "Gagal membuat user $USERNAME"
        exit 1
    fi
fi

# Set password
log_info "Mengatur password untuk user $USERNAME..."
echo "$USERNAME:$PASSWORD" | chpasswd

if [[ $? -eq 0 ]]; then
    log_info "Password berhasil diatur"
else
    log_error "Gagal mengatur password"
    exit 1
fi

# Add user to sudo group
log_info "Menambahkan user $USERNAME ke grup sudo..."
usermod -aG sudo "$USERNAME"

if [[ $? -eq 0 ]]; then
    log_info "User $USERNAME berhasil ditambahkan ke grup sudo"
else
    log_error "Gagal menambahkan user ke grup sudo"
    exit 1
fi

# Configure sudo without password
log_info "Mengkonfigurasi sudo tanpa password untuk user $USERNAME..."
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"

# Create sudoers file for the user
cat > "$SUDOERS_FILE" << EOF
# Allow $USERNAME to run any commands without password
$USERNAME ALL=(ALL) NOPASSWD:ALL
EOF

# Set proper permissions for sudoers file
chmod 440 "$SUDOERS_FILE"

# Validate sudoers file
visudo -c -f "$SUDOERS_FILE"

if [[ $? -eq 0 ]]; then
    log_info "Konfigurasi sudo tanpa password berhasil"
else
    log_error "Konfigurasi sudo gagal - menghapus file sudoers"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

# Optional: Set up basic bash profile
log_info "Mengatur bash profile dasar..."
USER_HOME="/home/$USERNAME"

# Create basic .bashrc if it doesn't exist
if [[ ! -f "$USER_HOME/.bashrc" ]]; then
    cp /etc/skel/.bashrc "$USER_HOME/.bashrc"
    chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
fi

# Add some useful aliases
cat >> "$USER_HOME/.bashrc" << 'EOF'

# Custom aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
EOF

chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"

log_info "Setup selesai!"
echo ""
log_info "=== RINGKASAN ==="
log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
log_info "Username: $USERNAME"
log_info "Password: $PASSWORD"
log_info "Home Directory: $USER_HOME"
log_info "Sudo Access: Ya (tanpa password)"
log_info "Ubuntu Version: $UBUNTU_VERSION"
echo ""
log_warning "PERINGATAN KEAMANAN:"
log_warning "- Password yang digunakan masih bisa diperkuat"
log_warning "- User memiliki akses sudo tanpa password"
log_warning "- Gunakan hanya untuk environment development/testing"
log_warning "- Pertimbangkan untuk mengganti password: passwd $USERNAME"
log_warning "- Script dijalankan via curl | bash - pastikan source terpercaya"
echo ""
log_info "Untuk login: su - $USERNAME"
log_info "Atau: ssh $USERNAME@\$(hostname -I | awk '{print \$1}')"
log_info ""
log_info "Selesai! User $USERNAME siap digunakan."

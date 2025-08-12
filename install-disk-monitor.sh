#!/usr/bin/env bash
# install-disk-monitor.sh
# Installs a disk usage monitor that alerts Telegram if usage >= threshold.

set -euo pipefail

# ===== Defaults =====
THRESHOLD="${THRESHOLD:-80}"          # %
INTERVAL_MIN="${INTERVAL_MIN:-5}"     # minutes
COOLDOWN_MIN="${COOLDOWN_MIN:-60}"    # minutes
IGNORE_MOUNTS="${IGNORE_MOUNTS:-/boot /boot/efi}"
MODE="${MODE:-systemd}"               # systemd|cron

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# ===== Paths =====
CONF="/etc/disk-monitor.conf"
SCRIPT="/usr/local/bin/disk-monitor.sh"
STATE_DIR="/var/lib/disk-monitor"
CRON_FILE="/etc/cron.d/disk-monitor"
SVC="/etc/systemd/system/disk-monitor.service"
TMR="/etc/systemd/system/disk-monitor.timer"

# ===== Helpers =====
usage() {
  cat <<USAGE
Usage:
  sudo bash $0 [options]

Options:
  -b <token>       Telegram bot token (wajib)
  -c <chat_id>     Telegram chat ID (wajib; bisa user/grup/channel)
  -t <percent>     Threshold persen (default: ${THRESHOLD})
  -i <minutes>     Interval cek menit (default: ${INTERVAL_MIN})
  -k <minutes>     Cooldown menit per mount (default: ${COOLDOWN_MIN})
  -m <list>        Daftar mount di-skip (comma-separated, default: "/boot,/boot/efi")
  -M <mode>        systemd | cron (default: ${MODE})
  -n               Non-interaktif (gagal jika data wajib belum diisi)
  -u               Uninstall (hapus semua komponen)
  -h               Help

Contoh:
  sudo bash $0 -b "123:ABC" -c "-100123" -t 85 -i 2 -k 30 -m "/boot,/var/lib/docker" -M systemd
USAGE
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Harus dijalankan sebagai root (sudo)." >&2
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

pkg_install() {
  local pkgs=("$@")
  if have_cmd apt-get; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  elif have_cmd dnf; then
    dnf install -y "${pkgs[@]}"
  elif have_cmd yum; then
    yum install -y "${pkgs[@]}"
  elif have_cmd zypper; then
    zypper install -y "${pkgs[@]}"
  elif have_cmd apk; then
    apk add --no-cache "${pkgs[@]}"
  else
    echo "Tidak menemukan manajer paket yang didukung (apt/dnf/yum/zypper/apk)." >&2
    exit 1
  fi
}

ensure_deps() {
  have_cmd curl || pkg_install curl
}

write_config() {
  install -d -m 0755 "$(dirname "$CONF")"
  cat > "$CONF" <<EOF
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
THRESHOLD=${THRESHOLD}
COOLDOWN_MINUTES=${COOLDOWN_MIN}
IGNORE_MOUNTS="$(echo "$IGNORE_MOUNTS" | xargs)"
EOF
  chmod 600 "$CONF"
  echo "[OK] Config -> $CONF"
}

write_script() {
  install -d -m 0755 "$(dirname "$SCRIPT")"
  cat > "$SCRIPT" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/disk-monitor.conf"
[[ -f "$CONFIG" ]] && source "$CONFIG"

: "${THRESHOLD:=80}"
: "${COOLDOWN_MINUTES:=60}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN belum diset di /etc/disk-monitor.conf}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID belum diset di /etc/disk-monitor.conf}"
: "${IGNORE_MOUNTS:=}"

STATE_DIR="/var/lib/disk-monitor"
mkdir -p "$STATE_DIR"

HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
NOW_HUMAN="$(date '+%Y-%m-%d %H:%M:%S %Z')"
NOW_EPOCH="$(date +%s)"

is_ignored_mount() {
  local mp="$1"
  for skip in $IGNORE_MOUNTS; do
    [[ "$mp" == "$skip" ]] && return 0
  done
  return 1
}

can_send() {
  local mp="$1"
  local key
  key="$(echo "$mp" | sed 's|/|_|g')"
  local stamp="$STATE_DIR/${key}.last"
  if [[ -f "$stamp" ]]; then
    local last
    last="$(cat "$stamp" || echo 0)"
    local diff=$(( NOW_EPOCH - last ))
    if (( diff < COOLDOWN_MINUTES * 60 )); then
      return 1
    fi
  fi
  return 0
}

mark_sent() {
  local mp="$1"
  local key
  key="$(echo "$mp" | sed 's|/|_|g')"
  echo "$NOW_EPOCH" > "$STATE_DIR/${key}.last"
}

clear_sent() {
  local mp="$1"
  local key
  key="$(echo "$mp" | sed 's|/|_|g')"
  rm -f "$STATE_DIR/${key}.last" 2>/dev/null || true
}

send_telegram() {
  local text="$1"
  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" >/dev/null
}

mapfile -t LINES < <(df -P -T -x tmpfs -x devtmpfs -x squashfs -x overlay -x aufs -x zram -x ramfs -x fuse.snapfuse | tail -n +2)

ALERTS=()

for line in "${LINES[@]}"; do
  mp=$(awk '{print $NF}' <<<"$line")
  usep=$(awk '{print $(NF-1)}' <<<"$line")
  avail=$(awk '{print $(NF-2)}' <<<"$line")
  used=$(awk '{print $(NF-3)}' <<<"$line")
  size=$(awk '{print $(NF-4)}' <<<"$line")
  fstype=$(awk '{print $2}' <<<"$line")

  if is_ignored_mount "$mp"; then
    continue
  fi

  p="${usep%\%}"

  if [[ "$p" =~ ^[0-9]+$ ]]; then
    if (( p >= THRESHOLD )); then
      if can_send "$mp"; then
        ALERTS+=("• $mp ($fstype) – $p% terpakai (Size:$size, Used:$used, Avail:$avail)")
      fi
      mark_sent "$mp"
    else
      clear_sent "$mp"
    fi
  fi
done

if (( ${#ALERTS[@]} > 0 )); then
  MSG="⚠️ Disk Usage Alert
Host   : ${HOSTNAME}
Waktu  : ${NOW_HUMAN}
Ambang : ${THRESHOLD}%

Detail:
$(printf '%s\n' "${ALERTS[@]}")

Saran cepat:
- Bersihkan log/artefak sementara.
- Cek direktori besar: du -xhd1 / | sort -hr | head -n5
- Prune Docker: docker system prune -af (hati-hati)
"
  send_telegram "$MSG"
fi
BASH
  chmod 755 "$SCRIPT"
  echo "[OK] Monitor script -> $SCRIPT"
}

write_systemd() {
  cat > "$SVC" <<EOF
[Unit]
Description=Disk usage monitor -> Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-$CONF
ExecStart=$SCRIPT
EOF

  cat > "$TMR" <<EOF
[Unit]
Description=Run disk monitor every ${INTERVAL_MIN} minute(s)

[Timer]
OnBootSec=2min
OnUnitActiveSec=${INTERVAL_MIN}min
Unit=$(basename "$SVC")

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$(basename "$TMR")"
  echo "[OK] systemd timer enabled -> $(basename "$TMR")"
}

remove_systemd() {
  if have_cmd systemctl; then
    systemctl disable --now "$(basename "$TMR")" 2>/dev/null || true
    rm -f "$TMR" "$SVC"
    systemctl daemon-reload || true
  fi
}

write_cron() {
  # */INTERVAL * * * * root /usr/local/bin/disk-monitor.sh
  local spec="*/${INTERVAL_MIN} * * * *"
  echo "$spec root $SCRIPT >/dev/null 2>&1" > "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  echo "[OK] cron installed -> $CRON_FILE"
}

remove_cron() {
  rm -f "$CRON_FILE" 2>/dev/null || true
}

uninstall_all() {
  echo "[*] Uninstalling..."
  remove_systemd
  remove_cron
  rm -f "$SCRIPT" "$CONF"
  rm -rf "$STATE_DIR"
  echo "[OK] Uninstalled."
}

# ===== Arg parsing =====
NONINTERACTIVE=0
UNINSTALL=0
while getopts ":b:c:t:i:k:m:M:nu h" opt; do
  case "$opt" in
    b) TELEGRAM_BOT_TOKEN="$OPTARG" ;;
    c) TELEGRAM_CHAT_ID="$OPTARG" ;;
    t) THRESHOLD="$OPTARG" ;;
    i) INTERVAL_MIN="$OPTARG" ;;
    k) COOLDOWN_MIN="$OPTARG" ;;
    m) IGNORE_MOUNTS="$(echo "$OPTARG" | tr ',' ' ')" ;;
    M) MODE="$OPTARG" ;;
    n) NONINTERACTIVE=1 ;;
    u) UNINSTALL=1 ;;
    h) usage; exit 0 ;;
    \?) echo "Opsi tidak dikenal: -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Opsi -$OPTARG membutuhkan argumen." >&2; usage; exit 2 ;;
  esac
done

need_root

if (( UNINSTALL == 1 )); then
  uninstall_all
  exit 0
fi

ensure_deps

# Prompt jika interactive dan belum diisi
if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
  if (( NONINTERACTIVE == 1 )); then
    echo "Error: butuh -b <token> dan -c <chat_id> dalam mode non-interaktif." >&2
    exit 2
  fi
  read -r -p "Masukkan Telegram Bot Token: " TELEGRAM_BOT_TOKEN
  read -r -p "Masukkan Telegram Chat ID: " TELEGRAM_CHAT_ID
fi

# Validasi ringan
if ! [[ "$THRESHOLD" =~ ^[0-9]{1,3}$ ]] || (( THRESHOLD < 1 || THRESHOLD > 100 )); then
  echo "Threshold tidak valid: $THRESHOLD" >&2; exit 2
fi
if ! [[ "$INTERVAL_MIN" =~ ^[0-9]+$ ]] || (( INTERVAL_MIN < 1 )); then
  echo "Interval menit tidak valid: $INTERVAL_MIN" >&2; exit 2
fi
if ! [[ "$COOLDOWN_MIN" =~ ^[0-9]+$ ]] || (( COOLDOWN_MIN < 1 )); then
  echo "Cooldown menit tidak valid: $COOLDOWN_MIN" >&2; exit 2
fi
MODE=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')
if [[ "$MODE" != "systemd" && "$MODE" != "cron" ]]; then
  echo "Mode harus 'systemd' atau 'cron'." >&2; exit 2
fi

# Tulis komponen
write_config
write_script
install -d -m 0755 "$STATE_DIR"

# Jadwalkan
if [[ "$MODE" == "systemd" ]]; then
  if have_cmd systemctl && pgrep -x systemd >/dev/null 2>&1; then
    remove_cron
    write_systemd
  else
    echo "[WARN] systemd tidak tersedia/aktif. Fallback ke cron."
    remove_systemd
    write_cron
  fi
else
  remove_systemd
  write_cron
fi

# Uji jalan sekali
echo "[*] Menjalankan uji jalan satu kali..."
if "$SCRIPT"; then
  echo "[OK] Uji jalan selesai. Jika disk >= ${THRESHOLD}% di salah satu mount, notifikasi akan dikirim."
else
  echo "[WARN] Script exit non-zero saat uji. Cek konfigurasi/token jaringan." >&2
fi

echo
echo "Selesai. Rangkuman:"
echo "  Config    : $CONF"
echo "  Script    : $SCRIPT"
echo "  Mode      : $MODE"
if [[ "$MODE" == "systemd" ]]; then
  echo "  Service   : $(basename "$SVC")"
  echo "  Timer     : $(basename "$TMR") (interval: ${INTERVAL_MIN}m)"
  echo "  Status    : systemctl status $(basename "$TMR")"
else
  echo "  Cron      : $CRON_FILE (interval: */${INTERVAL_MIN} * * * *)"
fi
echo
echo "Uninstall: sudo bash $0 -u"

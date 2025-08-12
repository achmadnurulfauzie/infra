#!/usr/bin/env bash
set -euo pipefail

# Default
USER_NAME=""
PLAINTEXT_PASS=""
SERVE_DIR=""
PORT="8888"
CT_NAME="nginx-basic"
RUN_AS_ROOT="true"
CONF_BASE="/opt/nginx-basic-auth"

usage() {
  cat <<USAGE
Usage:
  $0 -u <username> -p <password> -d <serve_dir> [-P <port>] [-n <container_name>] [-R|--as-root]

Options:
  -u            Username Basic Auth (wajib)
  -p            Password plaintext (wajib)
  -d            Direktori yang akan diserve (wajib), contoh: /root/share
  -P            Port host, default: 8888
  -n            Nama container, default: nginx-basic
  -R|--as-root  Jalankan container sebagai root:root (perlu jika SERVE_DIR tidak bisa dibaca user non-root)
  -h            Tampilkan bantuan

Contoh:
  $0 -u admin -p 'S3cretKu' -d /root/share -P 8888 -n nginx-basic
  $0 -u admin -p 'S3cretKu' -d /root -P 8888 -R
USAGE
}

# Parse long option --as-root
for arg in "$@"; do
  [[ "$arg" == "--as-root" ]] && RUN_AS_ROOT="true"
done

# Parse short options
while getopts ":u:p:d:P:n:Rh" opt; do
  case "${opt}" in
    u) USER_NAME="${OPTARG}" ;;
    p) PLAINTEXT_PASS="${OPTARG}" ;;
    d) SERVE_DIR="${OPTARG}" ;;
    P) PORT="${OPTARG}" ;;
    n) CT_NAME="${OPTARG}" ;;
    R) RUN_AS_ROOT="true" ;;
    h) usage; exit 0 ;;
    \?) echo "Opsi tidak dikenal: -${OPTARG}" >&2; usage; exit 1 ;;
    :)  echo "Opsi -${OPTARG} butuh nilai." >&2; usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

# Validasi
[[ -z "${USER_NAME}" ]] && echo "Error: -u <username> wajib." >&2 && usage && exit 1
[[ -z "${PLAINTEXT_PASS}" ]] && echo "Error: -p <password> wajib." >&2 && usage && exit 1
[[ -z "${SERVE_DIR}" ]] && echo "Error: -d <serve_dir> wajib." >&2 && usage && exit 1

# Pastikan direktori serve ada
if [[ ! -d "${SERVE_DIR}" ]]; then
  echo "Direktori ${SERVE_DIR} belum ada. Membuat..."
  mkdir -p "${SERVE_DIR}"
fi

# Jika bukan run-as-root, pastikan world-readable agar Nginx (non-root) bisa baca
if [[ "${RUN_AS_ROOT}" != "true" ]]; then
  if ! sudo -u nobody test -r "${SERVE_DIR}" 2>/dev/null; then
    echo "Peringatan: ${SERVE_DIR} kemungkinan tidak terbaca oleh user non-root di container."
    echo "  Opsi: set permission wajar (mis. chmod 755) ATAU jalankan dengan -R/--as-root."
  fi
fi

# Cek docker
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker tidak ditemukan. Instal Docker terlebih dahulu." >&2
  exit 1
fi

# Siapkan folder konfigurasi
CONF_DIR="${CONF_BASE}/${CT_NAME}"
mkdir -p "${CONF_DIR}"

echo "Menarik image yang diperlukan (nginx:alpine, httpd:2.4-alpine)..."
docker pull nginx:alpine >/dev/null
docker pull httpd:2.4-alpine >/dev/null

# Generate htpasswd (bcrypt)
echo "Menghasilkan .htpasswd..."
docker run --rm httpd:2.4-alpine htpasswd -nbB "${USER_NAME}" "${PLAINTEXT_PASS}" > "${CONF_DIR}/.htpasswd"
chmod 644 "${CONF_DIR}/.htpasswd"

# Tulis konfigurasi Nginx
cat > "${CONF_DIR}/default.conf" <<'EOF'
server {
    listen 80;
    server_name _;

    root /srv;
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;
    charset utf-8;

    # Basic Auth
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        try_files $uri $uri/ =404;
    }

    # Blokir file/dir tersembunyi
    location ~ /\.(?!well-known) {
        deny all;
    }

    # Header dasar
    add_header X-Content-Type-Options nosniff;
}
EOF

# Hentikan/hapus container lama jika ada
if docker ps -a --format '{{.Names}}' | grep -qx "${CT_NAME}"; then
  echo "Container ${CT_NAME} sudah ada. Menggantikan..."
  docker rm -f "${CT_NAME}" >/dev/null || true
fi

# Tentukan opsi user
USER_OPT=()
if [[ "${RUN_AS_ROOT}" == "true" ]]; then
  USER_OPT=(--user root:root)
fi

echo "Menjalankan container ${CT_NAME} (port host ${PORT} -> container 80)..."
docker run -d --name "${CT_NAME}" \
  "${USER_OPT[@]}" \
  -p "${PORT}:80" \
  -v "${SERVE_DIR}:/srv:ro" \
  -v "${CONF_DIR}/default.conf:/etc/nginx/conf.d/default.conf:ro" \
  -v "${CONF_DIR}/.htpasswd:/etc/nginx/.htpasswd:ro" \
  --restart unless-stopped \
  nginx:alpine >/dev/null

echo
echo "Sukses."
echo "Akses   : http://<IP-Server>:${PORT}/"
echo "User    : ${USER_NAME}"
echo "Folder  : ${SERVE_DIR} (read-only di container)"
echo "Container: ${CT_NAME}"
echo
echo "Uji cepat:"
echo "  curl -i http://127.0.0.1:${PORT}/ | head -n1"
echo "  curl -i -u '${USER_NAME}:${PLAINTEXT_PASS}' http://127.0.0.1:${PORT}/ | head -n1"
echo
echo "Catatan: Tanpa HTTPS, kredensial Basic Auth ditransmisikan plaintext. Pertimbangkan pembatasan IP via firewall."

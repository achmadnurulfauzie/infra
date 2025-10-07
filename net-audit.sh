#!/bin/bash
#
# net-audit.sh - Audit sederhana untuk IP interface & port listening
# Tujuan: Menampilkan IP setiap interface + port TCP/UDP yang listen + proses
# Versi: v1.1 (menambahkan cek port 80 & 443)
#

LOGFILE="/var/log/net-audit.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "============================================================" | tee -a "$LOGFILE"
echo "📡 Network Audit - $TIMESTAMP" | tee -a "$LOGFILE"
echo "============================================================" | tee -a "$LOGFILE"

echo -e "\n== 🌐 Interface & IP Address ==" | tee -a "$LOGFILE"
ip -br addr show | tee -a "$LOGFILE"

echo -e "\n== 🛠 Routing Table ==" | tee -a "$LOGFILE"
ip route show | tee -a "$LOGFILE"

echo -e "\n== 🔭 Listening Ports (TCP/UDP) ==" | tee -a "$LOGFILE"
sudo ss -tulnp | tee -a "$LOGFILE"

echo -e "\n== ⚙️  Top 10 Services by Connection Count ==" | tee -a "$LOGFILE"
sudo ss -tan | awk '{print $4}' | cut -d':' -f2 | sort | uniq -c | sort -nr | head | tee -a "$LOGFILE"

# ======================================================================
# 🔍 CEK KHUSUS PORT 80 & 443
# ======================================================================
echo -e "\n== 🌐 Cek Port 80 & 443 ==" | tee -a "$LOGFILE"

for PORT in 80 443; do
    echo -e "\n-- Port $PORT --" | tee -a "$LOGFILE"
    if sudo ss -tulnp | grep -q ":$PORT "; then
        sudo ss -tulnp | grep ":$PORT " | tee -a "$LOGFILE"
        PROC_INFO=$(sudo lsof -iTCP:$PORT -sTCP:LISTEN -Pn 2>/dev/null | awk 'NR>1 {print $1, $2, $9}' | uniq)
        if [ -n "$PROC_INFO" ]; then
            echo "🔎 Proses yang menggunakan port $PORT:" | tee -a "$LOGFILE"
            echo "$PROC_INFO" | tee -a "$LOGFILE"
        else
            echo "⚠️  Tidak dapat mendeteksi proses menggunakan lsof." | tee -a "$LOGFILE"
        fi
    else
        echo "❌ Port $PORT tidak digunakan (free)." | tee -a "$LOGFILE"
    fi
done

echo -e "\n== ✅ Audit Selesai ==" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

#!/usr/bin/env bash
# ============================================================================
#  manage_swap.sh — Interactive Swap Manager for Linux
# ============================================================================
#  Supported distros : Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux
#  Requires          : root or sudo privileges
#  Version           : 2.0
#  Author            : DevOps Engineering
#  Last Updated      : 2026-08-26
# ============================================================================
set -euo pipefail

# ── Colours & Symbols ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Colour

OK="${GREEN}✔${NC}"
WARN="${YELLOW}⚠${NC}"
ERR="${RED}✖${NC}"
INFO="${CYAN}ℹ${NC}"

SWAPFILE_BASE="/swapfile"
SWAPFILE_MAX=5    # Maksimum swapfile tambahan: /swapfile1 .. /swapfile5

# ── Helper Functions ────────────────────────────────────────────────────────

banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🔧  Interactive Swap Manager for Linux${NC}                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}      Supports: Ubuntu · Debian · CentOS · RHEL            ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e " ${ERR} Script ini harus dijalankan sebagai ${BOLD}root${NC} atau dengan ${BOLD}sudo${NC}."
        echo -e "    Contoh: ${YELLOW}sudo bash $0${NC}"
        exit 1
    fi
}

# ── Detect Distro ───────────────────────────────────────────────────────────

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_NAME="${PRETTY_NAME:-$ID}"
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO_ID="rhel"
        DISTRO_NAME=$(cat /etc/redhat-release)
    elif [[ -f /etc/debian_version ]]; then
        DISTRO_ID="debian"
        DISTRO_NAME="Debian $(cat /etc/debian_version)"
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown Linux"
    fi

    # Normalise family
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)
            DISTRO_FAMILY="debian"
            ;;
        centos|rhel|rocky|almalinux|fedora|ol|amzn)
            DISTRO_FAMILY="rhel"
            ;;
        *)
            DISTRO_FAMILY="other"
            ;;
    esac
}

# ── Bytes-to-Human ──────────────────────────────────────────────────────────

bytes_to_human() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
    elif (( bytes >= 1048576 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
    elif (( bytes >= 1024 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}") KB"
    else
        echo "${bytes} B"
    fi
}

# ── Pre-Check : System Info ────────────────────────────────────────────────

precheck() {
    separator
    echo -e " ${INFO} ${BOLD}PRE-CHECK — Informasi Sistem${NC}"
    separator

    # Distro
    echo -e "   ${BOLD}Distro${NC}          : ${GREEN}${DISTRO_NAME}${NC} (family: ${DISTRO_FAMILY})"

    # Kernel
    echo -e "   ${BOLD}Kernel${NC}          : $(uname -r)"

    # RAM
    local total_ram_kb
    total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_bytes=$(( total_ram_kb * 1024 ))
    TOTAL_RAM_MB=$(( total_ram_kb / 1024 ))
    echo -e "   ${BOLD}Total RAM${NC}       : ${GREEN}$(bytes_to_human $total_ram_bytes)${NC} (${TOTAL_RAM_MB} MB)"

    # Free RAM
    local free_ram_kb
    free_ram_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local free_ram_bytes=$(( free_ram_kb * 1024 ))
    echo -e "   ${BOLD}Available RAM${NC}   : $(bytes_to_human $free_ram_bytes)"

    # Disk space on /
    local disk_avail
    disk_avail=$(df -BM / | awk 'NR==2 {print $4}' | tr -d 'M')
    echo -e "   ${BOLD}Disk Free (/)${NC}   : ${disk_avail} MB"

    echo ""

    # ── Swap Status ─────────────────────────────────────────────────────────
    separator
    echo -e " ${INFO} ${BOLD}SWAP STATUS${NC}"
    separator

    local swap_total_kb
    swap_total_kb=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
    local swap_free_kb
    swap_free_kb=$(grep SwapFree /proc/meminfo | awk '{print $2}')
    local swap_used_kb=$(( swap_total_kb - swap_free_kb ))

    CURRENT_SWAP_MB=$(( swap_total_kb / 1024 ))

    if (( swap_total_kb > 0 )); then
        HAS_SWAP=true
        echo -e "   ${OK} Swap ${GREEN}aktif${NC}"
        echo -e "   ${BOLD}Total Swap${NC}      : ${GREEN}$(bytes_to_human $(( swap_total_kb * 1024 )))${NC} (${CURRENT_SWAP_MB} MB)"
        echo -e "   ${BOLD}Used Swap${NC}       : $(bytes_to_human $(( swap_used_kb * 1024 )))"
        echo -e "   ${BOLD}Free Swap${NC}       : $(bytes_to_human $(( swap_free_kb * 1024 )))"
    else
        HAS_SWAP=false
        echo -e "   ${WARN} Swap ${YELLOW}tidak aktif${NC} — belum ada swap yang di-enable."
    fi

    echo ""

    # ── Cek semua swapfile (/swapfile, /swapfile1 .. /swapfile5) ─────────────
    separator
    echo -e " ${INFO} ${BOLD}CEK SWAPFILES${NC}"
    separator

    SWAPFILE_COUNT=0          # jumlah swapfile yang ditemukan
    SWAPFILE_TOTAL_MB=0       # total ukuran semua swapfile

    # Bangun daftar path: /swapfile, /swapfile1, ..., /swapfile5
    local _swap_paths=("${SWAPFILE_BASE}")
    for i in $(seq 1 $SWAPFILE_MAX); do
        _swap_paths+=("${SWAPFILE_BASE}${i}")
    done

    for _sf in "${_swap_paths[@]}"; do
        if [[ -f "$_sf" ]]; then
            (( SWAPFILE_COUNT++ )) || true
            local _sf_size
            _sf_size=$(stat -c%s "$_sf" 2>/dev/null || stat -f%z "$_sf" 2>/dev/null)
            local _sf_mb=$(( _sf_size / 1048576 ))
            SWAPFILE_TOTAL_MB=$(( SWAPFILE_TOTAL_MB + _sf_mb ))

            echo -e "   ${OK} ${BOLD}${_sf}${NC} ${GREEN}ditemukan${NC}  —  $(bytes_to_human $_sf_size) (${_sf_mb} MB)"

            # cek apakah aktif sebagai swap
            if swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$_sf"; then
                echo -e "      └─ ${GREEN}aktif sebagai swap${NC}"
            else
                echo -e "      └─ ${YELLOW}tidak aktif sebagai swap${NC}"
            fi
        fi
    done

    if (( SWAPFILE_COUNT == 0 )); then
        echo -e "   ${WARN} ${YELLOW}Tidak ada swapfile ditemukan${NC} (/swapfile .. /swapfile${SWAPFILE_MAX})"
    else
        echo ""
        echo -e "   ${INFO} Total swapfile ditemukan : ${BOLD}${SWAPFILE_COUNT}${NC}  (total ${SWAPFILE_TOTAL_MB} MB)"
    fi

    echo ""

    # ── Swap entries lain ───────────────────────────────────────────────────
    local other_swaps
    other_swaps=$(swapon --show=NAME,SIZE,TYPE --noheadings 2>/dev/null || true)
    if [[ -n "$other_swaps" ]]; then
        separator
        echo -e " ${INFO} ${BOLD}SEMUA SWAP YANG AKTIF${NC}"
        separator
        echo -e "   ${BOLD}NAME                   SIZE     TYPE${NC}"
        while IFS= read -r line; do
            echo -e "   $line"
        done <<< "$other_swaps"
        echo ""
    fi

    # ── vm.swappiness ───────────────────────────────────────────────────────
    separator
    echo -e " ${INFO} ${BOLD}VM.SWAPPINESS${NC}"
    separator
    CURRENT_SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "unknown")
    echo -e "   ${BOLD}Nilai saat ini${NC}  : ${GREEN}${CURRENT_SWAPPINESS}${NC}"
    echo -e "   ${INFO} Nilai default = 60, production disarankan = 10"
    echo ""
}

# ── Create / Add Swap ──────────────────────────────────────────────────────

# Cari slot swapfile yang tersedia berikutnya
# Urutan: /swapfile → /swapfile1 → /swapfile2 → ... → /swapfile5
find_next_swapfile() {
    if [[ ! -f "${SWAPFILE_BASE}" ]]; then
        echo "${SWAPFILE_BASE}"
        return 0
    fi
    for i in $(seq 1 $SWAPFILE_MAX); do
        if [[ ! -f "${SWAPFILE_BASE}${i}" ]]; then
            echo "${SWAPFILE_BASE}${i}"
            return 0
        fi
    done
    # Semua slot terpakai
    return 1
}

create_or_add_swap() {
    separator
    echo -e " ${INFO} ${BOLD}KONFIGURASI SWAP${NC}"
    separator

    # Summary sebelum input
    echo -e "   RAM saat ini     : ${BOLD}${TOTAL_RAM_MB} MB${NC}"
    echo -e "   Swap saat ini    : ${BOLD}${CURRENT_SWAP_MB} MB${NC}"
    if (( SWAPFILE_COUNT > 0 )); then
        echo -e "   Swapfile aktif   : ${BOLD}${SWAPFILE_COUNT}${NC} file (total ${SWAPFILE_TOTAL_MB} MB)"
    fi
    echo ""

    # ── Cek apakah masih ada slot tersedia ──────────────────────────────────
    local target_swapfile
    if ! target_swapfile=$(find_next_swapfile); then
        echo -e "   ${ERR} ${RED}Semua slot swapfile sudah terpakai!${NC}"
        echo -e "      Slot yang ada: /swapfile, /swapfile1 .. /swapfile${SWAPFILE_MAX}"
        echo -e "      Hapus salah satu swapfile secara manual jika ingin menambah."
        return 1
    fi

    echo -e "   ${INFO} Swapfile baru akan dibuat di: ${BOLD}${target_swapfile}${NC}"
    echo ""

    # Rekomendasi
    local recommended
    if (( TOTAL_RAM_MB <= 2048 )); then
        recommended=$(( TOTAL_RAM_MB * 2 ))
    elif (( TOTAL_RAM_MB <= 8192 )); then
        recommended=$TOTAL_RAM_MB
    else
        recommended=$(( TOTAL_RAM_MB / 2 ))
    fi
    # Kurangi dengan swap yang sudah ada
    local recommended_additional=$(( recommended - CURRENT_SWAP_MB ))
    (( recommended_additional < 0 )) && recommended_additional=0

    echo -e "   ${INFO} Rekomendasi total swap berdasarkan RAM : ${GREEN}${recommended} MB ($(( recommended / 1024 )) GB)${NC}"
    if (( CURRENT_SWAP_MB > 0 )); then
        echo -e "   ${INFO} Swap sudah ada                        : ${YELLOW}${CURRENT_SWAP_MB} MB${NC}"
        if (( recommended_additional > 0 )); then
            echo -e "   ${INFO} Tambahan yang disarankan               : ${GREEN}${recommended_additional} MB ($(( recommended_additional / 1024 )) GB)${NC}"
        else
            echo -e "   ${INFO} Swap sudah memenuhi/melebihi rekomendasi."
        fi
    fi
    echo ""

    # ── Input ukuran swap ───────────────────────────────────────────────────
    local swap_size_input
    while true; do
        echo -ne "   Masukkan ukuran swap ${BOLD}tambahan${NC} (contoh: ${YELLOW}4G${NC}, ${YELLOW}8G${NC}, ${YELLOW}2048M${NC}): "
        read -r swap_size_input

        if [[ -z "$swap_size_input" ]]; then
            echo -e "   ${ERR} Input tidak boleh kosong."
            continue
        fi

        # Parse input
        local unit="${swap_size_input: -1}"
        local number="${swap_size_input%?}"

        case "$unit" in
            G|g)
                if [[ "$number" =~ ^[0-9]+$ ]] && (( number > 0 )); then
                    NEW_SWAP_MB=$(( number * 1024 ))
                    NEW_SWAP_DISPLAY="${number}G"
                    break
                fi
                ;;
            M|m)
                if [[ "$number" =~ ^[0-9]+$ ]] && (( number >= 256 )); then
                    NEW_SWAP_MB=$number
                    NEW_SWAP_DISPLAY="${number}M"
                    break
                else
                    echo -e "   ${ERR} Minimum ukuran swap: 256M"
                    continue
                fi
                ;;
            *)
                # Coba interpret sebagai GB jika murni angka
                if [[ "$swap_size_input" =~ ^[0-9]+$ ]] && (( swap_size_input > 0 )); then
                    NEW_SWAP_MB=$(( swap_size_input * 1024 ))
                    NEW_SWAP_DISPLAY="${swap_size_input}G"
                    break
                fi
                ;;
        esac

        echo -e "   ${ERR} Format tidak valid. Gunakan format: ${YELLOW}4G${NC}, ${YELLOW}8G${NC}, ${YELLOW}2048M${NC}, atau angka (GB)."
    done

    echo ""

    # ── Cek disk space ──────────────────────────────────────────────────────
    local disk_avail_mb
    disk_avail_mb=$(df -BM / | awk 'NR==2 {print $4}' | tr -d 'M')

    if (( disk_avail_mb < (NEW_SWAP_MB + 512) )); then
        echo -e "   ${ERR} ${RED}Disk space tidak cukup!${NC}"
        echo -e "      Dibutuhkan : ~${NEW_SWAP_MB} MB"
        echo -e "      Tersedia   : ${disk_avail_mb} MB"
        echo -e "      Sisakan minimal 512 MB untuk sistem."
        exit 1
    fi

    # ── Konfirmasi ──────────────────────────────────────────────────────────
    echo -e "   ${BOLD}Ringkasan perubahan:${NC}"
    echo -e "     Aksi         : ${GREEN}Buat baru${NC} ${target_swapfile}"
    echo -e "     Ukuran       : ${NEW_SWAP_MB} MB (${NEW_SWAP_DISPLAY})"
    if (( CURRENT_SWAP_MB > 0 )); then
        echo -e "     Swap lama    : ${CURRENT_SWAP_MB} MB (${BOLD}tetap aktif${NC})"
        echo -e "     Total swap   : $(( CURRENT_SWAP_MB + NEW_SWAP_MB )) MB"
    fi
    echo ""

    echo -ne "   Lanjutkan? [${GREEN}y${NC}/${RED}N${NC}]: "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "   ${WARN} Dibatalkan oleh user."
        return 1
    fi

    echo ""

    # ── Buat swapfile baru (tanpa menghapus yang lama) ──────────────────────
    echo -e "   ${INFO} Membuat ${target_swapfile} (${NEW_SWAP_DISPLAY})..."
    echo -e "       Ini mungkin membutuhkan waktu beberapa saat..."

    # Coba fallocate dulu, fallback ke dd
    if command -v fallocate &>/dev/null; then
        if fallocate -l "${NEW_SWAP_MB}M" "${target_swapfile}" 2>/dev/null; then
            echo -e "   ${OK} ${target_swapfile} dibuat dengan fallocate."
        else
            echo -e "   ${WARN} fallocate gagal, menggunakan dd sebagai fallback..."
            dd if=/dev/zero of="${target_swapfile}" bs=1M count="$NEW_SWAP_MB" status=progress
            echo -e "   ${OK} ${target_swapfile} dibuat dengan dd."
        fi
    else
        dd if=/dev/zero of="${target_swapfile}" bs=1M count="$NEW_SWAP_MB" status=progress
        echo -e "   ${OK} ${target_swapfile} dibuat dengan dd."
    fi

    # ── Set permissions ─────────────────────────────────────────────────────
    echo -e "   ${INFO} Set permissions 600..."
    chmod 600 "${target_swapfile}"
    echo -e "   ${OK} Permissions di-set."

    # ── Format as swap ──────────────────────────────────────────────────────
    echo -e "   ${INFO} Memformat sebagai swap..."
    mkswap "${target_swapfile}"
    echo -e "   ${OK} Format selesai."

    # ── Enable swap ─────────────────────────────────────────────────────────
    echo -e "   ${INFO} Mengaktifkan swap..."
    swapon "${target_swapfile}"
    echo -e "   ${OK} Swap aktif!"

    # ── Persist di /etc/fstab ───────────────────────────────────────────────
    echo -e "   ${INFO} Mengecek /etc/fstab..."
    if grep -q "${target_swapfile}" /etc/fstab 2>/dev/null; then
        echo -e "   ${OK} Entry ${target_swapfile} sudah ada di /etc/fstab."
    else
        echo -e "   ${INFO} Menambahkan entry ke /etc/fstab..."
        echo "${target_swapfile} none swap sw 0 0" >> /etc/fstab
        echo -e "   ${OK} Entry ditambahkan ke /etc/fstab (persistent setelah reboot)."
    fi

    echo ""
    echo -e "   ${OK} ${GREEN}${BOLD}Swap berhasil dikonfigurasi!${NC}"
}

# ── Configure vm.swappiness ─────────────────────────────────────────────────

configure_swappiness() {
    separator
    echo -e " ${INFO} ${BOLD}KONFIGURASI VM.SWAPPINESS${NC}"
    separator

    echo -e "   Nilai saat ini   : ${BOLD}${CURRENT_SWAPPINESS}${NC}"
    echo ""
    echo -e "   ${INFO} Panduan nilai vm.swappiness:"
    echo -e "     ${BOLD} 0${NC}   — Swap hanya digunakan saat keadaan sangat darurat (OOM)"
    echo -e "     ${BOLD}10${NC}   — ${GREEN}Disarankan untuk production server${NC}"
    echo -e "     ${BOLD}30${NC}   — Cocok untuk workstation / development"
    echo -e "     ${BOLD}60${NC}   — Default Linux (terlalu agresif untuk server)"
    echo -e "     ${BOLD}100${NC}  — Agresif menggunakan swap"
    echo ""

    local new_swappiness
    while true; do
        echo -ne "   Masukkan nilai vm.swappiness [0-100] (tekan Enter untuk skip): "
        read -r new_swappiness

        # Skip jika kosong
        if [[ -z "$new_swappiness" ]]; then
            echo -e "   ${INFO} Tidak ada perubahan pada vm.swappiness."
            return 0
        fi

        # Validasi
        if [[ "$new_swappiness" =~ ^[0-9]+$ ]] && (( new_swappiness >= 0 && new_swappiness <= 100 )); then
            break
        fi

        echo -e "   ${ERR} Nilai harus angka antara 0-100."
    done

    if (( new_swappiness == CURRENT_SWAPPINESS )); then
        echo -e "   ${OK} vm.swappiness sudah bernilai ${new_swappiness}. Tidak ada perubahan."
        return 0
    fi

    echo ""
    echo -ne "   Set vm.swappiness=${new_swappiness}? [${GREEN}y${NC}/${RED}N${NC}]: "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "   ${WARN} Dibatalkan."
        return 0
    fi

    # ── Set secara runtime ──────────────────────────────────────────────────
    echo -e "   ${INFO} Menerapkan vm.swappiness=${new_swappiness} (runtime)..."
    sysctl vm.swappiness="$new_swappiness" >/dev/null
    echo -e "   ${OK} Diterapkan."

    # ── Persist ─────────────────────────────────────────────────────────────
    local sysctl_file="/etc/sysctl.d/99-swappiness.conf"
    echo -e "   ${INFO} Menyimpan ke ${sysctl_file} (persistent)..."

    # Hapus entry lama jika ada
    if [[ -f "$sysctl_file" ]]; then
        sed -i '/^vm\.swappiness/d' "$sysctl_file"
    fi

    echo "vm.swappiness=${new_swappiness}" >> "$sysctl_file"

    # Juga cek di /etc/sysctl.conf
    if grep -q '^vm\.swappiness' /etc/sysctl.conf 2>/dev/null; then
        sed -i "s/^vm\.swappiness=.*/vm.swappiness=${new_swappiness}/" /etc/sysctl.conf
        echo -e "   ${OK} /etc/sysctl.conf juga di-update."
    fi

    echo -e "   ${OK} ${GREEN}vm.swappiness=${new_swappiness} berhasil disimpan!${NC}"
    echo ""
}

# ── Final Verification ─────────────────────────────────────────────────────

final_verification() {
    separator
    echo -e " ${INFO} ${BOLD}VERIFIKASI AKHIR${NC}"
    separator
    echo ""

    echo -e "   ${BOLD}swapon --show:${NC}"
    swapon --show 2>/dev/null | while IFS= read -r line; do
        echo "     $line"
    done
    echo ""

    echo -e "   ${BOLD}free -h:${NC}"
    free -h 2>/dev/null | while IFS= read -r line; do
        echo "     $line"
    done
    echo ""

    echo -e "   ${BOLD}vm.swappiness:${NC} $(cat /proc/sys/vm/swappiness)"
    echo ""

    # Cek fstab
    echo -e "   ${BOLD}/etc/fstab swap entry:${NC}"
    grep -i swap /etc/fstab 2>/dev/null | while IFS= read -r line; do
        echo "     $line"
    done
    echo ""
}

# ════════════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════════════

main() {
    banner
    check_root
    detect_distro
    precheck

    # ── Menu interaktif ─────────────────────────────────────────────────────
    separator
    echo -e " ${INFO} ${BOLD}APA YANG INGIN DILAKUKAN?${NC}"
    separator
    echo -e "   ${BOLD}1)${NC} Buat / Tambah swap (${SWAPFILE_BASE}[1..${SWAPFILE_MAX}])"
    echo -e "   ${BOLD}2)${NC} Konfigurasi vm.swappiness saja"
    echo -e "   ${BOLD}3)${NC} Buat / Tambah swap + Konfigurasi vm.swappiness"
    echo -e "   ${BOLD}4)${NC} Keluar"
    echo ""

    local choice
    echo -ne "   Pilihan [1-4]: "
    read -r choice
    echo ""

    case "$choice" in
        1)
            create_or_add_swap
            final_verification
            ;;
        2)
            configure_swappiness
            final_verification
            ;;
        3)
            create_or_add_swap
            # Refresh swappiness value after swap changes
            CURRENT_SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "unknown")
            configure_swappiness
            final_verification
            ;;
        4)
            echo -e "   ${INFO} Keluar. Tidak ada perubahan."
            exit 0
            ;;
        *)
            echo -e "   ${ERR} Pilihan tidak valid."
            exit 1
            ;;
    esac

    separator
    echo -e " ${OK} ${GREEN}${BOLD}Selesai!${NC} Swap telah dikonfigurasi dengan sukses."
    separator
    echo ""
}

main "$@"

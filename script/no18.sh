# geto


#!/bin/bash
set -euo pipefail

# ==========================================
# NOMOR 18 - API FAILOVER
# GETO LOAD BALANCER
# ==========================================

CONF="/etc/nginx/sites-available/no15"

echo "======================================"
echo " NOMOR 18 - API FAILOVER"
echo " Node : $(hostname -s)"
echo "======================================"

# ==========================================
# 1. VALIDASI NODE
# ==========================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root."
    exit 1
fi

if [ "$(hostname -s)" != "geto" ]; then
    echo "ERROR: Script hanya untuk Geto."
    exit 1
fi

if [ ! -f "$CONF" ]; then
    echo "ERROR: Nomor 15 belum dikonfigurasi."
    exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
    echo "ERROR: Nginx belum terinstal."
    exit 1
fi

if ! grep -q '^upstream api_cluster {' "$CONF"; then
    echo "ERROR: Upstream api_cluster tidak ditemukan."
    exit 1
fi

# ==========================================
# 2. BACKUP KONFIGURASI
# ==========================================

echo "[1] Backup konfigurasi..."

cp -a "$CONF" "${CONF}.before-no18"

# ==========================================
# 3. TAMBAHKAN KIRARA BACKUP
# ==========================================

echo "[2] Mengatur upstream failover..."

sed -i '/^upstream api_cluster {/,/^}/c\
upstream api_cluster {\
    server 192.239.4.5:80 weight=3 max_fails=2 fail_timeout=5s;\
    server 192.239.4.6:80 weight=1 max_fails=2 fail_timeout=5s;\
    server 192.239.4.7:80 backup;\
}' "$CONF"

# ==========================================
# 4. RETRY BACKEND JIKA GAGAL
# ==========================================

echo "[3] Mengatur proxy failover..."

if ! grep -q 'proxy_next_upstream error timeout' "$CONF"; then
    sed -i '/^[[:space:]]*server_name _;$/a\
    # Retry ke worker lain jika koneksi gagal\
    proxy_next_upstream error timeout http_502 http_503 http_504;\
    proxy_next_upstream_tries 3;\
    proxy_connect_timeout 2s;\
    proxy_read_timeout 5s;' "$CONF"
fi

# ==========================================
# 5. VALIDASI
# ==========================================

echo "[4] Validasi konfigurasi..."

if ! nginx -t; then
    echo "ERROR: Konfigurasi Nginx tidak valid."
    cp -a "${CONF}.before-no18" "$CONF"
    echo "Konfigurasi lama dipulihkan."
    exit 1
fi

# ==========================================
# 6. RELOAD NGINX
# ==========================================

echo "[5] Mengaktifkan failover..."

if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s reload
else
    nginx
fi

echo ""
echo "======================================"
echo " NOMOR 18 SELESAI"
echo "======================================"
echo "Primary 1 : Nanami (192.239.4.5)"
echo "Primary 2 : Todo   (192.239.4.6)"
echo "Backup    : Kirara (192.239.4.7)"
echo "Max Fails : 2"
echo "Timeout   : 5 detik"
echo "======================================"

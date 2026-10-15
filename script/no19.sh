# gojo

#!/bin/bash
set -euo pipefail

# ==========================================
# NOMOR 19 - PROXY CACHE & RATE LIMITING
# Node: Gojo
# ==========================================

SITE="/etc/nginx/sites-available/no16"
GLOBAL="/etc/nginx/conf.d/no19-global.conf"
CACHE_DIR="/var/cache/nginx/no19"

echo "======================================"
echo " NOMOR 19 - CACHE & RATE LIMITING"
echo " Node: $(hostname -s)"
echo "======================================"

# ==========================================
# 1. VALIDASI
# ==========================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root."
    exit 1
fi

if [ "$(hostname -s)" != "gojo" ]; then
    echo "ERROR: Script hanya untuk Gojo."
    exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
    echo "ERROR: Nginx belum tersedia."
    exit 1
fi

if [ ! -f "$SITE" ]; then
    echo "ERROR: Konfigurasi nomor 16 tidak ditemukan."
    exit 1
fi

# ==========================================
# 2. BACKUP
# ==========================================

echo "[1] Backup konfigurasi..."

BACKUP="${SITE}.before-no19"
cp -a "$SITE" "$BACKUP"

# ==========================================
# 3. KONFIGURASI CACHE & RATE ZONE
# ==========================================

echo "[2] Membuat cache dan rate limit zone..."

mkdir -p "$CACHE_DIR"
chown www-data:www-data "$CACHE_DIR"
chmod 750 "$CACHE_DIR"

# Kedua directive harus berada di http context.
# Debian Nginx memuat conf.d/*.conf di dalam http.

cat > "$GLOBAL" <<'NGINX'
# NOMOR 19 - GLOBAL HTTP CONFIGURATION

proxy_cache_path /var/cache/nginx/no19
    levels=1:2
    keys_zone=no19_frontend:10m
    max_size=100m
    inactive=10m
    use_temp_path=off;

limit_req_zone $binary_remote_addr
    zone=no19_api:10m
    rate=10r/s;
NGINX

# ==========================================
# 4. MODIFIKASI VIRTUAL HOST GOJO
# ==========================================

echo "[3] Mengatur cache frontend dan API limit..."

TEMP="$(mktemp)"

awk '
{
    print

    # Batas API /api
    if ($0 ~ /^[[:space:]]*location = \/api[[:space:]]*\{/) {
        print "        # NO19: API RATE LIMIT"
        print "        limit_req zone=no19_api burst=5 nodelay;"
        print "        limit_req_status 429;"
    }

    # Batas API /api/...
    if ($0 ~ /^[[:space:]]*location \^~ \/api\/[[:space:]]*\{/) {
        print "        # NO19: API RATE LIMIT"
        print "        limit_req zone=no19_api burst=5 nodelay;"
        print "        limit_req_status 429;"
    }

    # Cache frontend
    if ($0 ~ /^[[:space:]]*location \/[[:space:]]*\{/) {
        print "        # NO19: FRONTEND CACHE"
        print "        proxy_cache no19_frontend;"
        print "        proxy_cache_valid 200 10m;"
        print "        proxy_cache_key \"$scheme$host$request_uri\";"
        print "        add_header X-Cache-Status $upstream_cache_status always;"
    }
}
' "$BACKUP" > "$TEMP"

# Gunakan hasil modifikasi hanya jika bagian nomor 19
# belum ada sebelumnya. Jika sudah ada, gunakan file lama.

if grep -Fq '# NO19: FRONTEND CACHE' "$BACKUP"; then
    echo "Cache sudah ada, tidak ditambahkan lagi."
else
    cat "$TEMP" > "$SITE"
fi

rm -f "$TEMP"

# ==========================================
# 5. VALIDASI KONFIGURASI
# ==========================================

echo "[4] Memeriksa Nginx..."

if ! nginx -t; then
    echo "ERROR: Konfigurasi tidak valid."
    cp -a "$BACKUP" "$SITE"
    echo "Konfigurasi situs sebelumnya dipulihkan."
    echo "Periksa file $GLOBAL sebelum mencoba lagi."
    exit 1
fi

# ==========================================
# 6. AKTIFKAN NGINX
# ==========================================

echo "[5] Mengaktifkan nomor 19..."

if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s reload
else
    nginx
fi

echo ""
echo "======================================"
echo " NOMOR 19 SELESAI"
echo "======================================"
echo "Cache frontend : 10 menit"
echo "Header cache   : X-Cache-Status"
echo "Rate limit API : 10 request/detik/IP"
echo "Burst          : 5"
echo "Status limit   : HTTP 429"
echo "======================================"

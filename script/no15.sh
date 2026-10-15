# geto

#!/bin/bash
set -euo pipefail

# ==========================================
# NOMOR 15 - NGINX LOAD BALANCER
# Node: Geto
# ==========================================

GETO_IP="192.239.4.2"
NANAMI_IP="192.239.4.5"
TODO_IP="192.239.4.6"

echo "======================================"
echo " SETUP NOMOR 15 - LOAD BALANCING API"
echo " Node : $(hostname -s)"
echo "======================================"

# Pastikan script dijalankan di Geto
if [ "$(hostname -s)" != "geto" ]; then
    echo "ERROR: Script hanya untuk node Geto!"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root!"
    exit 1
fi

# ==========================================
# 1. INSTALASI NGINX
# ==========================================

echo "[1] Memeriksa Nginx..."

if ! command -v nginx >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y nginx
fi

# ==========================================
# 2. KONFIGURASI LOAD BALANCER
# ==========================================

echo "[2] Membuat konfigurasi upstream..."

mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled

cat > /etc/nginx/sites-available/no15 <<EOF
# NOMOR 15 - GETO LOAD BALANCER

upstream api_cluster {
    # Nanami mendapat 3 bagian request
    server ${NANAMI_IP}:80 weight=3;

    # Todo mendapat 1 bagian request
    server ${TODO_IP}:80 weight=1;
}

server {
    listen 80 default_server;
    server_name _;

    # Endpoint API
    location = /api {
        proxy_pass http://api_cluster;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Endpoint API dengan path lanjutan
    location ^~ /api/ {
        proxy_pass http://api_cluster;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Selain /api tidak dilayani
    location / {
        return 404;
    }
}
EOF

# ==========================================
# 3. AKTIFKAN KONFIGURASI
# ==========================================

echo "[3] Mengaktifkan virtual host..."

# Menghindari bentrok dengan situs default Debian
rm -f /etc/nginx/sites-enabled/default

ln -sfn \
    /etc/nginx/sites-available/no15 \
    /etc/nginx/sites-enabled/no15

# ==========================================
# 4. VALIDASI DAN JALANKAN NGINX
# ==========================================

echo "[4] Memeriksa konfigurasi Nginx..."

nginx -t

if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s reload
else
    nginx
fi

# ==========================================
# 5. SELESAI
# ==========================================

echo ""
echo "======================================"
echo " NOMOR 15 SELESAI"
echo "======================================"
echo "Load Balancer : ${GETO_IP}"
echo "Upstream      : api_cluster"
echo "Nanami        : ${NANAMI_IP} (weight 3)"
echo "Todo          : ${TODO_IP} (weight 1)"
echo "Endpoint      : http://${GETO_IP}/api"
echo "======================================"

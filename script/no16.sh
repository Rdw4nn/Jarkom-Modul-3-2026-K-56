# gojo

#!/bin/bash
set -euo pipefail

# ==========================================
# NOMOR 16 - REVERSE PROXY GOJO
# ==========================================

GOJO_IP="192.239.1.4"
MAKI_IP="192.239.4.3"
PANDA_IP="192.239.4.4"
GETO_IP="192.239.4.2"

DOMAIN="jujutsu.56.com"

echo "======================================"
echo " SETUP NOMOR 16 - REVERSE PROXY"
echo " Node : $(hostname -s)"
echo "======================================"

# ==========================================
# 1. VALIDASI NODE
# ==========================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root"
    exit 1
fi

if [ "$(hostname -s)" != "gojo" ]; then
    echo "ERROR: Script hanya untuk Gojo"
    exit 1
fi

# ==========================================
# 2. CEK NGINX
# ==========================================

echo "[1] Memeriksa Nginx..."

if ! command -v nginx >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y nginx
fi

# ==========================================
# 3. BUAT KONFIGURASI REVERSE PROXY
# ==========================================

echo "[2] Membuat konfigurasi reverse proxy..."

mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled

cat > /etc/nginx/sites-available/no16 <<EOF
# ==========================================
# NOMOR 16 - GOJO
# ==========================================

# Frontend: round robin default
upstream frontend_cluster {
    server ${MAKI_IP}:80;
    server ${PANDA_IP}:80;
}

server {
    listen 80 default_server;

    server_name ${DOMAIN} www.${DOMAIN};

    # API diteruskan ke Geto
    location = /api {
        proxy_pass http://${GETO_IP}:80;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ^~ /api/ {
        proxy_pass http://${GETO_IP}:80;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Web frontend Maki / Panda
    location / {
        proxy_pass http://frontend_cluster;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# ==========================================
# 4. AKTIFKAN VIRTUAL HOST
# ==========================================

echo "[3] Mengaktifkan konfigurasi..."

rm -f /etc/nginx/sites-enabled/default

ln -sfn \
    /etc/nginx/sites-available/no16 \
    /etc/nginx/sites-enabled/no16

# ==========================================
# 5. VALIDASI DAN JALANKAN NGINX
# ==========================================

echo "[4] Validasi Nginx..."

nginx -t

if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s reload
else
    nginx
fi

# ==========================================
# 6. SELESAI
# ==========================================

echo ""
echo "======================================"
echo " NOMOR 16 SELESAI"
echo "======================================"
echo "Gojo     : ${GOJO_IP}"
echo "Domain   : ${DOMAIN}"
echo "WWW      : www.${DOMAIN}"
echo "Frontend : Maki ${MAKI_IP}"
echo "           Panda ${PANDA_IP}"
echo "API      : Geto ${GETO_IP}"
echo "======================================"


#!/bin/bash
set -euo pipefail

# ==========================================
# NOMOR 17 - REAL CLIENT IP
# ==========================================

HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"

GOJO_IP="192.239.1.4"
GETO_IP="192.239.4.2"

GETO_CONF="/etc/nginx/sites-available/no15"
API_FILE="/var/www/no14/api.php"

echo "======================================"
echo " NOMOR 17 - REAL CLIENT IP"
echo " Node : $HOST"
echo "======================================"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root."
    exit 1
fi

case "$HOST" in

# ==========================================
# GOJO - PERIKSA HEADER
# ==========================================
gojo)
    echo "[1] Memeriksa header Gojo..."

    CONF="/etc/nginx/sites-available/no16"

    if [ ! -f "$CONF" ]; then
        echo "ERROR: no16 belum tersedia."
        exit 1
    fi

    if ! grep -Fq \
        'proxy_set_header X-Real-IP $remote_addr;' "$CONF"; then
        echo "ERROR: Header X-Real-IP tidak ditemukan."
        exit 1
    fi

    if ! grep -Fq \
        'proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' "$CONF"; then
        echo "ERROR: Header X-Forwarded-For tidak ditemukan."
        exit 1
    fi

    nginx -t

    echo "Gojo sudah meneruskan header IP asli."
    ;;

# ==========================================
# GETO - TRUST GOJO
# ==========================================
geto)
    echo "[1] Mengatur trusted proxy Geto..."

    if [ ! -f "$GETO_CONF" ]; then
        echo "ERROR: Konfigurasi nomor 15 belum ada."
        exit 1
    fi

    cp -n "$GETO_CONF" "${GETO_CONF}.before-no17"

    # Mempercayai header X-Real-IP hanya dari Gojo
    if ! grep -Fq "set_real_ip_from $GOJO_IP;" "$GETO_CONF"; then

        sed -i "/^[[:space:]]*server_name _;$/a\\
    set_real_ip_from $GOJO_IP;\\
    real_ip_header X-Real-IP;" "$GETO_CONF"

    fi

    if ! grep -Fq "set_real_ip_from $GOJO_IP;" "$GETO_CONF"; then
        echo "ERROR: Gagal menambahkan trusted proxy."
        exit 1
    fi

    if ! grep -Fq 'proxy_set_header X-Real-IP $remote_addr;' "$GETO_CONF"; then
        echo "ERROR: Konfigurasi forwarding IP Geto tidak ditemukan."
        exit 1
    fi

    echo "[2] Validasi Nginx..."

    nginx -t

    if pgrep -x nginx >/dev/null 2>&1; then
        nginx -s reload
    else
        nginx
    fi

    echo "Geto mempercayai Gojo sebagai proxy."
    ;;

# ==========================================
# NANAMI / TODO / KIRARA
# ==========================================
nanami|todo|kirara)
    echo "[1] Memperbarui API worker..."

    if [ ! -f "$API_FILE" ]; then
        echo "ERROR: API nomor 14 belum tersedia."
        exit 1
    fi

    if ! command -v php >/dev/null 2>&1; then
        echo "ERROR: PHP belum tersedia."
        exit 1
    fi

    cp -n "$API_FILE" "${API_FILE}.before-no17"

    # Ubah hanya bagian pembacaan client IP.
    # Kode database dan INSERT tetap dipertahankan.

    php <<'PHP'
<?php
$file = '/var/www/no14/api.php';

$code = file_get_contents($file);

if ($code === false) {
    fwrite(STDERR, "Gagal membaca API.\n");
    exit(1);
}

$old = <<<'OLD'
$clientIp = $_SERVER['REMOTE_ADDR'] ?? null;
OLD;

$new = <<<'NEW'
$peerIp = $_SERVER['REMOTE_ADDR'] ?? '';
$realIp = $_SERVER['HTTP_X_REAL_IP'] ?? '';

// Hanya percayai X-Real-IP dari Geto.
$clientIp = (
    $peerIp === '192.239.4.2'
    && filter_var($realIp, FILTER_VALIDATE_IP)
) ? $realIp : $peerIp;
NEW;

if (strpos($code, $new) !== false) {
    echo "API sudah menggunakan Real Client IP.\n";
    exit(0);
}

if (strpos($code, $old) === false) {
    fwrite(STDERR,
        "ERROR: Baris clientIp asli tidak ditemukan.\n"
    );
    exit(1);
}

$updated = str_replace($old, $new, $code);

if (file_put_contents($file, $updated) === false) {
    fwrite(STDERR, "ERROR: Gagal mengubah API.\n");
    exit(1);
}

echo "Kode Real Client IP berhasil ditambahkan.\n";
PHP

    echo "[2] Memeriksa sintaks PHP..."

    php -l "$API_FILE"

    echo "API $HOST siap mencatat IP asli."
    ;;

*)
    echo "ERROR: Node ini bukan target nomor 17."
    exit 1
    ;;
esac

echo ""
echo "======================================"
echo " NOMOR 17 SELESAI - $HOST"
echo "======================================"

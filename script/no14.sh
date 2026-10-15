# Maki, Panda, Nanami, Todo, dan Kirara

#!/bin/bash
set -euo pipefail

# =========================================
# NO 14 - WEB FRONTEND & API WORKERS
# Debian 13 / GNS3
# =========================================

DOMAIN="jujutsu.56.com"
GOJO_IP="192.239.1.4"
DB_NAME="db_shibuya_56"
DB_USER="api56"
DB_HOST="192.239.4.9"
GETO_IP="192.239.4.2"
DB_PASS="12345678"

SITE="/etc/nginx/sites-available/no14"
ROOT="/var/www/no14"
HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"

if [ "$(id -u)" -ne 0 ]; then
    echo "Jalankan sebagai root"
    exit 1
fi

case "$HOST" in
    maki|panda)
        ROLE="FRONTEND"
        ;;
    nanami|todo|kirara)
        ROLE="API"
        ;;
    *)
        echo "Node $HOST tidak digunakan pada no 14"
        exit 1
        ;;
esac

echo "=================================="
echo " SETUP NOMOR 14"
echo " Node : $HOST"
echo " Role : $ROLE"
echo "=================================="

# =========================================
# 1. INSTALASI
# =========================================

echo "[1] Instalasi package..."

if ! command -v nginx >/dev/null 2>&1 ||
   ! command -v php >/dev/null 2>&1 ||
   ! command -v curl >/dev/null 2>&1; then

    # Resolver internal hasil nomor 11
    if ! getent hosts deb.debian.org \
        >/dev/null 2>&1; then

        if [ -f /etc/resolv.conf ] &&
           [ ! -f /etc/resolv.conf.bak-no14 ]; then
            cp /etc/resolv.conf \
               /etc/resolv.conf.bak-no14
        fi

        printf 'nameserver 192.239.1.2\nnameserver 192.239.1.3\n' \
            > /etc/resolv.conf
    fi
fi

# apt install aman dipanggil lagi bila sudah terpasang
apt-get update

DEBIAN_FRONTEND=noninteractive \
apt-get install -y \
    nginx php-fpm php-cli php-mysql curl

# =========================================
# 2. MENJALANKAN PHP-FPM
# =========================================

echo "[2] Menjalankan PHP-FPM..."

FPM_BIN="$(find /usr/sbin -maxdepth 1 \
    -name 'php*-fpm' -type f | sort -V | tail -1)"

if [ -z "$FPM_BIN" ]; then
    echo "ERROR: php-fpm tidak ditemukan"
    exit 1
fi

FPM_NAME="$(basename "$FPM_BIN")"
FPM_VERSION="${FPM_NAME#php-fpm}"

if ! pgrep -f "^php-fpm: master process" \
    >/dev/null 2>&1; then
    "$FPM_BIN" -D
fi

FPM_SOCKET="/run/php/php${FPM_VERSION}-fpm.sock"

for i in $(seq 1 15); do
    if [ -S "$FPM_SOCKET" ]; then
        break
    fi
    sleep 1
done

if [ ! -S "$FPM_SOCKET" ]; then
    echo "ERROR: Socket PHP-FPM belum tersedia"
    exit 1
fi

echo "PHP-FPM socket: $FPM_SOCKET"

# =========================================
# 3. DIREKTORI WEB
# =========================================

mkdir -p "$ROOT"
chmod 755 "$ROOT"

# =========================================
# 4. FRONTEND MAKI DAN PANDA
# =========================================

if [ "$ROLE" = "FRONTEND" ]; then

echo "[3] Membuat Web Frontend..."

cat > "$ROOT/index.php" <<'PHP'
<?php
$host = gethostname();

header('Content-Type: text/html; charset=UTF-8');
header('X-Worker-Name: ' . $host);

$safeHost = htmlspecialchars(
    $host,
    ENT_QUOTES,
    'UTF-8'
);
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport"
          content="width=device-width, initial-scale=1">
    <title>Jujutsu Shibuya</title>
    <style>
        body {
            margin: 0;
            font-family: Arial, sans-serif;
            background: #101827;
            color: #fff;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .card {
            padding: 42px;
            background: #1e293b;
            border-radius: 20px;
            text-align: center;
            box-shadow: 0 12px 30px #0005;
            max-width: 440px;
        }
        h1 { color: #93c5fd; }
        .worker {
            margin-top: 20px;
            padding: 16px;
            background: #0f172a;
            border-radius: 12px;
            font-size: 24px;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>Jujutsu Shibuya</h1>
        <p>Web Frontend Berhasil Berjalan</p>
        <div class="worker">
            Server: <?= $safeHost ?>
        </div>
        <p>Nginx + PHP-FPM</p>
    </div>
</body>
</html>
PHP

cat > "$SITE" <<EOF
server {
    listen 80;
    server_name $HOST $HOST.$DOMAIN $DOMAIN www.$DOMAIN;

    # Hanya Gojo sebagai reverse proxy
    allow $GOJO_IP;
    deny all;

    root $ROOT;
    index index.php;

    location / {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $ROOT/index.php;
        fastcgi_pass unix:$FPM_SOCKET;
    }

    location ~ /\\. {
        deny all;
    }
}
EOF

# =========================================
# 5. API NANAMI / TODO / KIRARA
# =========================================

else

echo "[3] Konfigurasi koneksi database..."

# Validasi alamat IPv4
valid_ip() {
    local ip="$1"
    local a b c d octet

    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] \
        || return 1

    IFS=. read -r a b c d <<< "$ip"

    for octet in "$a" "$b" "$c" "$d"; do
        (( 10#$octet <= 255 )) || return 1
    done
}

if ! valid_ip "$DB_HOST" ||
   ! valid_ip "$GETO_IP"; then
    echo "ERROR: IP Yaga atau Geto tidak valid"
    exit 1
fi

if ! [[ "$DB_PASS" =~ ^[a-zA-Z0-9_]{8,64}$ ]]; then
    echo "ERROR: Password harus huruf/angka/_"
    echo "Panjang 8 sampai 64 karakter"
    exit 1
fi

mkdir -p /etc/no14
chmod 750 /etc/no14

cat > /etc/no14/database.php <<PHP
<?php
return [
    'host' => '$DB_HOST',
    'database' => '$DB_NAME',
    'username' => '$DB_USER',
    'password' => '$DB_PASS'
];
PHP

chown root:www-data /etc/no14/database.php
chmod 640 /etc/no14/database.php

cat > "$ROOT/api.php" <<'PHP'
<?php
header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: no-store');

$worker = gethostname();
$path = parse_url(
    $_SERVER['REQUEST_URI'] ?? '/api',
    PHP_URL_PATH
);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

/*
 * Nomor 14:
 * client_ip untuk sementara adalah IP koneksi
 * ke worker (biasanya Geto).
 * Nomor 17 nanti menerapkan real client IP.
 */
$clientIp = $_SERVER['REMOTE_ADDR'] ?? null;

try {
    $config = require '/etc/no14/database.php';

    $dsn = sprintf(
        'mysql:host=%s;port=3306;dbname=%s;charset=utf8mb4',
        $config['host'],
        $config['database']
    );

    $pdo = new PDO(
        $dsn,
        $config['username'],
        $config['password'],
        [
            PDO::ATTR_ERRMODE =>
                PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE =>
                PDO::FETCH_ASSOC,
            PDO::ATTR_TIMEOUT => 5
        ]
    );

    $stmt = $pdo->prepare(
        'INSERT INTO request_logs
         (endpoint, method, client_ip)
         VALUES (?, ?, ?)'
    );

    $stmt->execute([
        substr($path, 0, 255),
        substr($method, 0, 10),
        $clientIp
    ]);

    http_response_code(200);

    echo json_encode([
        'status' => 'success',
        'worker' => $worker,
        'endpoint' => $path,
        'method' => $method,
        'logged' => true,
        'request_id' => $pdo->lastInsertId()
    ], JSON_PRETTY_PRINT);

} catch (Throwable $e) {
    error_log('NO14 API: ' . $e->getMessage());

    http_response_code(500);

    echo json_encode([
        'status' => 'error',
        'worker' => $worker,
        'message' => 'Database logging failed'
    ]);
}
PHP

cat > "$SITE" <<EOF
server {
    listen 80;
    server_name $HOST $HOST.$DOMAIN;

    # API hanya menerima Geto
    allow $GETO_IP;
    deny all;

    location ~ ^/api(?:/|$) {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $ROOT/api.php;
        fastcgi_pass unix:$FPM_SOCKET;
    }

    location / {
        return 404;
    }

    location ~ /\\. {
        deny all;
    }
}
EOF

fi

# =========================================
# 6. AKTIFKAN NGINX VIRTUAL HOST
# =========================================

echo "[4] Mengaktifkan Nginx..."

ln -sfn "$SITE" \
    /etc/nginx/sites-enabled/no14

# Node khusus praktikum no14:
# nonaktifkan default site bawaan Nginx
rm -f /etc/nginx/sites-enabled/default

nginx -t

if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s reload
else
    nginx
fi

# =========================================
# 7. HASIL
# =========================================

echo ""
echo "=================================="
echo " NOMOR 14 - SETUP SELESAI"
echo "=================================="
echo "Node     : $HOST"
echo "Role     : $ROLE"
echo "PHP-FPM  : $FPM_SOCKET"
echo "Nginx    : konfigurasi aktif"
echo "=================================="
echo ""
echo "Periksa hasil dari jalur proxy."
echo "Frontend diakses melalui Gojo."
echo "API worker diakses melalui Geto."

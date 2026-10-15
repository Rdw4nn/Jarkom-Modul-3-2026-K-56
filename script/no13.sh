# yaga

#!/bin/bash
set -euo pipefail

# =============================================
# NOMOR 13 - MARIADB MASTER SLAVE
# YAGA MASTER / INUMAKI SLAVE
# DEBIAN 13 - GNS3
# =============================================

DB="db_shibuya_56"
NETWORK="192.239.4"
CONF="/etc/mysql/mariadb.conf.d/60-no13.cnf"
REPL_USER="replica56"
APP_USER="api56"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root"
    exit 1
fi

HOST="$(hostname -s)"

case "$HOST" in
    yaga)
        ROLE="MASTER"
        SERVER_ID=1
        ;;
    inumaki)
        ROLE="SLAVE"
        SERVER_ID=2
        ;;
    *)
        echo "ERROR: Hanya untuk yaga dan inumaki"
        exit 1
        ;;
esac

echo "======================================"
echo " SETUP MARIADB NOMOR 13"
echo " Node : $HOST"
echo " Role : $ROLE"
echo "======================================"

# =============================================
# FUNGSI MENJALANKAN MARIADB
# =============================================

start_db() {
    if mariadb-admin ping --silent \
        >/dev/null 2>&1; then
        return 0
    fi

    if [ -x /etc/init.d/mariadb ]; then
        service mariadb start || true
    fi

    if ! mariadb-admin ping --silent \
        >/dev/null 2>&1; then

        if command -v mariadbd-safe \
            >/dev/null 2>&1; then
            mariadbd-safe --user=mysql \
                >/tmp/no13-mariadb.log 2>&1 &
        elif command -v mysqld_safe \
            >/dev/null 2>&1; then
            mysqld_safe --user=mysql \
                >/tmp/no13-mariadb.log 2>&1 &
        else
            echo "ERROR: Launcher MariaDB tidak ada"
            exit 1
        fi
    fi

    for i in $(seq 1 30); do
        if mariadb-admin ping --silent \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done

    echo "ERROR: MariaDB gagal berjalan"
    cat /tmp/no13-mariadb.log 2>/dev/null || true
    exit 1
}

# =============================================
# 1. INSTALL MARIADB
# =============================================

echo "[1] Memeriksa MariaDB..."

if ! command -v mariadb >/dev/null 2>&1 ||
   ! command -v mariadbd >/dev/null 2>&1; then

    echo "Menginstal MariaDB..."

    # Resolver NAT praktikum yang telah diuji
    if ! getent hosts deb.debian.org \
        >/dev/null 2>&1; then

        if [ -f /etc/resolv.conf ]; then
            cp -n /etc/resolv.conf \
                /etc/resolv.conf.bak-no13
        fi

        printf 'nameserver 192.168.122.1\n' \
            > /etc/resolv.conf
    fi

    apt-get update
    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        mariadb-server mariadb-client
fi

mkdir -p /etc/mysql/mariadb.conf.d

# =============================================
# 2. PERIKSA DATABASE AWAL
# =============================================

echo "[2] Memeriksa layanan database..."

if [ ! -d /var/lib/mysql/mysql ]; then
    mariadb-install-db \
        --user=mysql \
        --datadir=/var/lib/mysql
fi

start_db

# Pastikan root dapat mengakses MariaDB
if ! mariadb -u root -e "SELECT 1;" \
    >/dev/null 2>&1; then
    echo "ERROR: Akses root MariaDB gagal"
    echo "Periksa autentikasi root MariaDB"
    exit 1
fi

# Slave yang sudah berkonfigurasi tidak direset
if [ "$ROLE" = "SLAVE" ]; then

    EXISTING="$(mariadb -N -B \
        -e 'SHOW SLAVE STATUS\G' || true)"

    if echo "$EXISTING" |
        grep -q 'Master_Host:'; then

        echo "Konfigurasi replikasi sudah ada."
        echo "Tidak akan ditimpa."
        echo ""
        mariadb -e 'SHOW SLAVE STATUS\G'
        exit 0
    fi
fi

# =============================================
# 3. KONFIGURASI SERVER ID DAN LOG
# =============================================

echo "[3] Mengatur server-id..."

cat > "$CONF" <<EOF
[mysqld]
server-id=$SERVER_ID
bind-address=0.0.0.0
EOF

if [ "$ROLE" = "MASTER" ]; then
    cat >> "$CONF" <<EOF
log_bin=/var/lib/mysql/no13-bin
binlog_format=ROW
EOF
else
    cat >> "$CONF" <<EOF
relay_log=/var/lib/mysql/no13-relay
read_only=ON
EOF
fi

# =============================================
# 4. RESTART DATABASE
# =============================================

echo "[4] Memuat konfigurasi baru..."

if ! mariadb-admin -u root shutdown; then
    echo "ERROR: Gagal menghentikan MariaDB"
    exit 1
fi

sleep 2
start_db

ACTUAL_ID="$(mariadb -N -B \
    -e 'SELECT @@server_id;')"

if [ "$ACTUAL_ID" != "$SERVER_ID" ]; then
    echo "ERROR: server-id tidak sesuai"
    exit 1
fi

if [ "$ROLE" = "MASTER" ]; then

    BINLOG="$(mariadb -N -B \
        -e 'SELECT @@log_bin;')"

    if [ "$BINLOG" != "1" ]; then
        echo "ERROR: Binary logging belum aktif"
        exit 1
    fi
fi

# =============================================
# 5. BUAT DATABASE DAN TABEL
# =============================================

echo "[5] Membuat database dan tabel..."

mariadb -u root <<SQL
CREATE DATABASE IF NOT EXISTS $DB;

CREATE TABLE IF NOT EXISTS $DB.request_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    endpoint VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    client_ip VARCHAR(45) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL

# =============================================
# 6. KONFIGURASI MASTER
# =============================================

if [ "$ROLE" = "MASTER" ]; then

    echo "[6] Membuat akun replikasi dan API..."

    read -r -s -p \
      "Password replikasi (huruf/angka): " REPL_PASS
    echo

    read -r -s -p \
      "Password user API (huruf/angka): " APP_PASS
    echo

    if ! [[ "$REPL_PASS" =~ ^[a-zA-Z0-9_]{8,64}$ &&
            "$APP_PASS" =~ ^[a-zA-Z0-9_]{8,64}$ ]]; then
        echo "ERROR: Password minimal 8 karakter"
        echo "Gunakan hanya huruf, angka, underscore"
        exit 1
    fi

    mariadb -u root <<SQL
CREATE USER IF NOT EXISTS
  '$REPL_USER'@'$NETWORK.%'
  IDENTIFIED BY '$REPL_PASS';

ALTER USER '$REPL_USER'@'$NETWORK.%'
  IDENTIFIED BY '$REPL_PASS';

GRANT REPLICATION SLAVE
  ON *.*
  TO '$REPL_USER'@'$NETWORK.%';

CREATE USER IF NOT EXISTS
  '$APP_USER'@'$NETWORK.%'
  IDENTIFIED BY '$APP_PASS';

ALTER USER '$APP_USER'@'$NETWORK.%'
  IDENTIFIED BY '$APP_PASS';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON $DB.*
  TO '$APP_USER'@'$NETWORK.%';
SQL

    echo ""
    echo "======================================"
    echo " MASTER YAGA SIAP"
    echo "======================================"
    echo "Database : $DB"
    echo "Tabel    : request_logs"
    echo "User replikasi : $REPL_USER"
    echo "User aplikasi : $APP_USER"
    echo ""
    echo "CATAT FILE DAN POSITION DI BAWAH:"
    mariadb -u root -e 'SHOW MASTER STATUS\G'
    echo ""
    echo "Gunakan informasi tersebut di Inumaki."
    echo "Jangan INSERT data uji sebelum"
    echo "Slave selesai dikonfigurasi."

# =============================================
# 7. KONFIGURASI SLAVE
# =============================================

else

    echo "[6] Menghubungkan Inumaki ke Yaga..."

    read -r -p "Masukkan IP Yaga: " MASTER_IP
    read -r -p "Master Log File: " LOG_FILE
    read -r -p "Master Log Position: " LOG_POS

    read -r -s -p \
      "Password replikasi Yaga: " REPL_PASS
    echo

    if ! [[ "$MASTER_IP" =~ ^192\.239\.4\.[0-9]{1,3}$ &&
            "$LOG_FILE" =~ ^[a-zA-Z0-9_.-]+$ &&
            "$LOG_POS" =~ ^[0-9]+$ &&
            "$REPL_PASS" =~ ^[a-zA-Z0-9_]{8,64}$ ]]; then
        echo "ERROR: Input koneksi tidak valid"
        exit 1
    fi

    mariadb -u root <<SQL
CHANGE MASTER TO
    MASTER_HOST='$MASTER_IP',
    MASTER_PORT=3306,
    MASTER_USER='$REPL_USER',
    MASTER_PASSWORD='$REPL_PASS',
    MASTER_LOG_FILE='$LOG_FILE',
    MASTER_LOG_POS=$LOG_POS;

START SLAVE;
SQL

    echo ""
    echo "======================================"
    echo " STATUS REPLIKASI INUMAKI"
    echo "======================================"

    sleep 5

    mariadb -u root -e 'SHOW SLAVE STATUS\G'

fi

echo ""
echo "SETUP NOMOR 13 SELESAI"
echo "Pastikan pengujian replikasi berhasil."

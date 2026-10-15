#config utahime & shoko

#!/bin/bash
set -euo pipefail

# ==========================================
# PRAKTIKUM NOMOR 11
# DNS MASTER-SLAVE BIND9
# ==========================================

DOMAIN="jujutsu.56.com"
MASTER_IP="192.239.1.2"
SLAVE_IP="192.239.1.3"
INSTALL_DNS="192.168.122.1"

ZONE_FILE="/etc/bind/zones/db.${DOMAIN}"
SLAVE_FILE="/var/cache/bind/db.${DOMAIN}"
CONF_FILE="/etc/bind/named.conf.no11.conf"

# ==========================================
# 1. CEK NODE DAN AKSES ROOT
# ==========================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root."
    exit 1
fi

HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"

case "$HOST" in
    utahime)
        ROLE="MASTER"
        LOCAL_IP="$MASTER_IP"
        ;;
    shoko)
        ROLE="SLAVE"
        LOCAL_IP="$SLAVE_IP"
        ;;
    *)
        echo "ERROR: Script hanya untuk utahime dan shoko."
        exit 1
        ;;
esac

echo "====================================="
echo "  SETUP DNS NOMOR 11"
echo "====================================="
echo "Node   : $HOST"
echo "Role   : $ROLE"
echo "IP     : $LOCAL_IP"
echo "Domain : $DOMAIN"
echo "====================================="

# ==========================================
# 2. CEK IP NODE
# ==========================================

if ! ip -4 addr show | grep -Fq "$LOCAL_IP/"; then
    echo "ERROR: IP $LOCAL_IP tidak ditemukan."
    echo "Periksa IP node terlebih dahulu."
    exit 1
fi

# ==========================================
# 3. INSTALL BIND9 JIKA DIPERLUKAN
# ==========================================

# ==========================================
# 3. SETUP DNS RESOLVER DAN INSTALL BIND9
# ==========================================

echo "[1] Memeriksa instalasi BIND9..."

if ! command -v named >/dev/null 2>&1 ||
   ! command -v named-checkconf >/dev/null 2>&1; then

    echo "Mengatur DNS resolver untuk instalasi..."

    # Backup resolver lama
    if [ -f /etc/resolv.conf ] &&
       [ ! -f /etc/resolv.conf.bak-no11 ]; then
        cp /etc/resolv.conf /etc/resolv.conf.bak-no11
    fi

    # DNS sesuai topologi praktikum
    printf 'nameserver 192.168.122.1\n' > /etc/resolv.conf

    echo "Memperbarui repository Debian..."
    apt update

    echo "Menginstal BIND9..."
    apt install -y bind9 bind9-utils bind9-dnsutils

else
    echo "BIND9 sudah terinstal, melewati instalasi."
fi

# ==========================================
# 4. SIAPKAN FILE KONFIGURASI
# ==========================================

mkdir -p /etc/bind/zones
mkdir -p /var/cache/bind

touch /etc/bind/named.conf.local

INCLUDE="include \"$CONF_FILE\";"

if ! grep -Fxq "$INCLUDE" \
    /etc/bind/named.conf.local; then

    echo "$INCLUDE" \
        >> /etc/bind/named.conf.local
fi

# ==========================================
# 5. KONFIGURASI MASTER
# ==========================================

if [ "$ROLE" = "MASTER" ]; then

    echo "[2] Mengatur Utahime sebagai MASTER..."

    cat > "$CONF_FILE" <<EOF
zone "$DOMAIN" {
    type master;

    file "$ZONE_FILE";

    allow-transfer {
        $SLAVE_IP;
    };

    also-notify {
        $SLAVE_IP;
    };

    notify yes;
};
EOF

    if [ ! -f "$ZONE_FILE" ]; then

        SERIAL="$(date +%Y%m%d)01"

        cat > "$ZONE_FILE" <<EOF
\$TTL 3600

@ IN SOA utahime.$DOMAIN. admin.$DOMAIN. (
    $SERIAL ; serial
    3600 ; refresh
    900 ; retry
    604800 ; expire
    3600 ; negative TTL
)

@ IN NS utahime.$DOMAIN.
@ IN NS shoko.$DOMAIN.

utahime IN A $MASTER_IP
shoko   IN A $SLAVE_IP
EOF

    fi

    # Mode uji update zona
    if [ "${1:-}" = "--update" ]; then

        OLD_SERIAL="$(awk '/; serial/ {
            print $1
            exit
        }' "$ZONE_FILE")"

        if ! [[ "$OLD_SERIAL" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Format serial tidak dikenali."
            exit 1
        fi

        NEW_SERIAL="$((10#$OLD_SERIAL + 1))"

        sed -i \
            "s/$OLD_SERIAL ; serial/$NEW_SERIAL ; serial/" \
            "$ZONE_FILE"

        if ! grep -q '^uji11[[:space:]]' \
            "$ZONE_FILE"; then

            echo 'uji11 IN TXT "Sinkronisasi DNS berhasil"' \
                >> "$ZONE_FILE"
        fi

        echo "[3] Serial naik:"
        echo "    $OLD_SERIAL -> $NEW_SERIAL"
    fi

    chown root:bind "$ZONE_FILE"
    chmod 644 "$ZONE_FILE"

    echo "[4] Validasi zona Master..."

    named-checkzone "$DOMAIN" "$ZONE_FILE"

# ==========================================
# 6. KONFIGURASI SLAVE
# ==========================================

else

    if [ "${1:-}" = "--update" ]; then
        echo "ERROR: --update hanya untuk Utahime."
        exit 1
    fi

    echo "[2] Mengatur Shoko sebagai SLAVE..."

    cat > "$CONF_FILE" <<EOF
zone "$DOMAIN" {
    type slave;

    masters {
        $MASTER_IP;
    };

    file "$SLAVE_FILE";

    allow-notify {
        $MASTER_IP;
    };

    transfer-source $SLAVE_IP;
};
EOF

    chown bind:bind /var/cache/bind

    echo "[3] Zona akan diambil dari Utahime."
fi

# ==========================================
# 7. VALIDASI KONFIGURASI
# ==========================================

echo "[5] Memvalidasi konfigurasi BIND9..."

named-checkconf

# ==========================================
# 8. JALANKAN ATAU RELOAD BIND9
# ==========================================

echo "[6] Menjalankan DNS Server..."

if rndc status >/dev/null 2>&1; then

    echo "BIND9 sudah aktif. Reconfig..."

    rndc reconfig

    if [ "$ROLE" = "MASTER" ]; then
        rndc reload "$DOMAIN" IN
    fi

else

    if pgrep -x named >/dev/null 2>&1; then
        echo "ERROR: named berjalan tetapi rndc gagal."
        echo "Periksa konfigurasi kontrol BIND9."
        exit 1
    fi

    named -u bind -c /etc/bind/named.conf
fi

# ==========================================
# 9. PENGUJIAN DNS
# ==========================================

echo "[7] Menunggu DNS siap..."

READY=0

for i in $(seq 1 15); do

    if dig @"$LOCAL_IP" "$DOMAIN" SOA \
        +norecurse +time=2 +tries=1 \
        +noall +answer | grep -q ' SOA '; then

        READY=1
        break
    fi

    sleep 2
done

if [ "$READY" -eq 1 ]; then

    echo ""
    echo "=== SOA ==="

    dig @"$LOCAL_IP" "$DOMAIN" SOA \
        +norecurse +noall +answer

    echo ""
    echo "=== NS ==="

    dig @"$LOCAL_IP" "$DOMAIN" NS \
        +norecurse +noall +answer

    echo ""
    echo "====================================="
    echo " DNS SERVER BERHASIL MENJAWAB"
    echo " Node : $HOST"
    echo " Role : $ROLE"
    echo "====================================="

else

    echo ""
    exit 1
fi
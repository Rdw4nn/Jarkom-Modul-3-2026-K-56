#config di utahime & shoko

#gojo -> printf 'nameserver 192.239.1.2\nnameserver 192.239.1.3\n' > /etc/resolv.conf

#!/bin/bash
set -euo pipefail

# ==============================================
# NOMOR 12 - DNS A, CNAME, PTR, FORWARDER
# Debian 13 - BIND9 - GNS3
# ==============================================

DOMAIN="jujutsu.56.com"
MASTER="192.239.1.2"
SLAVE="192.239.1.3"
GOJO="192.239.1.4"
FORWARDER="192.168.122.1"

REVERSE="1.239.192.in-addr.arpa"

FORWARD_FILE="/etc/bind/zones/db.$DOMAIN"
REVERSE_FILE="/etc/bind/zones/db.$REVERSE"
SLAVE_FILE="/var/cache/bind/db.$REVERSE"

OPTIONS="/etc/bind/named.conf.options"
LOCAL="/etc/bind/named.conf.local"
CONF12="/etc/bind/named.conf.no12.conf"

# ==============================================
# 1. CEK NODE
# ==============================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root"
    exit 1
fi

HOST="$(hostname -s)"

case "$HOST" in
    utahime)
        ROLE="MASTER"
        IP="$MASTER"
        ;;
    shoko)
        ROLE="SLAVE"
        IP="$SLAVE"
        ;;
    *)
        echo "ERROR: Hanya untuk Utahime/Shoko"
        exit 1
        ;;
esac

echo "======================================"
echo "       SETUP DNS NOMOR 12"
echo "======================================"
echo "Node      : $HOST"
echo "Role      : $ROLE"
echo "IP        : $IP"
echo "Domain    : $DOMAIN"
echo "Gojo      : $GOJO"
echo "Forwarder : $FORWARDER"
echo "======================================"

# ==============================================
# 2. PERIKSA BIND9 DAN NOMOR 11
# ==============================================

echo "[1] Memeriksa BIND9..."

for CMD in named named-checkconf dig rndc; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: Perintah $CMD tidak tersedia"
        echo "Pastikan nomor 11 sudah disetup"
        exit 1
    fi
done

if ! rndc status >/dev/null 2>&1; then
    echo "ERROR: BIND9 belum berjalan"
    exit 1
fi

if ! rndc zonestatus "$DOMAIN" IN \
    >/dev/null 2>&1; then
    echo "ERROR: Zona nomor 11 belum aktif"
    exit 1
fi

if [ ! -f "$OPTIONS" ] ||
   [ ! -f "$LOCAL" ]; then
    echo "ERROR: Konfigurasi BIND9 tidak lengkap"
    exit 1
fi

# ==============================================
# 3. BACKUP KONFIGURASI
# ==============================================

echo "[2] Membuat backup..."

for FILE in "$OPTIONS" "$LOCAL"; do
    if [ ! -f "$FILE.bak-no12" ]; then
        cp "$FILE" "$FILE.bak-no12"
    fi
done

if [ "$ROLE" = "MASTER" ]; then
    if [ ! -f "$FORWARD_FILE" ]; then
        echo "ERROR: Zona Master nomor 11 hilang"
        exit 1
    fi

    if [ ! -f "$FORWARD_FILE.bak-no12" ]; then
        cp "$FORWARD_FILE" \
           "$FORWARD_FILE.bak-no12"
    fi
fi

# ==============================================
# 4. SETUP DNS FORWARDER
# ==============================================

echo "[3] Mengatur DNS Forwarder..."

# Hapus hanya konfigurasi nomor 12 sebelumnya
sed -i '/\/\/ BEGIN NO12/,/\/\/ END NO12/d' \
    "$OPTIONS"

# Cegah duplikasi opsi yang sudah ada
if grep -Eq '^[[:space:]]*(recursion|allow-recursion|forwarders|forward)[[:space:];{]' \
    "$OPTIONS"; then
    echo "ERROR: Ada opsi DNS serupa di $OPTIONS"
    echo "Periksa sebelum menjalankan ulang"
    exit 1
fi

# Sisipkan konfigurasi di dalam blok options
awk -v fwd="$FORWARDER" '
/^[[:space:]]*options[[:space:]]*\{/ && !added {
    print
    print "    // BEGIN NO12"
    print "    recursion yes;"
    print "    allow-recursion {"
    print "        localhost;"
    print "        192.239.0.0/16;"
    print "    };"
    print "    forwarders { " fwd "; };"
    print "    forward only;"
    print "    // END NO12"
    added=1
    next
}
{ print }
END {
    if (!added) exit 1
}
' "$OPTIONS" > "$OPTIONS.tmp-no12"

mv "$OPTIONS.tmp-no12" "$OPTIONS"

# ==============================================
# 5. REVERSE DNS
# ==============================================

echo "[4] Mengatur Reverse DNS..."

mkdir -p /etc/bind/zones
mkdir -p /var/cache/bind

if [ "$ROLE" = "MASTER" ]; then

    cat > "$CONF12" <<EOF
zone "$REVERSE" {
    type master;
    file "$REVERSE_FILE";

    allow-transfer { $SLAVE; };
    also-notify { $SLAVE; };
    notify yes;
};
EOF

    # Buat reverse zone hanya jika belum ada
    if [ ! -f "$REVERSE_FILE" ]; then

        SERIAL="$(date +%Y%m%d)01"

        cat > "$REVERSE_FILE" <<EOF
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

4 IN PTR $DOMAIN.
EOF

    elif ! grep -Eq \
        '^[[:space:]]*4[[:space:]]+IN[[:space:]]+PTR[[:space:]]+jujutsu\.56\.com\.' \
        "$REVERSE_FILE"; then

        echo "ERROR: Zona reverse sudah ada"
        echo "tetapi PTR Gojo belum sesuai."
        echo "Periksa $REVERSE_FILE"
        exit 1
    fi

    chmod 644 "$REVERSE_FILE"

    named-checkzone "$REVERSE" "$REVERSE_FILE"

else

    cat > "$CONF12" <<EOF
zone "$REVERSE" {
    type slave;
    masters { $MASTER; };

    file "$SLAVE_FILE";

    allow-notify { $MASTER; };
    transfer-source $SLAVE;
};
EOF

    chown bind:bind /var/cache/bind
fi

# Include konfigurasi reverse
INCLUDE="include \"$CONF12\";"

if ! grep -Fxq "$INCLUDE" "$LOCAL"; then
    echo "$INCLUDE" >> "$LOCAL"
fi

# ==============================================
# 6. FORWARD ZONE: A DAN CNAME
# ==============================================

if [ "$ROLE" = "MASTER" ]; then

    echo "[5] Mengatur A dan CNAME..."

    # Hapus blok record nomor 12 jika sudah ada
    sed -i '/; BEGIN NO12 RECORDS/,/; END NO12 RECORDS/d' \
        "$FORWARD_FILE"

    # Cegah konflik dengan record dari sumber lain
    if grep -Eq \
        '^[[:space:]]*@[[:space:]]+IN[[:space:]]+A[[:space:]]' \
        "$FORWARD_FILE" ||
       grep -Eq \
        '^[[:space:]]*www[[:space:]]+IN[[:space:]]+(CNAME|A)[[:space:]]' \
        "$FORWARD_FILE"; then

        echo "ERROR: Record A atau www sudah ada"
        echo "Periksa $FORWARD_FILE"
        exit 1
    fi

    cat >> "$FORWARD_FILE" <<EOF

; BEGIN NO12 RECORDS
@   IN A     $GOJO
www IN CNAME $DOMAIN.
; END NO12 RECORDS
EOF

    # Baca serial SOA saat ini
    OLD_SERIAL="$(awk '
        /SOA/ { soa=1; next }
        soa && $1 ~ /^[0-9]+$/ {
            print $1
            exit
        }
    ' "$FORWARD_FILE")"

    if ! [[ "$OLD_SERIAL" =~ ^[0-9]{10}$ ]]; then
        echo "ERROR: Serial SOA tidak valid"
        exit 1
    fi

    # Naikkan serial hanya jika setup awal
    # atau terdapat perubahan isi zona
    CURRENT_HASH="$(sha256sum "$FORWARD_FILE" | cut -d' ' -f1)"
    OLD_HASH_FILE="/etc/bind/.no12-zone-hash"

    if [ ! -f "$OLD_HASH_FILE" ] ||
       [ "$(cat "$OLD_HASH_FILE")" != "$CURRENT_HASH" ]; then

        NEW_SERIAL="$((10#$OLD_SERIAL + 1))"

        sed -i \
            "s/^[[:space:]]*$OLD_SERIAL[[:space:]]*; serial/    $NEW_SERIAL ; serial/" \
            "$FORWARD_FILE"

        echo "Serial: $OLD_SERIAL -> $NEW_SERIAL"
    fi

    named-checkzone "$DOMAIN" "$FORWARD_FILE"

    sha256sum "$FORWARD_FILE" |
        cut -d' ' -f1 > "$OLD_HASH_FILE"
fi

# ==============================================
# 7. VALIDASI DAN RELOAD
# ==============================================

echo "[6] Memvalidasi BIND9..."

named-checkconf
named-checkconf -z

echo "[7] Menerapkan konfigurasi..."

rndc reconfig

sleep 3

if [ "$ROLE" = "MASTER" ]; then
    rndc reload "$DOMAIN" IN
fi

# ==============================================
# 8. PENGUJIAN
# ==============================================

echo "[8] Menguji DNS..."

READY=0

for i in $(seq 1 30); do

    RESPONSE="$(dig @"$IP" "$DOMAIN" SOA \
        +norecurse +time=2 +tries=1 2>&1 || true)"

    if echo "$RESPONSE" | grep -q 'status: NOERROR' &&
       echo "$RESPONSE" | grep -q 'flags:.*aa'; then
        READY=1
        break
    fi

    sleep 2
done

if [ "$READY" -ne 1 ]; then
    echo "ERROR: DNS belum menjawab SOA"
    exit 1
fi

echo ""
echo "=== SOA ==="
dig @"$IP" "$DOMAIN" SOA +short

echo ""
echo "=== A RECORD ==="
dig @"$IP" "$DOMAIN" A +short

echo ""
echo "=== CNAME ==="
dig @"$IP" "www.$DOMAIN" CNAME +short

echo ""
echo "=== PTR ==="
dig @"$IP" -x "$GOJO" +short

echo ""
echo "=== FORWARDER ==="
dig @"$IP" google.com A +short

echo ""
echo "======================================"
echo " SETUP NOMOR 12 SELESAI"
echo " Node : $HOST"
echo "======================================"
echo "Periksa hasil A, CNAME, PTR dan Internet"
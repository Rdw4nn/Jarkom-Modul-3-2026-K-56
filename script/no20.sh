#kusakabe

#!/bin/bash
set -euo pipefail

# ==========================================
# NOMOR 20 - APACHEBENCH BENCHMARK
# NODE: KUSAKABE
# ==========================================

DOMAIN="jujutsu.56.com"
HASIL="/root/no20-results"

echo "======================================"
echo " NOMOR 20 - APACHEBENCH"
echo " Node: $(hostname -s)"
echo "======================================"

# 1. VALIDASI NODE
if [ "$(hostname -s)" != "kusakabe" ]; then
    echo "ERROR: Script hanya untuk Kusakabe!"
    exit 1
fi

# 2. PERIKSA APACHEBENCH
echo "[1] Memeriksa ApacheBench..."

if ! command -v ab >/dev/null 2>&1; then
    echo "ApacheBench belum terinstal."
    echo "Jalankan: apk add apache2-utils"
    exit 1
fi

# 3. PERIKSA DNS
echo "[2] Memeriksa DNS..."

if ! nslookup "$DOMAIN" >/dev/null 2>&1; then
    echo "ERROR: Domain tidak dapat di-resolve."
    echo "Periksa DNS Utahime dan Shoko."
    exit 1
fi

# 4. BUAT FOLDER HASIL
mkdir -p "$HASIL"

# 5. BENCHMARK FRONTEND
echo ""
echo "[3] Benchmark frontend..."
echo "600 request, concurrency 30"

ab -n 600 -c 30 \
    "http://${DOMAIN}/" \
    > "$HASIL/frontend.txt"

echo "Benchmark frontend selesai."

# 6. BENCHMARK API
echo ""
echo "[4] Benchmark API..."
echo "600 request, concurrency 30"

ab -n 600 -c 30 \
    "http://${DOMAIN}/api" \
    > "$HASIL/api.txt"

echo "Benchmark API selesai."

# 7. TAMPILKAN HASIL FRONTEND
echo ""
echo "======================================"
echo " HASIL BENCHMARK FRONTEND"
echo "======================================"

grep -E \
'Complete requests:|Failed requests:|Non-2xx responses:|Requests per second:|Time per request:|Time taken for tests:' \
"$HASIL/frontend.txt"

# 8. TAMPILKAN HASIL API
echo ""
echo "======================================"
echo " HASIL BENCHMARK API"
echo "======================================"

grep -E \
'Complete requests:|Failed requests:|Non-2xx responses:|Requests per second:|Time per request:|Time taken for tests:' \
"$HASIL/api.txt"

echo ""
echo "======================================"
echo " NOMOR 20 SELESAI"
echo "======================================"
echo "Frontend: $HASIL/frontend.txt"
echo "API     : $HASIL/api.txt"
echo "======================================"

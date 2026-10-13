# Jarkom-Modul-3-2026-K-56

| No  | Nama                           | NRP        | Pengerjaan |
| --- | ------------------------------ | ---------- | ---------- |
| 1   | Sahira Bilqis Rivadito         | 5027251037 | No 1-10    |
| 2   | Muhammmad Ridwan               | 5027251113 | No 11-20   |

## LAPORAN RESMI MODUL 3

# SOAL 1 | Konektivitas Dasar (jichi sebagai Router)

Kelompok: K56 | Prefix IP: `192.239.x.x`

> Ketika Curtain menutup Shibuya, jalur komunikasi antar zona Jujutsu High terputus. Pulihkan konektivitas dasar dengan mengonfigurasi jichi: eth0 memperoleh WAN dari NAT, sedangkan eth1–eth4 menjadi gateway Network 1–4 sesuai tabel pemetaan. Aktifkan IPv4 forwarding dan source NAT, lalu tetapkan IP statis host infrastruktur sesuai tabel spesifikasi. Buktikan konektivitas setiap host ke gateway dan akses eksternal dari host yang relevan.

## 1. Tujuan

Memulihkan konektivitas dasar antar jaringan:

- jichi `eth0` memperoleh WAN dari NAT (DHCP)
- jichi `eth1`–`eth4` menjadi gateway Network 1–4 (/24)
- IPv4 forwarding dan source NAT (MASQUERADE) aktif
- Host infrastruktur memakai IP statis
- Membuktikan konektivitas tiap host ke gateway dan akses eksternal

## 2. Rancangan Alamat

| Network | Subnet | Gateway (jichi) | Interface jichi |
|---|---|---|---|
| NAT | 192.168.122.0/24 | 192.168.122.1 | eth0 (DHCP) |
| Network 1 (DMZ) | 192.239.1.0/24 | 192.239.1.1 | eth1 |
| Network 2 (Divisi A) | 192.239.2.0/24 | 192.239.2.1 | eth2 |
| Network 3 (Divisi B) | 192.239.3.0/24 | 192.239.3.1 | eth3 |
| Network 4 (Data Center) | 192.239.4.0/24 | 192.239.4.1 | eth4 |

### IP statis host infrastruktur

| Host | Peran | Network | IP | Gateway |
|---|---|---|---|---|
| utahime | DNS Master | 1 | 192.239.1.2 | 192.239.1.1 |
| shoko | DNS Slave | 1 | 192.239.1.3 | 192.239.1.1 |
| gojo | Reverse Proxy | 1 | 192.239.1.4 | 192.239.1.1 |
| geto | Load Balancer | 4 | 192.239.4.2 | 192.239.4.1 |
| maki | Worker frontend | 4 | 192.239.4.3 | 192.239.4.1 |
| panda | Worker frontend | 4 | 192.239.4.4 | 192.239.4.1 |
| nanami | Worker API utama | 4 | 192.239.4.5 | 192.239.4.1 |
| todo | Worker API utama | 4 | 192.239.4.6 | 192.239.4.1 |
| kirara | Worker API cadangan | 4 | 192.239.4.7 | 192.239.4.1 |
| inumaki | DB Slave | 4 | 192.239.4.8 | 192.239.4.1 |
| yaga | DB Master | 4 | 192.239.4.9 | 192.239.4.1 |
| tengen | DHCP Server | 4 | 192.239.4.10 | 192.239.4.1 |

Klien Network 2 dan 3 tidak diberi IP statis karena memperoleh alamat melalui DHCP relay (soal berikutnya).

## 3. Konfigurasi

### 3.1 jichi – `/etc/network/interfaces`

```
auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet static
    address 192.239.1.1
    netmask 255.255.255.0

auto eth2
iface eth2 inet static
    address 192.239.2.1
    netmask 255.255.255.0

auto eth3
iface eth3 inet static
    address 192.239.3.1
    netmask 255.255.255.0

auto eth4
iface eth4 inet static
    address 192.239.4.1
    netmask 255.255.255.0
```

### 3.2 jichi – IP forwarding dan source NAT

Bagian forwarding dan NAT pada `/root/setup-jichi.sh`:

```bash
#!/bin/bash
# IPv4 forwarding (langsung aktif + permanen)
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-forward.conf
sysctl --system >/dev/null

# Source NAT (idempotent)
apt update && apt install -y iptables
iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

Catatan: `/etc/sysctl.conf` tidak ada di Debian trixie, sehingga forwarding permanen ditulis ke `/etc/sysctl.d/99-forward.conf`.

### 3.3 Host infrastruktur – contoh (utahime)

`/etc/network/interfaces`:

```
auto eth0
iface eth0 inet static
    address 192.239.1.2
    netmask 255.255.255.0
    gateway 192.239.1.1
```

Host lain memakai pola yang sama, hanya `address` dan `gateway` yang berbeda sesuai tabel pada bagian 2.

Untuk persiapan awal (unduh paket), DNS sementara:

```bash
echo "nameserver 192.168.122.1" > /etc/resolv.conf
```

## 4. Pembuktian

### 4.1 jichi

```bash
ip -br a
cat /proc/sys/net/ipv4/ip_forward
cat /etc/sysctl.d/99-forward.conf
iptables -t nat -S POSTROUTING
ip route
ping -c2 8.8.8.8
```

Hasil yang diharapkan:

- `eth0` memperoleh `192.168.122.x/24`; `eth1`–`eth4` bernilai `192.239.1.1` s.d. `192.239.4.1` dengan /24
- `ip_forward` bernilai `1`
- Terdapat aturan `-A POSTROUTING -o eth0 -j MASQUERADE`
- Ping ke `8.8.8.8` berhasil

> Screenshot: `[01-jichi.png]`

### 4.2 Setiap host infrastruktur

Dijalankan pada utahime, shoko, gojo, geto, maki, panda, nanami, todo, kirara, inumaki, yaga, dan tengen:

```bash
ip -br a show eth0
ping -c2 $(ip route | awk '/default/{print $3}')   # gateway
ping -c2 8.8.8.8                                    # akses eksternal
```

Hasil yang diharapkan: IP sesuai tabel, ping ke gateway dan ke `8.8.8.8` berhasil.

| Host | Screenshot |
|---|---|
| utahime, shoko, gojo, geto | `[02-utahime.png]` |
| maki, panda, nanami, todo | `[06-maki.png]` |
| kirara, inumaki, yaga, tengen | `[10-kirara.png]` |

## 5. Kesimpulan

jichi berfungsi sebagai router: forwarding aktif, source NAT memberi akses internet, dan seluruh host infrastruktur terhubung ke gateway masing-masing serta dapat mengakses jaringan eksternal.

## 6. Pemulihan setelah restart

Aturan iptables tidak persisten. Setelah node restart, jalankan ulang script:

```bash
./setup-jichi.sh
```

# SOAL 2 | DHCP Server pada tengen

Kelompok: K56 | Prefix IP: `192.239.x.x`

> Tengen, penjaga pusat distribusi di Data Center, harus mengambil alih pengalokasian alamat bagi wilayah yang membutuhkan konfigurasi dinamis. Konfigurasikan isc-dhcp-server pada [PREFIX IP].4.10. Deklarasikan Network 4 ([PREFIX IP].4.0/24) sebagai subnet lokal tanpa pool dinamis, lalu siapkan scope DHCP untuk Network 2 ([PREFIX IP].2.0/24) dan Network 3 ([PREFIX IP].3.0/24). Validasi konfigurasi dan pastikan service aktif tanpa error “No subnet declaration”.

## 1. Tujuan

- Mengonfigurasi `isc-dhcp-server` pada tengen (`192.239.4.10`)
- Mendeklarasikan Network 4 (`192.239.4.0/24`) sebagai subnet lokal tanpa pool dinamis
- Menyiapkan scope DHCP untuk Network 2 (`192.239.2.0/24`) dan Network 3 (`192.239.3.0/24`)
- Memvalidasi konfigurasi dan memastikan service aktif tanpa error "No subnet declaration"

## 2. Rancangan

| Subnet | Peran | Pool dinamis |
|---|---|---|
| 192.239.4.0/24 | Subnet lokal tengen (Data Center) | Tidak ada |
| 192.239.2.0/24 | Divisi A (via relay jichi) | Ada |
| 192.239.3.0/24 | Divisi B (via relay jichi) | Ada |

Subnet 4.0 wajib dideklarasikan walau kosong. Tanpa deklarasi tersebut, dhcpd tidak menemukan subnet yang cocok dengan interface `eth0` (`192.239.4.10`) dan muncul error "No subnet declaration".

## 3. Konfigurasi

### 3.1 IP tengen – `/etc/network/interfaces`

```
auto eth0
iface eth0 inet static
    address 192.239.4.10
    netmask 255.255.255.0
    gateway 192.239.4.1
```

### 3.2 Script `/root/setup-tengen.sh`

Versi dasar untuk soal ini (range sementara; pool final diatur pada soal 4 dan seterusnya):

```bash
#!/bin/bash
echo "nameserver 192.168.122.1" > /etc/resolv.conf

# apt update boleh error (repo security), yang penting paket terpasang
apt update || true
apt install -y isc-dhcp-server

cat > /etc/default/isc-dhcp-server <<'EOF'
INTERFACESv4="eth0"
EOF

cat > /etc/dhcp/dhcpd.conf <<'EOF'
default-lease-time 600;
max-lease-time 7200;
authoritative;

# Network 4: subnet lokal, tanpa pool dinamis
subnet 192.239.4.0 netmask 255.255.255.0 {
}

# Network 2 (Divisi A)
subnet 192.239.2.0 netmask 255.255.255.0 {
    option routers 192.239.2.1;
    option subnet-mask 255.255.255.0;
    range 192.239.2.10 192.239.2.50;
}

# Network 3 (Divisi B)
subnet 192.239.3.0 netmask 255.255.255.0 {
    option routers 192.239.3.1;
    option subnet-mask 255.255.255.0;
    range 192.239.3.10 192.239.3.50;
}
EOF

dhcpd -t -cf /etc/dhcp/dhcpd.conf && service isc-dhcp-server restart
service isc-dhcp-server status
```

Jalankan:

```bash
chmod +x /root/setup-tengen.sh
/root/setup-tengen.sh
```

## 4. Validasi dan Pembuktian

Dijalankan pada tengen:

```bash
ip -br a show eth0
dhcpd -t -cf /etc/dhcp/dhcpd.conf; echo "exit code: $?"
service isc-dhcp-server status
ps aux | grep [d]hcpd
cat /etc/dhcp/dhcpd.conf
```

Hasil yang diharapkan:

- `eth0` bernilai `192.239.4.10/24`
- `dhcpd -t` tanpa error, `exit code: 0`
- `dhcpd is running`
- Tidak ada pesan "No subnet declaration"
- `dhcpd.conf` memuat tiga deklarasi subnet (4.0 kosong, 2.0, 3.0)

> Screenshot:
> - `[01-tengen-ip.png]` – IP tengen
> - `[02-dhcpd-test.png]` – `dhcpd -t` exit code 0
> - `[03-dhcpd-status.png]` – service running
> - `[04-dhcpd-conf.png]` – isi `dhcpd.conf`

## 5. Kesimpulan

isc-dhcp-server pada tengen berjalan dengan deklarasi subnet Network 4 (tanpa pool) serta scope untuk Network 2 dan Network 3. Konfigurasi lolos validasi dan service aktif tanpa error "No subnet declaration". Pembuktian pemberian lease ke klien melalui relay dilakukan pada soal 3.

## 6. Pemulihan setelah restart

```bash
service isc-dhcp-server restart
# jika dhcpd.conf atau paket hilang:
/root/setup-tengen.sh
```

# SOAL 3 | DHCP Relay pada jichi

Kelompok: K56 | Prefix IP: `192.239.x.x`

> Permintaan alamat dari Divisi A dan Divisi B tidak dapat menyeberangi subnet secara langsung. Konfigurasikan jichi sebagai DHCP Relay menuju tengen ([PREFIX IP].4.10), menggunakan eth2 untuk Network 2 dan eth3 untuk Network 3. Buktikan bahwa client dari kedua subnet berhasil memperoleh lease melalui relay.

## 1. Tujuan

Permintaan alamat dari Divisi A dan Divisi B tidak dapat menyeberangi subnet secara langsung (broadcast tidak dilewatkan router). jichi dikonfigurasi sebagai DHCP Relay menuju tengen (`192.239.4.10`):

- `eth2` untuk Network 2
- `eth3` untuk Network 3
- Membuktikan klien kedua subnet memperoleh lease melalui relay

## 2. Alur kerja relay

```
Klien (N2/N3) --broadcast DISCOVER--> jichi (eth2/eth3)
jichi --unicast, giaddr = IP interface penerima--> tengen (192.239.4.10)
tengen --OFFER/ACK ke giaddr--> jichi --> Klien
```

| Klien | Interface jichi penerima | giaddr |
|---|---|---|
| Network 2 | eth2 | 192.239.2.1 |
| Network 3 | eth3 | 192.239.3.1 |

## 3. Konfigurasi

### 3.1 `/etc/default/isc-dhcp-relay` pada jichi

```
SERVERS="192.239.4.10"
INTERFACES=""
OPTIONS="-id eth2 -id eth3 -iu eth4"
```

- `-id eth2 -id eth3`: interface sisi klien (downstream)
- `-iu eth4`: interface sisi server (upstream) menuju Data Center

### 3.2 Bagian relay pada `/root/setup-jichi.sh`

```bash
apt update && apt install -y isc-dhcp-relay

cat > /etc/default/isc-dhcp-relay <<'EOF'
SERVERS="192.239.4.10"
INTERFACES=""
OPTIONS="-id eth2 -id eth3 -iu eth4"
EOF

service isc-dhcp-relay restart
service isc-dhcp-relay status
```

### 3.3 Klien menggunakan DHCP

`/etc/network/interfaces` pada itadori, fushiguro, zenin, okkotsu, ino, kusakabe, miwa, dan kugisaki:

```
auto eth0
iface eth0 inet dhcp
```

## 4. Pembuktian

### 4.1 jichi

```bash
cat /etc/default/isc-dhcp-relay
ps aux | grep [d]hcrelay
```

Hasil yang diharapkan: tujuan `192.239.4.10`, proses `dhcrelay -q -id eth2 -id eth3 -iu eth4 192.239.4.10`.

> Screenshot: `[01-jichi-relay.png]`

### 4.2 Klien Network 2 (itadori)

```bash
ifdown eth0; ifup eth0
ip -br a show eth0
ip route | grep default
```

Hasil: `lease of 192.239.2.x obtained from 192.239.4.10`, IP `192.239.2.x/24`, default route `192.239.2.1`.

> Screenshot: `[02-itadori-lease.png]`

### 4.3 Klien Network 3 (miwa)

Perintah sama seperti di atas.

Hasil: `lease of 192.239.3.x obtained from 192.239.4.10`, IP `192.239.3.x/24`, default route `192.239.3.1`.

> Screenshot: `[03-miwa-lease.png]`

### 4.4 Sisi server (tengen)

```bash
grep -E "^lease|hardware ethernet" /var/lib/dhcp/dhcpd.leases | tail -n 20
```

Hasil: terdapat lease untuk `192.239.2.x` dan `192.239.3.x` beserta MAC klien, membuktikan permintaan dari kedua subnet sampai ke tengen.

> Screenshot: `[04-tengen-leases.png]`

### 4.5 Bukti tambahan (opsional): tangkap paket

Pada tengen:

```bash
tcpdump -ni eth0 port 67 or port 68
```

Discover/Request tampak dari `192.239.4.1` (jichi eth4) ke `192.239.4.10`, sedangkan Offer/ACK dikirim tengen ke `192.239.2.1` atau `192.239.3.1` (giaddr), sehingga membuktikan paket diteruskan oleh relay.

> Screenshot: `[05-tcpdump.png]`

## 5. Kesimpulan

jichi berfungsi sebagai DHCP Relay: eth2 dan eth3 menerima broadcast dari Network 2 dan 3, meneruskannya ke tengen (`192.239.4.10`) lewat eth4, dan membawa balasan kembali ke klien. Klien kedua subnet berhasil memperoleh lease dari tengen.

## 6. Pemulihan setelah restart

```bash
./setup-jichi.sh
```

Script ini menulis ulang konfigurasi relay yang benar dan menjalankan service.


# SOAL 4 | Dua Pool DHCP pada Network 2

Kelompok: K56 | Prefix IP: `192.239`

## 1. Tujuan

Tim Dev dan Support di Divisi A menerima jatah alamat yang berbeda. Dua pool dibuat pada Network 2:

| Pool | Rentang | Klien |
|---|---|---|
| Pool 1 | 192.239.2.10 – 192.239.2.35 | itadori, fushiguro |
| Pool 2 | 192.239.2.70 – 192.239.2.95 | zenin, okkotsu |

Rentang `192.239.2.36 – 192.239.2.69` tidak boleh dialokasikan. Karena seluruh klien berada pada subnet yang sama, pemisahan dilakukan dengan DHCP class berdasarkan MAC Address.

## 2. Rancangan

- Setiap kelompok klien didefinisikan sebagai `class` yang dicocokkan dengan MAC (`substring(hardware, 1, 6)`).
- Setiap `pool` dibatasi dengan `allow members of "<class>"`, sehingga hanya anggota class tersebut yang dilayani dari range pool itu.
- Rentang `.36–.69` tidak dimasukkan ke range manapun, sehingga tidak pernah dialokasikan.

### Pemetaan MAC

MAC diambil dari tiap klien dengan `ip link show eth0 | grep ether`.

| Klien | MAC | Class |
|---|---|---|
| itadori | 02:42:7d:a7:cb:00 | pool1 |
| fushiguro | 02:42:d6:51:ef:00 | pool1 |
| zenin | f2:dd:ec:51:c9:cb | pool2 |
| okkotsu | 02:42:54:9b:57:00 | pool2 |

Catatan: MAC zenin sebelumnya `02:42:30:6b:50:00` dan berubah setelah node di-restart/dibuat ulang (lihat bagian 4).

## 3. Konfigurasi

Blok Network 2 pada heredoc `dhcpd.conf` di `/root/setup-tengen.sh`:

```
# Network 2 (Divisi A)
class "pool1" {
    match if (substring(hardware, 1, 6) = 02:42:7d:a7:cb:00)
          or (substring(hardware, 1, 6) = 02:42:d6:51:ef:00);
}

class "pool2" {
    match if (substring(hardware, 1, 6) = f2:dd:ec:51:c9:cb)
          or (substring(hardware, 1, 6) = 02:42:54:9b:57:00);
}

subnet 192.239.2.0 netmask 255.255.255.0 {
    option routers 192.239.2.1;
    option subnet-mask 255.255.255.0;

    pool {
        allow members of "pool1";
        range 192.239.2.10 192.239.2.35;
    }

    pool {
        allow members of "pool2";
        range 192.239.2.70 192.239.2.95;
    }
}
```

Terapkan dan validasi:

```bash
./setup-tengen.sh
dhcpd -t -cf /etc/dhcp/dhcpd.conf; echo "exit code: $?"
```

Karena klien masih memegang lease dari range lama, lease dikosongkan agar klien meminta ulang:

```bash
service isc-dhcp-server stop
: > /var/lib/dhcp/dhcpd.leases
service isc-dhcp-server start
```

Lalu pada tiap klien Network 2:

```bash
ifdown eth0; ifup eth0
```

## 4. Pembuktian

### 4.1 Klien Network 2

Pada itadori, fushiguro, zenin, dan okkotsu:

```bash
ip link show eth0 | grep ether
ifdown eth0; ifup eth0
ip -4 addr show eth0
```

| Klien | IP yang diharapkan |
|---|---|
| itadori, fushiguro | 192.239.2.10 – .35 |
| zenin, okkotsu | 192.239.2.70 – .95 |

Hasil terverifikasi sejauh ini:

- itadori: `192.239.2.11` (Pool 1)
- fushiguro: `192.239.2.14` (Pool 1)
- okkotsu: `192.239.2.70` (Pool 2)
- zenin: diverifikasi ulang setelah MAC diperbarui

> Screenshot: `[01-itadori.png]`, `[02-fushiguro.png]`, `[03-zenin.png]`, `[04-okkotsu.png]`

### 4.2 Sisi server (tengen)

```bash
cat /etc/dhcp/dhcpd.conf
dhcpd -t -cf /etc/dhcp/dhcpd.conf; echo "exit code: $?"
grep -E "^lease|hardware ethernet|^  binding state" /var/lib/dhcp/dhcpd.leases
```

Hasil yang diharapkan: konfigurasi memuat class dan dua pool, exit code `0`, dan tidak ada lease pada `192.239.2.36 – .69`.

> Screenshot: `[05-dhcpd-conf.png]`, `[06-dhcpd-test.png]`, `[07-leases.png]`

## 5. Kesimpulan

Network 2 dilayani dua pool terpisah berdasarkan class MAC: itadori dan fushiguro memperoleh alamat dari Pool 1, zenin dan okkotsu dari Pool 2, sedangkan rentang `.36–.69` tidak pernah dialokasikan.

## 7. Pemulihan setelah restart

Jika MAC klien berubah, cocokkan ulang dengan class di `dhcpd.conf` tengen:

```bash
ip link show eth0 | grep ether                       # di klien
grep -n "substring(hardware" /etc/dhcp/dhcpd.conf    # di tengen
```

Perbarui MAC yang berbeda pada `./setup-tengen.sh`, lalu jalankan ulang script.

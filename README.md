# Jarkom-Modul-3-2026-K-56

| No  | Nama                           | NRP        | Pengerjaan |
| --- | ------------------------------ | ---------- | ---------- |
| 1   | Sahira Bilqis Rivadito         | 5027251037 | No 1-10    |
| 2   | Muhammmad Ridwan               | 5027251113 | No 11-20   |

## LAPORAN RESMI MODUL 3

# Soal 1 – Konektivitas Dasar (jichi sebagai Router)

Kelompok: K56 | Prefix IP: `192.239`

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

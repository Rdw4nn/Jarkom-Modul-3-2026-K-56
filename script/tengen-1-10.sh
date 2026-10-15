#!/bin/bash
# /root/setup-tengen.sh  (Soal 2: DHCP Server)

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
    option broadcast-address 192.239.2.255;
    option domain-name-servers 192.239.1.2, 192.239.1.3;
    option domain-search "k56.com";
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

# Network 3 (Divisi B)
class "short" {
    match if (substring(hardware, 1, 6) = 02:42:a6:c1:7d:00)
          or (substring(hardware, 1, 6) = 02:42:55:d0:dc:00);
    default-lease-time 1800;
    max-lease-time 1800;
}

class "long" {
    match if (substring(hardware, 1, 6) = 02:42:14:04:b7:00);
    default-lease-time 43200;
    max-lease-time 43200;
}

subnet 192.239.3.0 netmask 255.255.255.0 {
    option routers 192.239.3.1;
    option broadcast-address 192.239.3.255;
    option subnet-mask 255.255.255.0;
    option domain-name-servers 192.239.1.2, 192.239.1.3;
    option domain-search "k56.com";

    pool {
        allow members of "short";
        range 192.239.3.10 192.239.3.89;
    }

    pool {
        allow members of "long";
        range 192.239.3.100 192.239.3.199;
    }
}

host kugisaki {
    hardware ethernet 02:42:5c:a9:44:00;
    fixed-address 192.239.3.99;
}

EOF

dhcpd -t -cf /etc/dhcp/dhcpd.conf && service isc-dhcp-server restart
service isc-dhcp-server status

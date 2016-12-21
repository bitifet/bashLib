#!/usr/bin/env bash

# Parameters:
# ===========
domain="${1}"
ipRange="${2}"
interactive=""

# Defaults:
# =========
defDomain="mydomain.local"
defIpRange="192.168.1"

if [ -z "${domain}" ]; then
    interactive="true"
    read -p "Domain (Default=${defDomain}): " domain
    domain="${domain:=${defDomain}}"
fi;

if [ -z "${ipRange}" ]; then
    interactive="true"
    read -p "IP Range (Default=${defIpRange}): " ipRange
    ipRange="${ipRange:=${defIpRange}}"
fi;

# Calculations:
# =============
revIP=$(printf "%s\n" ${ipRange//\./ }|tac|xargs)
revIP=${revIP// /.}

nsIP=$(/sbin/ifconfig | grep "inet addr:${ipRange}" | head -n 1)
nsIP=${nsIP/* inet addr:${ipRange}./}
nsIP=${nsIP/ */}

nsName=$(/bin/hostname)


echo "================================================";
echo "Writting basic bind configuration:";
echo "------------------------------------------------";
echo "Domain: ${domain}";
echo "IP Range: ${ipRange} (NS=${nsIP})";
echo "================================================";

if [ -z "${nsIP}" ]; then 
    >&2 echo "Error trying to determine local IP in given range."
    exit 1;
fi;



# Setup:
# ======
echo "Software setup..."
sudo apt-get install -y bind9 # bind9-doc

echo "Log directory setup...."
sudo mkdir /var/log/named
sudo chown bind:bind /var/log/named
sudo chmod 755 /var/log/named



echo "Configuring logging policies..."
sudo tee /etc/bind/named.conf.log >/dev/null <<!EOF

logging {
        channel update_debug {
                file "/var/log/named/update_debug.log" versions 3 size 100k;
                severity debug;
                print-severity  yes;
                print-time      yes;
        };
        channel security_info {
                file "/var/log/named/security_info.log" versions 1 size 100k;
                severity info;
                print-severity  yes;
                print-time      yes;
        };
        channel bind_log {
                file "/var/log/named/bind.log" versions 3 size 1m;
                severity info;
                print-category  yes;
                print-severity  yes;
                print-time      yes;
        };

        category default { bind_log; };
        category lame-servers { null; };
        category update { update_debug; };
        category update-security { update_debug; };
        category security { security_info; };
};
!EOF


echo "Configuring domain zones..."
sudo tee /etc/bind/named.conf.local >/dev/null <<!EOF

// Manage the file logs:
include "/etc/bind/named.conf.log";

// Domain Management ${domain}
// ---------------------------------------------------
//  - The server is defined as the master on the domain.
//  - There are no forwarders for this domain.
zone "${domain}" {
        type master;
        file "/var/cache/bind/db.${domain}";
};
zone "${revIP}.in-addr.arpa" {
        type master;
        file "/var/cache/bind/db.${domain}.inv";
};

// RFC1918 zones:
include "/etc/bind/zones.rfc1918";

!EOF


echo "Initializing direct resolution DB..."
sudo tee /var/cache/bind/db.${domain} >/dev/null <<!EOF

\$TTL    3600
@       IN      SOA     ${nsName}.${domain}. root.${domain}. (
                   2007010401           ; Serial
                         3600           ; Refresh [1h]
                          600           ; Retry   [10m]
                        86400           ; Expire  [1d]
                          600 )         ; Negative Cache TTL [1h]
;
@       IN      NS      ${nsName}.${domain}.
@       IN      MX      10 ${nsName}.${domain}.

${nsName}     IN      A       ${ipRange}.${nsIP}

; More hosts:
;<hostName>    IN      A       ${ipRange}.<ip>
;...

; CNAMES:
;www     IN      CNAME   ${nsName}
;mail    IN      CNAME   ${nsName}
;pop     IN      CNAME   ${nsName}
;smtp    IN      CNAME   ${nsName}


!EOF




echo "Initializing inverse resolution DB..."
sudo tee /var/cache/bind/db.${domain}.inv >/dev/null <<!EOF

@ IN SOA        ${nsName}.${domain}. root.${domain}. (
                   2007010401           ; Serial
                         3600           ; Refresh [1h]
                          600           ; Retry   [10m]
                        86400           ; Expire  [1d]
                          600 )         ; Negative Cache TTL [1h]
;
@       IN      NS      ${nsName}.${domain}.

${nsIP}       IN      PTR     ${nsName}.${domain}.
;<ipNum>       IN      PTR     <hostName>.${domain}.
;...


!EOF





echo "Overwritting resolv.conf"
sudo tee /etc/resolv.conf >/dev/null <<!EOF
nameserver ${nsName}.${domain}
search ${domain}
!EOF

if [ -n "${interactive}" ]; then
    read -p "Press ENTER to edit direct resolution DB"
    vim "/var/cache/bind/db.${domain}";
    read -p "Press ENTER to edit inverse resolution DB"
    vim "/var/cache/bind/db.${domain}.inv";
fi;


echo "Restarting server..."
sudo /etc/init.d/bind9 restart



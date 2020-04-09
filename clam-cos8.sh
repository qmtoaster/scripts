#!/bin/bash

qmailctl stop
systemctl stop clamav-daemon clamav-socket

rpm -ev --nodeps clamav

yum --disablerepo=qmt-current \
    --disablerepo=qmt-testing \
    --disablerepo=qmt-devel \
    install clamav clamav-update clamd -y

curl -o /usr/lib/systemd/system/clamd@scan.service  https://raw.githubusercontent.com/qmtoaster/scripts/master/clamd@scan.service
curl -o /etc/clamd.d/scan.conf https://raw.githubusercontent.com/qmtoaster/scripts/master/scan.conf

chown clamscan:root /var/qmail/simscan
chown clamscan:root /var/qmail/bin/simscan
chmod 0750 /var/qmail/simscan
chmod 4711 /var/qmail/bin/simscan
mkdir /var/log/clamd
chown -R clamscan:clamscan /var/log/clamd

freshclam
systemctl start clamav-freshclam clamd@scan
systemctl enable clamav-freshclam clamd@scan

qmailctl start
qmailctl cdb

sed -i 's/CLAMS=clamav-daemon.socket//' /usr/bin/toaststat
sed -i 's/$CLAMS//' /usr/bin/toaststat
sed -i 's/CLAMD=clamav-daemon.service/CLAMD=clamd@scan.service/' /usr/bin/toaststat

toaststat

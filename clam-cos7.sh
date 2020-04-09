#!/bin/bash

qmailctl stop
systemctl stop clamav-daemon.socket clamav-daemon.service freshclam

rpm -ev --nodeps clamav

yum --disablerepo=qmt-current \
    --disablerepo=qmt-testing \
    --disablerepo=qmt-devel \
    install clamav clamav-update clamd -y
    
curl -o /etc/clamd.d/scan.conf https://raw.githubusercontent.com/qmtoaster/scripts/master/scan.conf    

chown clamscan:root /var/qmail/simscan
chown clamscan:root /var/qmail/bin/simscan
chmod 0750 /var/qmail/simscan
chmod 4711 /var/qmail/bin/simscan
mkdir /var/log/clamd
chown -R clamscan:clamscan /var/log/clamd

systemctl start clamd@scan clamav-freshclam
systemctl enable clamd@scan clamav-freshclam

qmailctl start
qmailctl cdb

wget -O /usr/bin/toaststat.cos7.new https://raw.githubusercontent.com/qmtoaster/scripts/master/toaststat

toaststat

#!/bin/bash

systemctl stop clamav-daemon.socket clamav-daemon.service

rpm -ev --nodeps clamav

yum --disablerepo=qmt-current \
    --disablerepo=qmt-testing \
    --disablerepo=qmt-devel \
    install patch clamav clamav-update clamd -y

printf '%s\n' \
'# Run the freshclam as daemon' \
'[Unit]' \
'Description = freshclam scanner' \
'After = network.target' \
'' \
'[Service]' \
'Type = forking' \
'ExecStart = /usr/bin/freshclam -d -c 4' \
'Restart = on-failure' \
'PrivateTmp = true' \
'' \
'[Install]' \
'WantedBy=multi-user.target' \
> /usr/lib/systemd/system/clamav-freshclam.service

chown clamscan:root /var/qmail/simscan
chown clamscan:root /var/qmail/bin/simscan
chmod 0750 /var/qmail/simscan
chmod 4711 /var/qmail/bin/simscan
mkdir /var/log/clamd
chown -R clamscan:clamscan /var/log/clamd

wget http://www.qmailtoaster.org/clamd.conf.diff

patch /etc/clamd.d/scan.conf clamd.conf.diff

systemctl start clamd@scan freshclam
systemctl enable clamd@scan freshclam

sed -i 's/CLAMD=/CLAMD=clamd@scan/' /usr/bin/toaststat

toaststat

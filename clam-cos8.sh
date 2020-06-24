#!/bin/bash

qmailctl stop
systemctl stop clamav-daemon.socket clamav-daemon.service clamav-freshclam

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
[ ! -d /var/log/clamd ] && mkdir /var/log/clamd
[ ! -d /var/log/clamav ] && mkdir /var/log/clamav
chown -R clamscan:clamscan /var/log/clamd
chown -R clamupdate:clamupdate /var/log/clamav
chown -R clamupdate:clamupdate /var/lib/clamav
sed -i 's/#UpdateLogFile \/var\/log\/freshclam.log/UpdateLogFile \/var\/log\/clamav\/freshclam.log/g; s/#LogFileMaxSize/LogFileMaxSize/g; s/#LogTime/LogTime/g; s/#LogVerbose/LogVerbose/g; s/#LogRotate/LogRotate/g' /etc/freshclam.conf

freshclam
systemctl start clamav-freshclam clamd@scan
systemctl enable clamav-freshclam clamd@scan

qmailctl start
qmailctl cdb

sed -i 's/CLAMS=clamav-daemon.socket//' /usr/bin/toaststat
sed -i 's/$CLAMS//' /usr/bin/toaststat
sed -i 's/CLAMD=clamav-daemon.service/CLAMD=clamd@scan.service/' /usr/bin/toaststat

toaststat

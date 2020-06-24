#!/bin/bash

qmailctl stop
systemctl stop clamav-daemon.socket clamav-daemon.service clamav-freshclam

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
[ ! -d /var/log/clamd ] && mkdir /var/log/clamd
[ ! -d /var/log/clamav ] && mkdir /var/log/clamav
chown -R clamscan:clamscan /var/log/clamd
chown -R clamupdate:clamupdate /var/log/clamav
chown -R clamupdate:clamupdate /var/lib/clamav
sed -i 's/#UpdateLogFile \/var\/log\/freshclam.log/UpdateLogFile \/var\/log\/clamav\/freshclam.log/g; s/#LogFileMaxSize/LogFileMaxSize/g; s/#LogTime/LogTime/g; s/#LogVerbose/LogVerbose/g; s/#LogRotate/LogRotate/g' /etc/freshclam.conf


freshclam
systemctl start clamd@scan clamav-freshclam
systemctl enable clamd@scan clamav-freshclam



qmailctl start
qmailctl cdb

wget -O /usr/bin/toaststat  https://raw.githubusercontent.com/qmtoaster/scripts/master/toaststat.cos7.new

toaststat

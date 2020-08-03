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
systemctl enable --now   clamd@scan clamav-freshclam

mount | grep "/var/qmail/simscan"
if [ $? = 0 ]
then
   tempid=`id -u clamscan`
   umount /var/qmail/simscan
   chown clamscan:root /var/qmail/simscan
   chown clamscan:root /var/qmail/bin/simscan
   chmod 0750 /var/qmail/simscan
   mount -t tmpfs -o size=1024m,nodev,noexec,noatime,uid=$tempid,gid=0,mode=0750 myramdisk /var/qmail/simscan
   tempno=`cat /etc/fstab  | grep -n /var/qmail/simscan | cut -d: -f1`
   re='^[0-9]+$'
   if [[ $tempno =~ $re ]]
   then
      read -p "You have simscan ramdisk entry in /etc/fstab, Do you want to change clamav to clamscan uid now? [y/N] : " doit
      doit=${doit^^}
      if [ "$doit" = "Y" ]
      then
         cp -p /etc/fstab /etc/fstab.bak
         [ "$?" = "0" ] && echo "/etc/fstab backed up to /etc/fstab.bak"
         sed -i "${tempno}s/uid=46/uid=$tempid/" /etc/fstab
      fi
   fi
fi

qmailctl start
qmailctl cdb

sed -i 's/CLAMS=clamav-daemon.socket//' /usr/bin/toaststat
sed -i 's/$CLAMS//' /usr/bin/toaststat
sed -i 's/CLAMD=clamav-daemon.service/CLAMD=clamd@scan.service/' /usr/bin/toaststat

toaststat

#!/bin/bash

qmailctl stop
systemctl disable clamav-daemon.socket clamav-daemon.service clamav-freshclam
systemctl stop clamav-daemon.socket clamav-daemon.service clamav-freshclam
systemctl stop spamd

rpm -ev --nodeps clamav
rpm -ev --nodeps spamassassin

yum install clamav clamav-update clamd spamassassin -y
    
chown clamscan:root /var/qmail/simscan
chown clamscan:root /var/qmail/bin/simscan
chmod 0750 /var/qmail/simscan
chmod 4711 /var/qmail/bin/simscan
chown -R clamupdate:clamupdate /var/lib/clamav

sed -i 's/^#LocalSocket /LocalSocket /'  /etc/clamd.d/scan.conf

freshclam
systemctl enable --now   clamd@scan clamav-freshclam spamassassin

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

wget -O /usr/bin/toaststat  https://raw.githubusercontent.com/qmtoaster/scripts/master/toaststat.cos7

toaststat

#!/bin/sh

TAB="$(printf '\t')"
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
NORMAL=$(tput sgr0)

begin=`date`

# CentOS 7 QMT install script

# Remove stock SMTP server installation
yum -y remove postfix

# Install secondary repos (epel)
yum -y install epel-release 
yum -y install yum-plugin-priorities

echo ""
printf $RED
printf "%s\n" "*********************************************************************************************************************************************"
printf $GREEN
printf "%s\n" "Be patient with the ClamAV RPM install and DB download, mirror speeds may be slow. At peak times a 30 minute wait is not out of the question."
printf $RED
printf "%s\n" "*********************************************************************************************************************************************"
printf  $NORMAL
echo ""
sleep 7

rpm -Uvh ftp://ftp.whitehorsetc.com/pub/repo/qmt/CentOS/7/current/noarch/whtc-qmt-1-1.qt.el7.noarch.rpm 
yum clean all
yum groupinstall WHTC-QMT

# Set up the db server
systemctl start mariadb.service
systemctl enable mariadb.service
read -p "Secure the MariaDB installation [Y/N]: " yesno
if [ "$yesno" = "Y" ] || [ "$yesno" = "y" ]; then
   mysql_secure_installation
fi

# MySQL vpopmail setup
read -s -p "Enter DB admin password to set up vpopmail: " password
if [ -z "$password" ]; then
   echo "Empty password, exiting..."
   exit 1
fi
MYSQLPW=$password
echo ""

# Check the password
mysqladmin status -uroot -p$MYSQLPW > /dev/null 2>&1
if [ "$?" != "0" ]; then
   echo "Bad MariaDB administrator password. Exiting..."
   exit 1
fi
# Install vpopmail
read -p "If there is a vpopmail database, you are about to destroy it and create a new one. Proceed? [Y/N]:" yesno
if [ "$yesno" = "Y" ] || [ "$yesno" = "y" ]; then
   mysqladmin drop vpopmail -uroot -p$MYSQLPW
   mysqladmin create vpopmail -uroot -p$MYSQLPW
   mysqladmin -uroot -p$MYSQLPW reload
   mysqladmin -uroot -p$MYSQLPW refresh
   echo "GRANT ALL PRIVILEGES ON vpopmail.* TO vpopmail@localhost IDENTIFIED BY 'SsEeCcRrEeTt'" | mysql -uroot -p$MYSQLPW
   mysqladmin -uroot -p$MYSQLPW reload
   mysqladmin -uroot -p$MYSQLPW refresh
fi

# Open ports on firewall
systemctl start firewalld
systemctl enable firewalld
ports=(20 21 22 25 53 80 110 113 143 443 465 587 993 995 3306)
for index in ${!ports[*]}
do
   echo -n "Opening port: ${ports[$index]} : "
   tput setaf 2
   firewall-cmd --zone=public --add-port=${ports[$index]}/tcp --permanent
   tput sgr0
done
echo -n "Reload firewall settings : "
tput setaf 2
firewall-cmd --reload
tput sgr0

# Start and display status of qmail
qmailctl stop &> /dev/null
qmailctl start
qmailctl stat

# Start systemd services
chown root.clamav /run/clamav
chmod 775 /run/clamav
CLAMS=clamav-daemon.socket
CLAMD=clamav-daemon.service
sv=($CLAMS $CLAMD spamd dovecot httpd named vsftpd network acpid atd autofs crond ntpd smartd sshd irqbalance)
for idx in ${!sv[*]}
do
   temp=${sv[$idx]}
   systemctl enable $temp  > /dev/null 2>&1
   ret0=$?
   systemctl start $temp  > /dev/null 2>&1
   ret1=$?
   if [ "$ret0" = 0 ] && [ "$ret1" = 0 ]; then
       printf "%s %11.11s %s %s %s %s %s %s\n" "Systemd service" "$temp:" "${TAB}" "[" "$GREEN" "OK" "$NORMAL" "]"
   else
       printf "%s %11.11s %s %s %s %s %s %s\n" "Systemd service" "$temp:" "${TAB}" "[" "$RED" "FAILED" "$NORMAL" "]"
   fi
done

# Isoqlog 
sh /usr/share/toaster/isoqlog/bin/cron.sh
# If this command is not run lo interface will not come up on boot
# https://bugs.centos.org/view.php?id=7351
systemctl enable NetworkManager-wait-online.service
# If this command is not run the ntpd service will not start
systemctl disable chronyd.service
# Script to determine all of the necessary toaster daemons
wget -O /usr/bin/toaststat  ftp://ftp.whitehorsetc.com/pub/qmail/CentOS7/qmt/scripts/toaststat
chmod 755 /usr/bin/toaststat

# Install Unison
read -p "Install Unison [Y/N] : " yesno
if [ "$yesno" = "Y" ] || [ "$yesno" = "y" ]; then
   rpm -Uvh \
   ftp://ftp.whitehorsetc.com/pub/qmail/CentOS7/unison/unison-2.40.63-1.el7.rf.x86_64.rpm \
   ftp://ftp.whitehorsetc.com/pub/qmail/CentOS7/unison/unison-debuginfo-2.40.63-1.el7.rf.x86_64.rpm
fi

# Enter domain
read -p "Enter a domain? [Y/N] : " yesno
if [ "$yesno" = "Y" ] || [ "$yesno" = "y" ]; then
   /home/vpopmail/bin/vadddomain
   read -p "Enter domain: " newdom
   read -s -p "Enter postmaster@$newdom password: " newpass
   echo ""
   if [ -z "$newdom" ] || [ -z "$newpass" ]; then
      echo "Empty username or password."
   else
      /home/vpopmail/bin/vadddomain $newdom $newpass
   fi
fi

# Install Dspam
read -p "Install dspam [Y/N] : " yesno
if [ "$yesno" = "Y" ] || [ "$yesno" = "y" ]; then
   wget ftp://ftp.whitehorsetc.com/pub/dspam/scripts/dspam-install.sh
   if [ "$?" = "1" ]; then
      echo "Error downloading dspam installer, exiting..."
      exit 1
   fi
   chmod 755 dspam-install.sh
   ./dspam-install.sh
   if [ "$?" != 0 ]; then
      echo "Error installing dspam"
   fi
fi
echo "CentOS 7 QMT installation complete"
end=`date`
echo "Start: $begin"
echo "  End: $end"
exit 0

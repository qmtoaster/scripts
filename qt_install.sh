#!/bin/sh
#
#   Script: qt_install.sh
# Function: This script was written to install Qmailtoaster on CentOS 7 host.
#
#   Author: Eric C. Broch
#
#      Use: ./qt_install.sh
#
#  Warning: This script is not bullet-proof, use at your own risk.
#
#  Failure: Re-run
#
#  Updates:
#  
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
wget https://github.com/qmtoaster/release/raw/master/qmt-release-1-4.qt.el7.noarch.rpm
rpm -Uvh qmt-release-1-4.qt.el7.noarch.rpm

# Install QMT dependencies and accessories
yum -y install rsync bind-utils bind net-tools zlib-devel mariadb-server mariadb mariadb-devel libev-devel httpd php mrtg expect libidn-devel aspell tmpwatch perl-Time-HiRes \
perl-ExtUtils-MakeMaker perl-Archive-Tar perl-Digest-SHA perl-HTML-Parser perl-IO-Zlib perl-Net-DNS perl-NetAddr-IP perl-Crypt-OpenSSL-Bignum \
perl-Digest-SHA1 perl-Encode-Detect perl-Geo-IP perl-IO-Socket-SSL perl-Mail-DKIM  perl-Razor-Agent perl-Sys-Syslog perl-Net-CIDR-Lite perl-DB_File \
bzip2-devel check-devel curl-devel gmp-devel ncurses-devel libxml2-devel python-devel sqlite-devel postgresql-devel openldap-devel quota-devel libcap-devel \
pam-devel clucene-core-devel expat-devel emacs ocaml procmail wget logwatch vsftpd acpid acpid-sysvinit at autofs ntp smartmontools mod_ssl fail2ban perl-Sys-Hostname-Long \
perl-Mail-DomainKeys perl-Mail-SPF-Query nfs-utils bzip2


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

# Check the password
mysqladmin status -uroot -p$MYSQLPW &> /dev/null
if [ "$?" != "0" ]; then
   echo "Bad MariaDB administrator password. Exiting..."
   exit 1
fi

echo ""
# Install vpopmail
echo "use vpopmail" | mysql -uroot -p$MYSQLPW &> /dev/null
[ "$?" = "0" ] && mysqldump -uroot -p$MYSQLPW vpopmail > vpopmail.sql \
               && echo "drop database vpopmail" | mysql -u root -p$MYSQLPW \
               && echo "vpopmail db saved to vpopmail.sql and dropped..."

mysqladmin create vpopmail -uroot -p$MYSQLPW
[ "$?" != "0" ] && echo "vpopmail db not created or already exists" && exit 1
echo "vpopmail db created"
mysqladmin -uroot -p$MYSQLPW reload
mysqladmin -uroot -p$MYSQLPW refresh
echo "GRANT ALL PRIVILEGES ON vpopmail.* TO vpopmail@localhost IDENTIFIED BY 'SsEeCcRrEeTt'" | mysql -uroot -p$MYSQLPW
mysqladmin -uroot -p$MYSQLPW reload
mysqladmin -uroot -p$MYSQLPW refresh

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

# Install QMT
yum -y install daemontools ucspi-tcp libsrs2 libsrs2-devel vpopmail spamdyke qmail autorespond control-panel ezmlm ezmlm-cgi qmailadmin qmailmrtg maildrop \
maildrop-devel isoqlog vqadmin squirrelmail spamassassin clamav ripmime simscan mailman mailman-debuginfo dovecot libdomainkeys-devel qmt-plus

# Open ports on firewall
systemctl start firewalld
systemctl enable firewalld
ports=(20 21 22 25 80 110 113 143 443 465 587 993 995 3306)
for index in ${!ports[*]}
do
   echo -n "Opening port: ${ports[$index]} : "
   tput setaf 2
   firewall-cmd --zone=public --add-port=${ports[$index]}/tcp --permanent
   tput sgr0
done
firewall-cmd --zone=public --add-port=53/udp --permanent
echo -n "Reload firewall settings : "
tput setaf 2
firewall-cmd --reload
tput sgr0

# Start qmail
qmailctl stop &> /dev/null
qmailctl start &> /dev/null 

# Stop freshclam under SysV
chkconfig freshclam off &> /dev/null
service freshclam stop &> /dev/null

# Start systemd services
chown root.clamav /run/clamav
chmod 775 /run/clamav
CLAMS=clamav-daemon.socket
CLAMD=clamav-daemon.service
sv=($CLAMS $CLAMD clamav-freshclam spamd dovecot httpd named vsftpd network acpid atd autofs crond ntpd smartd sshd irqbalance)
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
wget -O /usr/bin/toaststat https://raw.githubusercontent.com/qmtoaster/scripts/master/toaststat
if [ "$?" = "0" ]; then
   chmod 755 /usr/bin/toaststat
   toaststat
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
   wget https://raw.githubusercontent.com/qmtoaster/dspam/master/dspamdb.sh
   if [ "$?" != "0" ]; then
      echo "Error downloading dspam installer, exiting..."
      exit 1
   fi
   chmod 755 dspamdb.sh
   ./dspamdb.sh
   if [ "$?" != 0 ]; then
      echo "Error installing dspam"
   fi
fi
echo "CentOS 7 QMT installation complete"
end=`date`
echo "Start: $begin"
echo "  End: $end"
exit 0

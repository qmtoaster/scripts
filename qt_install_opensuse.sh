#!/bin/bash

begin=`date`

# Open necessary firewall ports
TAB="$(printf '\t')" && GREEN=$(tput setaf 2) && RED=$(tput setaf 1) && NORMAL=$(tput sgr0) && \
  systemctl start firewalld && systemctl enable firewalld && \
  ports=(20 21 22 25 80 89 110 113 143 443 465 587 993 995 3306) && \
  for index in ${!ports[*]}; do echo -n "Opening port: ${ports[$index]} : ";tput setaf 2;firewall-cmd --zone=public --add-port=${ports[$index]}/tcp --permanent;tput sgr0; done && \
  firewall-cmd --zone=public --add-port=53/udp --permanent && \
  echo -n "Reload firewall settings : " && tput setaf 2 && firewall-cmd --reload && tput sgr0
  
# Disable Apparmor
printf $RED
echo "Disabling Apparmor..."
printf $NORMAL
systemctl stop apparmor &> /dev/null
systemctl disable apparmor &> /dev/null
printf $RED
echo "Apparmor has been disabled. If connection to the Dovecot IMAP server fails, reboot is necessary."
printf $NORMAL

printf $RED
echo "Installing necessary packages..."
printf $NORMAL
zypper update -y
zypper install -y logwatch bind bind-utils telnet yum-utils chrony acpid at autofs bzip2 \
       smartmontools wget vsftpd fail2ban roundcubemail php-mysql net-tools-deprecated \
       mariadb

# Set up MariaDB Server
printf $RED
echo "MariaDB setup started..."
printf $NORMAL
read -s -p "Enter MariaDB Server password: " password
if [ -z "$password" ]; then
   echo "Empty password, exiting..."
   exit 1
fi
echo -e "\n"
MYSQLPW=$password
credfile=~/sql.cnf
echo -e "[client]\nuser=root\npassword='$MYSQLPW'\nhost=localhost" > $credfile
echo "Starting MariaDB Server..."
systemctl enable --now mariadb && systemctl status mariadb
echo "Started MariaDB Server"
sleep 2
echo "Setting MariaDB admin password..."
mysqladmin -uroot password $MYSQLPW &> /dev/null
printf $RED
echo "MariaDB setup completed..."
printf $NORMAL

printf $RED
echo "Creating Vpopmail DB..."
printf $NORMAL
mysqladmin --defaults-extra-file=$credfile reload
mysqladmin --defaults-extra-file=$credfile refresh
mysqladmin --defaults-extra-file=$credfile create vpopmail
mysqladmin --defaults-extra-file=$credfile reload
mysqladmin --defaults-extra-file=$credfile refresh
echo "Adding vpopmail users and privileges..."
mysql --defaults-extra-file=$credfile -e "CREATE USER vpopmail@localhost IDENTIFIED BY 'SsEeCcRrEeTt'"
mysql --defaults-extra-file=$credfile -e "GRANT ALL PRIVILEGES ON vpopmail.* TO vpopmail@localhost"
mysqladmin --defaults-extra-file=$credfile reload
mysqladmin --defaults-extra-file=$credfile refresh
printf $RED
echo "Created Vpopmail DB..."
printf $NORMAL

# Add roundcube support
printf $RED
echo "Create Roundcube DB..."
printf $NORMAL
mysql --defaults-extra-file=$credfile -e "create database roundcube character set utf8 collate utf8_bin"
mysql --defaults-extra-file=$credfile -e "CREATE USER roundcube@localhost IDENTIFIED BY 'p4ssw3rd'"
mysql --defaults-extra-file=$credfile -e "GRANT ALL PRIVILEGES ON roundcube.* TO roundcube@localhost"
mysql --defaults-extra-file=$credfile roundcube < /usr/share/doc/packages/roundcubemail/SQL/mysql.initial.sql
wget -O /etc/roundcubemail/config.inc.php http://www.qmailtoaster.org/rc.default.config
sed -i 's/^date.timezone.*/date.timezone = "America\/Denver"/' /etc/php7/apache2/php.ini
printf $RED
echo "Created Roundcube DB..."
printf $NORMAL

# Get QMT/OpenSUSE repo
printf $RED
echo "Install Mail Server..."
printf $NORMAL
curl -o  /etc/zypp/repos.d/qmt.repo  https://raw.githubusercontent.com/qmtoaster/mirrorlist/master/qmt-opensuse152.repo
zypper install -y simscan clamav daemontools ucspi-tcp libsrs2 libsrs2-devel \
                  vpopmail spamdyke qmail autorespond control-panel ezmlm \
                  ezmlm-cgi qmailadmin qmailmrtg maildrop maildrop-devel \
                  isoqlog vqadmin squirrelmail ripmime dovecot spamassassin
printf $RED
echo "Installed Mail Server..."
printf $NORMAL         
               

printf $RED
echo "Adjust mail server settings..."
printf $NORMAL
mv /etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext.bak &> /dev/null
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/local.conf
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot-sql.conf.ext
systemctl relaod dovecot &> /dev/null

# Enable man pages
echo "MANDATORY_MANPATH /var/qmail/man" >> /etc/manpath.config

# Smart Daemon
sed -i 's/smartd_opts=""/smartd_opts="-q never"/' /var/lib/smartmontools/smartd_opts
sed -i 's/ConditionVirtualization=false/#ConditionVirtualization=false/' /usr/lib/systemd/system/smartd.service
sed -i 's/DirectoryIndex/DirectoryIndex index.php/' /etc/apache2/httpd.conf

# Add access to QMT administration from desired network or hosts && enable OpenSUSE SSL
sed -i 's|APACHE_SERVER_FLAGS=""|APACHE_SERVER_FLAGS="SSL"|' /etc/sysconfig/apache2
sed -i 's|APACHE_MODULES="|APACHE_MODULES="mod_php7 |' /etc/sysconfig/apache2
sed -i 's|SSLCertificateFile.*|SSLCertificateFile /var/qmail/control/servercert.pem|g' /etc/apache2/vhosts.d/vhost-ssl.template
sed -i 's|SSLCertificateKeyFile.*|SSLCertificateKeyFile /var/qmail/control/servercert.pem|g' /etc/apache2/vhosts.d/vhost-ssl.template
mv /etc/apache2/vhosts.d/vhost-ssl.template /etc/apache2/vhosts.d/vhost-ssl.conf
 
printf $RED
echo "Downloading ClamAV database..."
printf $NORMAL
freshclam
printf $RED
echo "Starting QMT..."
printf $NORMAL
qmailctl start
printf $RED
echo "Starting clamd freshclam dovecot spamassassin httpd chronyd acpid atd autofs smartd named, this may take a while..."
printf $NORMAL
systemctl enable --now clamd spamd dovecot apache2 named chronyd cron vsftpd acpid atd autofs smartd

wget -O /usr/bin/toaststat https://raw.githubusercontent.com/qmtoaster/scripts/master/toaststat.opensuse
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
      sh /usr/share/toaster/isoqlog/bin/cron.sh
   fi
fi

# Connection test script, tests IMAPS, SMTPS, Submission.
wget https://raw.githubusercontent.com/qmtoaster/scripts/master/conntest && chmod 755 conntest && ./conntest

# All squirrelamail access to user preferences file and directories
# chown wwwrun:www /var/lib/squirrelmail/prefs
# chmod 755 /var/lib/squirrelmail/prefs
# mkdir /usr/share/squirrelmail/data 
# mv /var/lib/squirrelmail/prefs/default_pref /usr/share/squirrelmail/data
# chmod 644 /usr/share/squirrelmail/data/default_pref

# Left to do OpenSUSE
# 1) Find a way to set cryptograhic policies to legacy on OpenSUSE
#update-crypto-policies --set LEGACY

echo "OpenSUSE Leap QMT installation complete"
end=`date`
echo "Start: $begin"
echo "  End: $end"
exit 0

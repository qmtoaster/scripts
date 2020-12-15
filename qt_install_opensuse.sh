#!/bin/bash

begin=`date`

# Open necessary firewall port, and disable selinux
TAB="$(printf '\t')" && GREEN=$(tput setaf 2) && RED=$(tput setaf 1) && NORMAL=$(tput sgr0) && \
  systemctl start firewalld && systemctl enable firewalld && \
  ports=(20 21 22 25 80 89 110 113 143 443 465 587 993 995 3306) && \
  for index in ${!ports[*]}; do echo -n "Opening port: ${ports[$index]} : ";tput setaf 2;firewall-cmd --zone=public --add-port=${ports[$index]}/tcp --permanent;tput sgr0; done && \
  firewall-cmd --zone=public --add-port=53/udp --permanent && \
  echo -n "Reload firewall settings : " && tput setaf 2 && firewall-cmd --reload && tput sgr0

zypper update -y
zypper install -y logwatch bind bind-utils telnet yum-utils chrony acpid at autofs bzip2 \
       smartmontools wget vsftpd fail2ban roundcubemail php-mysql

# MySQL admin password
read -s -p "Enter $DBD password: " password
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
echo "Admin password set"
echo "Creating vpopmail database..."
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
echo "Done with vpopmail database..."

# Install mail server
zypper --no-gpg-checks install -y simscan clamav  daemontools ucspi-tcp \
               libsrs2 libsrs2-devel vpopmail spamdyke qmail autorespond \
               control-panel ezmlm ezmlm-cgi qmailadmin qmailmrtg maildrop \
               maildrop-devel isoqlog vqadmin squirrelmail ripmime dovecot \
               spamassassin

[ -f /etc/dovecot/dovecot.conf ] && mv /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.bak
[ -f /etc/dovecot/dovecot-sql.conf.ext ] && mv /etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext.bak
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot.conf
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot-sql.conf.ext
sed -i 's/log_path/#log_path/' /etc/dovecot/dovecot.conf
systemctl relaod dovecot &> /dev/null

# Enable man pages
echo "Enable QMT man pages..."
echo "MANDATORY_MANPATH /var/qmail/man" >> /etc/manpath.config
cp /var/qmail/control/servercert.pem /etc/ssl/private

sed -i 's/smartd_opts=""/smartd_opts="-q never"/' /var/lib/smartmontools/smartd_opts
sed -i 's/ConditionVirtualization=false/#ConditionVirtualization=false/' /usr/lib/systemd/system/smartd.service


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

#**** More to do here ****

echo "OpenSUSE Leap QMT installation complete"
end=`date`
echo "Start: $begin"
echo "  End: $end"
exit 0

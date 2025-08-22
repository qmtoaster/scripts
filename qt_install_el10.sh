#!/bin/bash

begin=`date`

cat > /etc/yum.repos.d/fedora41.repo << EOF
[fedora41]
name=Fedora 41 RPM - x86_64
baseurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/41/Everything/\$basearch/os/
enabled=0
gpgcheck=0
priority=100
[fedora41-source]
name=Fedora 41 SRPM - x86_64 Source
baseurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/41/Everything/source/tree/
enabled=0
gpgcheck=0
priority=100
EOF

# Open necessary firewall port, and disable selinux
TAB="$(printf '\t')" && GREEN=$(tput setaf 2) && RED=$(tput setaf 1) && NORMAL=$(tput sgr0) && \
  systemctl start firewalld && systemctl enable firewalld && \
  ports=(20 21 22 25 80 89 110 113 143 443 465 587 993 995 3306) && \
  for index in ${!ports[*]}; do echo -n "Opening port: ${ports[$index]} : ";tput setaf 2;firewall-cmd --zone=public --add-port=${ports[$index]}/tcp --permanent;tput sgr0; done && \
  firewall-cmd --zone=public --add-port=53/udp --permanent && \
  echo -n "Reload firewall settings : " && tput setaf 2 && firewall-cmd --reload && tput sgr0
setenforce 0 && sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config && getenforce

# Update minimal
dnf -y update
dnf -y install dnf-utils epel-release
dnf -y install logwatch bind bind-utils telnet yum-utils chrony acpid at autofs bzip2 net-tools \
               smartmontools wget vsftpd mod_ssl fail2ban roundcubemail php-mysqlnd chkconfig rsyslog

yum-config-manager --enable crb
dnf -y install mysql8.4 mysql8.4-server mysql8.4-common mysql8.4-libs

# MySQL admin password
read -s -p "Enter mysql password: " password
if [ -z "$password" ]; then
   echo "Empty password, exiting..."
   exit 1
fi

echo -e "\n"
MYSQLPW=$password
credfile=~/sql.cnf
echo -e "[client]\nuser=root\npassword='$MYSQLPW'\nhost=localhost" > $credfile
echo "Starting mysql Server..."
systemctl start mysqld && systemctl enable mysqld && systemctl status mysqld
echo "Started mysql Server"
sleep 2
echo "Setting mysql admin password..."
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

echo "Dropping Dspam database if it exists already..."
mysql --defaults-extra-file=$credfile -e "use dspam" &> /dev/null
[ "$?" = "0" ] && mysqldump --defaults-extra-file=$credfile dspam > dspam.sql \
               && mysql --defaults-extra-file=$credfile -e "drop database dspam" \
               && echo "dspam db saved to dspam.sql and dropped..."

# Get dspam db structure
wget https://raw.githubusercontent.com/qmtoaster/dspam/master/dspamdb.sql
if [ "$?" != "0" ]; then
   echo "Error downloading dspam db: ($?), exiting..."
   exit 1
fi

# Create dspam with correct permissions
echo "Creating Dspam database..."
mysqladmin --defaults-extra-file=$credfile reload
mysqladmin --defaults-extra-file=$credfile refresh
mysqladmin --defaults-extra-file=$credfile create dspam
mysqladmin --defaults-extra-file=$credfile reload
mysqladmin --defaults-extra-file=$credfile refresh
echo "Adding dspam users and privileges..."
mysql --defaults-extra-file=$credfile -e "CREATE USER dspam@localhost IDENTIFIED BY 'p4ssw3rd'"
mysql --defaults-extra-file=$credfile -e "GRANT ALL PRIVILEGES ON dspam.* TO dspam@localhost"
mysqladmin --defaults-extra-file=$credfile reload
mysqladmin --defaults-extra-file=$credfile refresh
echo "Done with dspam database..."
mysql --defaults-extra-file=$credfile dspam < dspamdb.sql
mysqladmin --defaults-extra-file=$credfile reload
mysqladmin --defaults-extra-file=$credfile refresh
# End DSpam DB install

wget http://repo.whitehorsetc.com/10/testing/x86_64/qmt-release-1-9.qt.el10.noarch.rpm
dnf -y install qmt-release-1-9.qt.el10.noarch.rpm

# Install Dspam
dnf -y --enablerepo=fedora41 install dspam dspam-libs dspam-client dspam-mysql dspam-web rspamd
systemctl enable --now dspam rspamd
systemctl status dspam rspamd

dnf -y install clamav-update
dnf -y install clamd && dnf -y downgrade clamd

# Install Qmail
dnf -y install daemontools spamassassin ucspi-tcp libsrs2 libsrs2-devel vpopmail \
               spamdyke simscan qmail autorespond control-panel 'ezmlm*' qmailadmin \
               qmailmrtg maildrop isoqlog vqadmin squirrelmail ripmime dovecot \
               dovecot-mysql

chkconfig qmail on

sed -i 's/softlimit -m.*\\/softlimit -m 256000000 \\/' /var/qmail/supervise/smtp/run
sed -i 's|/cgi-bin||'  /usr/share/squirrelmail/plugins/qmailadmin_login/config_default.php
sed -i -z 's/#LocalSocket/LocalSocket/2' /etc/clamd.d/scan.conf
chown -R clamupdate:clamupdate /var/lib/clamav
[ -f /etc/dovecot/dovecot.conf ] && mv /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.bak
[ -f /etc/dovecot/dovecot-sql.conf.ext ] && mv /etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext.bak
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot.conf
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot-sql.conf.ext
systemctl reload dovecot &> /dev/null

# Until added to qmail
[ ! -h /usr/sbin/sendmail ] && ln -s /var/qmail/bin/sendmail /usr/sbin/sendmail || echo "sendmail present..."

# Enable man pages
echo "Enable QMT man pages..."
echo "MANDATORY_MANPATH /var/qmail/man" >> /etc/man_db.conf

printf $RED
echo "Downloading ClamAV database..."
printf $NORMAL
freshclam
printf $RED
echo "Starting QMT..."
printf $NORMAL
qmailctl start
printf $RED

sed -i 's/ConditionVirtualization=no/ConditionVirtualization=yes/g' /usr/lib/systemd/system/smartd.service
systemctl daemon-reload

echo "Starting clamd freshclam dovecot spamassassin httpd chronyd acpid atd autofs smartd named, this may take a while..."
printf $NORMAL
systemctl enable --now clamd@scan clamav-freshclam dovecot spamassassin httpd chronyd acpid atd autofs smartd named

wget -O /usr/local/bin/toaststat https://raw.githubusercontent.com/qmtoaster/scripts/master/toaststat.cos9
if [ "$?" = "0" ]; then
   chmod 755 /usr/local/bin/toaststat
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
wget -P /usr/local/bin https://raw.githubusercontent.com/qmtoaster/scripts/master/conntest
if [ "$?" = "0" ]; then
   chmod 755 /usr/local/bin/conntest
   conntest
fi

# Add access to QMT administration from desired network or hosts
sed -i -e 's/Define aclnet "127.0.0.1"/Define aclnet "192.168.2.0\/24 192.168.9.0\/24 127.0.0.1"/' /etc/httpd/conf/toaster.conf && \
  systemctl reload httpd

# Add roundcube support
echo "Adding roundcubemail support..."
mysql --defaults-extra-file=$credfile -e "create database roundcube character set utf8 collate utf8_bin"
mysql --defaults-extra-file=$credfile -e "CREATE USER roundcube@localhost IDENTIFIED BY 'p4ssw3rd'"
mysql --defaults-extra-file=$credfile -e "GRANT ALL PRIVILEGES ON roundcube.* TO roundcube@localhost"
mysql --defaults-extra-file=$credfile roundcube < /usr/share/roundcubemail/SQL/mysql.initial.sql
cp -p /etc/httpd/conf.d/roundcubemail.conf /etc/httpd/conf.d/roundcubemail.conf.bak && \
wget -O /etc/roundcubemail/config.inc.php http://www.qmailtoaster.org/rc.default.config && \
wget -O /etc/httpd/conf.d/roundcubemail.conf http://www.qmailtoaster.org/rc.httpd.config
cp config.inc.php config.inc.php.bak
sed -i 's/127.0.0.1/127.0.0.1:25/g' config.inc.php
echo "date.timezone = \"`timedatectl status | grep "zone" | sed -e 's/^[ ]*Time zone: \(.*\) (.*)$/\1/g'`\"" > /etc/php.d/50-qmail.ini
systemctl restart httpd

echo "CentOS 10 QMT installation complete"
end=`date`
echo "Start: $begin"
echo "  End: $end"
exit 0

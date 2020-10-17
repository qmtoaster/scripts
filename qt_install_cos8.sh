#!/bin/bash

begin=`date`

# Open necessary firewall port, and disable selinux
TAB="$(printf '\t')" && GREEN=$(tput setaf 2) && RED=$(tput setaf 1) && NORMAL=$(tput sgr0) && \
  systemctl start firewalld && systemctl enable firewalld && \
  ports=(20 21 22 25 80 89 110 113 143 443 465 587 993 995 3306) && \
  for index in ${!ports[*]}; do echo -n "Opening port: ${ports[$index]} : ";tput setaf 2;firewall-cmd --zone=public --add-port=${ports[$index]}/tcp --permanent;tput sgr0; done && \
  firewall-cmd --zone=public --add-port=53/udp --permanent && \
  echo -n "Reload firewall settings : " && tput setaf 2 && firewall-cmd --reload && tput sgr0
setenforce 0 && sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config && getenforce

# Update minimal, install EPEL and REMI (roundcubemail) here, and add necessary programs.
yum -y update && \
  yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
  yum -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm && \
  dnf -y install dnf-utils && \
  dnf -y module install php:remi-7.4 && \
  yum -y --enablerepo=remi install logwatch bind bind-utils telnet yum-utils chrony acpid at autofs bzip2 \
                                   smartmontools wget vsftpd mod_ssl fail2ban roundcubemail php-mysql


# Choose backend MariaDB or MySQL
read -p "Enter backend database 1) MariaDB 2) MySQL, 1 or 2: " backend
if [ -z "$backend" ]; then
   echo "Empty backend, exiting..."
   exit 1
fi
if [ "$backend" != "1" ] && [ "$backend" != "2" ]
then
  echo "Enter 1 for MariaDB or 2 for MySQL database" && exit 1
fi
[ "$backend" = "1" ] && DB=mariadb || DB=mysql

# Set DNF variables
echo "$DB" > /etc/yum/vars/db

DB=`cat /etc/yum/vars/db` && [[ "$DB" == *mysql* ]] && DBD="${DB}d" || DBD="${DB}"

echo "Using $DBD backend..."

yum -y install $DB $DB-server

# MySQL admin password
read -s -p "Enter $DBD password: " password
if [ -z "$password" ]; then
   echo "Empty password, exiting..."
   exit 1
fi
echo -e "\n"
MYSQLPW=$password
credfile=~/sql.cnf
echo -e "[client]\nuser=root\npassword=$MYSQLPW\nhost=localhost" > $credfile
echo "Starting $DBD Server..."
systemctl start $DBD && systemctl enable $DBD && systemctl status $DBD
echo "Started $DBD Server"
sleep 2
echo "Setting $DBD admin password..."
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

# Add repos
curl -o /etc/yum.repos.d/qmt.repo  https://raw.githubusercontent.com/qmtoaster/mirrorlist/master/qmt-centos8.repo
DOVECOTMYSQL=
if [[ "$DB" == *"mysql"* ]]
then
   read -p "Do you want Many-Domain setup? If you're unsure press [ENTER] (Y/N): " yesno
   yesno=${yesno^^}
   if [ "$yesno" = "Y" ]
   then
      wget -O /etc/yum.repos.d/qmt-md.repo  https://raw.githubusercontent.com/qmtoaster/mirrorlist/master/qmt-md-centos8.repo
      yum-config-manager --enable qmt-md-testing
      wget -P /etc/yum.repos.d https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot.repo
      yum makecache
      DOVECOTMYSQL=dovecot-mysql
   fi
fi

yum -y install clamav-update

# Install Qmail
yum -y install daemontools ucspi-tcp libsrs2 libsrs2-devel vpopmail \
               spamdyke simscan qmail autorespond control-panel ezmlm \
               ezmlm-cgi qmailadmin qmailmrtg maildrop maildrop-devel \
               isoqlog vqadmin squirrelmail ripmime dovecot $DOVECOTMYSQL \
               qmt-plus clamd

sed -i 's/^#LocalSocket /LocalSocket /'  /etc/clamd.d/scan.conf
chown -R clamupdate:clamupdate /var/lib/clamav
if [ -f /etc/yum.repos.d/dovecot.repo ]
then
   [ -f /etc/dovecot/dovecot.conf ] && mv /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.bak
   [ -f /etc/dovecot/dovecot-sql.conf.ext ] && mv /etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext.bak
   wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot.conf
   wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot-sql.conf.ext
   systemctl relaod dovecot &> /dev/null
fi   

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
echo "Starting clamd freshclam dovecot spamassassin httpd chronyd acpid atd autofs smartd named, this may take a while..."
printf $NORMAL
systemctl enable --now clamd@scan clamav-freshclam dovecot spamassassin httpd chronyd acpid atd autofs smartd named

wget -O /usr/bin/toaststat https://raw.githubusercontent.com/qmtoaster/scripts/master/toaststat.cos8
if [ "$?" = "0" ]; then
   chmod 755 /usr/bin/toaststat
   sed -i 's/CLAMS=clamav-daemon.socket//' /usr/bin/toaststat
   sed -i 's/$CLAMS//' /usr/bin/toaststat
   sed -i 's/CLAMD=clamav-daemon.service/CLAMD=clamd@scan.service/' /usr/bin/toaststat
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
 sed -i 's/\;date.timezone.*/date.timezone = "America\/Denver"/' /etc/php.ini | sleep 2 | cat /etc/php.ini | grep date.timezone.*=
 systemctl restart httpd

update-crypto-policies --set LEGACY

echo "CentOS 8 QMT installation complete"
end=`date`
echo "Start: $begin"
echo "  End: $end"
exit 0

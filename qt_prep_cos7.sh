#!/bin/bash
# Eric Broch <ebroch@whitehorsetc.com> 
#
# Disable Selinux, update host, install pkgs.
######################################################################
# Change Log
# 10-27-2016  Written by Eric Broch <ebroch@whitehorsetc.com> 
#             Thanks to Eric Shubert's template
######################################################################

######################################################################
# disable SELINUX
#
a2_disable_selinux(){

selinux_config=/etc/selinux/config

if [ ! -f "$selinux_config" ]; then
  echo "$me - $selinux_config not found, continuing..."
  return
fi

echo "$me - disabling SELINUX ..."
sed -i$(date +%Y%m%d) -e "s|^SELINUX=.*$|SELINUX=disabled|" $selinux_config
setenforce 0
}

######################################################################
# main routine begins here
#
me=${0##*/}
myver=v1.0
echo "$me - $myver"

a2_disable_selinux

echo "$me - updating all packages (yum update) ..."
yum clean all
yum -y update
yum -y install wget

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
NORMAL=$(tput sgr0)

wget https://raw.githubusercontent.com/qmtoaster/scripts/master/qmt_host.sh
chmod 755 qmt_host.sh
wget https://raw.githubusercontent.com/qmtoaster/scripts/master/qt_install_cos7.sh
if [ "$?" != "0" ]; then
   echo $RED
   echo "QMT Installer (qt_install.sh) did not download, download manually from (https://raw.githubusercontent.com/qmtoaster/scripts/master/)."
   echo $NORMAL
else
   chmod 755 qt_install_cos7.sh
   echo $GREEN
   echo "QMT Installer (qt_install_cos7.sh) is located in `pwd`, run this script after reboot to complete QMT toaster install."
   echo $NORMAL
   sleep 2
fi
echo "$me - rebooting now..."
shutdown -r now

echo "$me - completed"
exit 0

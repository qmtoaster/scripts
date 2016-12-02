#!/bin/sh

#
#   Script: chg_dns.sh
# Function: Switches nameserver software between bind, pdns, and djbdns.
#           Changes the nameserver to the localhost (127.0.0.1) 
#           by modifying /etc/resolv.conf and the active interface script:
#           /etc/sysconfig/network-scripts/ifcfg-'active'.
#   Author: Eric C. Broch
#
#      Use: ./chg-dns.sh bind
#           ./chg-dns.sh djbdns
#           ./chg-dns.sh pdns
#
#  Warning: This script is not bullet-proof, use at your own risk.
#  Failure: In event of a failure sets FreeDNS 37.235.1.174 as the 
#           nameserver.
#



# disable SELINUX
#
disable_selinux()
{
   setenforce 0
   selinux_config=/etc/selinux/config
   if [ ! -f "$selinux_config" ]
   then
      echo "Selinux Config ($selinux_config) not found..."
      return 1
   fi
   echo "Disabling selinux ..."
   sed -i$(date +%Y%m%d) -e "s|^SELINUX=.*$|SELINUX=disabled|" $selinux_config
   return 0
}

# Test an IP address for validity:
# Usage:
#      valid_ip IP_ADDRESS
#      if [[ $? -eq 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_ip IP_ADDRESS; then echo good; else echo bad; fi
#
function valid_ip()
{
    local  ip=$1
    local  stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
       OIFS=$IFS
       IFS='.'
       ip=($ip)
       IFS=$OIFS
       [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
           && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
       stat=$?
    fi
    return $stat
}
# 
# Set nameserver in resolv.conf
#
function set_resolv()
{
   valid_ip $1
   ns=`cat /etc/resolv.conf | grep nameserver`
   echo "Before: nameserver in resolv.conf $ns"
   cat /etc/resolv.conf | grep search > /tmp/srch-$$
   cp -p /etc/resolv.conf /etc/resolv.conf.bak
   cat /tmp/srch-$$ > /etc/resolv.conf
   echo "nameserver $1" >> /etc/resolv.conf
   rm /tmp/srch-$$
   ns=`cat /etc/resolv.conf | grep nameserver`
   echo "After: nameserver in resolv.conf $ns"
}
#
# Set nameserver in active interface connection
#
function set_if()
{
 [ ! -f /usr/bin/nmcli ] && echo $GREEN \
                           && echo "Network Manager must be installed to continue, installing..." \
                           && echo $NORMAL && sleep 2 \
                           && yum -y install NetworkManager
                           
   aif=`nmcli connection show --active | grep ethernet | cut -d' ' -f1`
   ifc=/etc/sysconfig/network-scripts/ifcfg-$aif
   valid_ip $1
   if [[ $? -eq 0 ]]; then
      echo "$1 is a valid IP address, modifying ifcfg-$aif"
      if [ -f $ifc ]; then
         ns=`cat $ifc | grep DNS1`
         echo "Before: nameserver IF $ns"
         nmcli con mod $aif ipv4.dns "$1"
         ns=`cat $ifc | grep DNS1`
         echo "After: nameserver IF $ns"
      else
         echo "No corresponding interface file ($aif)"
         return 1
      fi
   else
      echo "$1 is an invalid IP Address, exiting..."
      return 1
   fi
}

#
# Check input paramter
#
if [ "$1" != "bind" ] && [ "$1" != "djbdns" ] && [ "$1" != "pdns" ]
then
   echo "Enter CLI  parameter: bind, pdns, or djbdns"
   exit
fi

selnx=`getenforce`
selnx=`echo "${selnx,,}"`
if [ "$1" = "djbdns" ] && [ "$selnx" = "enforcing" ]
then
   echo "Before the djbdns name service will start Selinux will be disabled. To make change permanent a reboot is necessary"
   disable_selinux
   echo "Selinux disabled"
   sleep 2   
fi

# Nameserver must be external (not localhost), temporarily, between removal of old, and install of new, nameserver software
# as yum depends on DNS services
set_resolv 37.235.1.174 
# Set active interface DNS (DNS1) to 127.0.0.1. If this is not set, on reboot, the system will revert resolv.conf to the old setting.
set_if  127.0.0.1

# Install pdns and remove djbdns, and bind
if [ "$1" = "pdns" ]; then
   echo "Installing Bind..."
   systemctl stop djbdns
   systemctl stop named
   yum -y remove djbdns-localcache
   yum -y remove bind bind-chroot
   yum -y install epel-release
   yum -y install pdns-recursor
   echo "allow-from=127.0.0.1/8" >> /etc/pdns-recursor/recursor.conf
   systemctl enable pdns-recursor
   systemctl start pdns-recursor
fi

# Install bind and remove djbdns, and pdns
if [ "$1" = "bind" ]; then
   echo "Installing Bind..."
   systemctl stop djbdns
   systemctl stop pdns-recursor
   yum -y remove djbdns-localcache
   yum -y remove pdns-recursor
   yum -y install bind
   systemctl enable named
   systemctl start named
fi
# Install djbdns and remove bind, and pdns
if [ "$1" = "djbdns" ]; then
   echo "Installing DJBDNS..."
   systemctl stop named
   systemctl stop pdns-recursor
   yum -y remove bind bind-chroot
   yum -y remove pdns-recursor
   # Check if repo for djbdns is installed 
   wget https://github.com/qmtoaster/release/raw/master/qmt-release-1-3.qt.el7.noarch.rpm
   yum -y localinstall qmt-release-1-3.qt.el7.noarch.rpm
   yum -y install djbdns-localcache
   systemctl start djbdns
   systemctl status djbdns
fi

# After success set nameserver localally 
set_resolv 127.0.0.1

echo ""
echo ""
echo "Testing the local nameserver..."
nslookup msn.com
if [ "$?" = "1" ]; then
   echo "Local nameserver lookup failed, changing to external nameserver @ FreeDNS 37.235.1.174 ..."
   set_resolv 37.235.1.174
   set_if 37.235.1.174
else
   echo "Local nameserver lookup succeded..."
fi


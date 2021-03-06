#!/bin/sh

#
#   Script: qmt_host.sh
# Function: This script was written to change IPv4 parameters
#           (hostname, address, subnet mask, gateway, and dns)
#           on my boxed standard CentOS 7 VM.
#
#   Author: Eric C. Broch
#
#      Use: ./qmt_host.sh hostname ipv4.address ipv4.gateway ipv4.dns (ipv4.dns optional)
#
#  Warning: This script is not bullet-proof, use at your own risk.
#           It is best to use this script in the console as you most
#           likely will be changing the IPv4 address. All changes will
#           be made, but you will be disconnected from the host.
#           The DNS setting will be set to OpenDNS server 208.67.222.222
#           if none is provided on the command line.
#
#  Failure: Set up the network manually.
#
#  Updates:
#  
#  Added install of NetworkManager necessary to run nmcli 12-1-2016
#
GREEN=$(tput setaf 2)
NORMAL=$(tput sgr0)

# This script was written to change IPv4 parameters (hostname, address, subnet mask, gateway, and dns) on
# my boxed standard CentOS 7 VM, but can be used on any CentOS 7 host.

# Check if valid IPv4 address
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
# Set IPv4 interface parameters
function set_if()
{
   [ ! -f /usr/bin/nmcli ] && echo $GREEN \
                           && echo "Network Manager must be installed to continue, installing..." \
                           && echo $NORMAL \
                           && sleep 2 \
                           && yum -y install NetworkManager
   ip=$1
   gw=$2
   dns=$3
   aif=`nmcli connection show --active | grep ethernet | cut -d' ' -f1`
   ifc=/etc/sysconfig/network-scripts/ifcfg-$aif
   if [ -f $ifc ]
   then
      txt=`cat $ifc | grep BOOTPROTO`
      txt1=`cat $ifc | grep IPADDR`
      txt2=`cat $ifc | grep GATEWAY`
      txt3=`cat $ifc | grep DNS`
      echo "Before: nameserver IF $txt $txt1 $txt2 $txt3"
      nmcli con mod $aif ipv6.addresses "" ipv6.gateway "" ipv6.dns "" ipv6.method auto
      nmcli con mod $aif ipv4.addresses $ip/24 ipv4.gateway $gw ipv4.dns $dns ipv4.method manual
      txt=`cat $ifc | grep BOOTPROTO`
      txt1=`cat $ifc | grep IPADDR`
      txt2=`cat $ifc | grep GATEWAY`
      txt3=`cat $ifc | grep DNS`
      echo "After: nameserver IF $txt $txt1 $txt2 $txt3"
      systemctl restart network
   fi
}
# Set hostname
function set_hostname()
{
   hn=$1
   hostnamectl set-hostname $hn
   systemctl restart systemd-hostnamed
   hostnamectl status
}

if [ -z $1 ] || [ -z $2 ] || [ -z $3 ]
then
   echo ""
   echo "Call this script as follows (example below):"
   echo "$0 hostname ipv4.address ipv4.gateway"
   echo "$0 me.mydomain.com 192.168.0.2 192.168.0.1"
   echo ""
   exit
fi


hn=$1
ip=$2
gw=$3
dns="208.67.222.222"
if [ ! -z "$4" ]
then
   dns=$4
fi
# check ip
valid_ip $ip
if [[ $? -ne 0 ]]
then
   echo "$ip is not a valid IPv4 address"
   exit
fi
# check gw
valid_ip $gw
if [[ $? -ne 0 ]]
then
   echo "$gw is not a valid IPv4 address"
   exit
fi
# check dns
valid_ip $dns
if [[ $? -ne 0 ]]
then
   echo "$dns is not a valid IPv4 address"
   exit
fi


# Set hostname
set_hostname $hn

# Set IPv4 stuff
set_if $ip $gw $dns

exit 0


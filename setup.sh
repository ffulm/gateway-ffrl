#!/bin/bash

# This script sets up a Freifunk Ulm server consisting of the following blocks:

# 1. mesh (fastd, batman, alfred)
# 2. gateway (iptables, radvd, dns, dhcp, batman gateway mode)
# 3. webserver (lighttpd for status page, map pages)
# 7. unattended upgrades of debian packages (keeps your server save!)

# DO NOT CALL THE SCRIPTS IN STANDALONE MODE as this will NOT WORK!

#
# Please note:
# Toggling the setup_xxxx variables below back to 0 later does not _uninstall_ the software, but _skips_
# the _re-installation_ of this block. No further data updates will be performed by freifunk/update.sh for this block.
#
# BUT: Remaining server processes have to be manually stopped as needed. They are not killed by a 0 setting. 
# If you are not sure, which processes to stop - reboot the server, which cleans up the mess.
#
 

####################
# General settings #
####################

# The community identifier for internal purposes
community_id="ulm"
# The community identifier which shows up on websites, lists, meshviewer... 
community_name="Ulm"

# This server's name. Please stick to the vpnXX scheme. E.g. vpn10, vpn11, ...
ff_servername="vpnXX"

# The internal IPv6 prefix as defined in the Freifunk community wiki.
# https://wiki.freifunk-ulm.de/display/FI/Freifunk+Rheinland
ff_prefix="2a03:2260:1015:xxxx::/64"

####################
# 1. Mesh settings #
####################

# Run setup? 
# Mandatory.
setup_mesh=1

# IP v4 for mesh interface.
# This is gateway specific.
# Format: xxx.xxx.xxx.xxx
mesh_ipv4_addr=""

# Secret key for fastd (will be generated if not provided).
# Please keep in mind that the _public_ part of this key pair must be known to other gateways and routers to establish a connection
fastd_secret=""

# B.A.T.M.A.N version
batman_version=2022.3

#######################
# 2. Gateway settings #
#######################

# Run setup?
# Optional
setup_gateway=1

# Range for DHCP
# This is gateway specific. Get your DHCP range by writing to the mailing list!
# Enter space separated IP range: xxx.xxx.xxx.xxx xxx.xxx.xxx.xxx
dhcp_ipv4_range=""

#########################
# 3. webserver settings #
#########################

# A webserver is needed to display map and statistical information (e.g. map, munin stats). 
# Furthermore it is mandatory if users should be able to click on their router's "neighbourhood link" and 
# jump to the gateway they are connected with.

# If you run this part, be sure to have DNS resolution set up - otherwise certificate checkout at letsencrypt will fail!

# Run setup? 
# Optional
setup_webserver=1

#########################
# 7. unattended upgrade #
#########################

# Sets up unattended security upgrades performed by apt

# Run setup? 
# Optional
setup_unattended=1

# Everything set up ? 
# Set run to 1 for this script to run. :-)
run=0


################################################################
# NO CHANGES BELOW THIS LINE

export PATH=$PATH:/usr/local/sbin:/usr/local/bin

# abort script on first error
set -e
set -u

# config output colors
red=`tput setaf 1`
green=`tput setaf 2`
col_reset=`tput sgr0`

if [ $run -eq 0 ]; then
	echo "Check the variables in this script and then set run to 1!"
	exit 1
fi

ula_addr() {
	local prefix="$1" mac="$2" a

	# translate to local administered mac
	a=${mac%%:*} #cut out first hex
	a=$((0x$a ^ 2)) #invert second least significant bit
	a=`printf '%02x\n' $a` #convert back to hex
	mac="$a:${mac#*:}" #reassemble mac

	mac=${mac//:/} # remove ':'
	mac=${mac:0:6}fffe${mac:6:6} # insert ffee
	mac=`echo $mac | sed 's/..../&:/g'` # insert ':'

	# assemble IPv6 address
	echo "${prefix%%::*}:${mac%?}"
}

get_mac() {
	local mac="$(cat /sys/class/net/$1/address)" a

	# translate to local administered mac
	a=${mac%%:*} #cut out first hex
	a=$((0x$a ^ 2)) #invert second least significant bit
	a=`printf '%02x\n' $a` #convert back to hex
	echo "$a:${mac#*:}" #reassemble mac
}

# Set hostname
echo "(I) ${green}hostname will be set to $ff_servername ${col_reset}"
hostname -b $ff_servername

if ! ip addr list dev $wan_iface &> /dev/null; then
	echo "(E) ${red}Interface $wan_iface does not exist.${col_reset}"
	exit 1
fi

mac_addr="$(get_mac $wan_iface)"
mesh_ipv6_addr="$(ula_addr $ff_prefix $mac_addr)"

if [ -z "$mac_addr" -o -z "$mesh_ipv6_addr" ]; then
	echo "(E) ${red}MAC or IP address no set.${col_reset}"
	exit 1
fi

# disable rpcbind
systemctl stop rpcbind
systemctl disable rpcbind

echo "(I) ${green}Update package database${col_reset}"
apt update

if [ $setup_mesh -eq 1 ]; then ( . ./mesh.sh ) # source script in separate shell
fi
if [ $setup_gateway -eq 1 ]; then ( . ./gateway.sh ) # source script in separate shell
fi
if [ $setup_webserver -eq 1 ]; then ( . ./webserver.sh ) # source script in separate shell
fi
if [ $setup_unattended -eq 1 ]; then ( . ./unattended.sh ) # source script in separate shell
fi

{
	echo "(I) ${green}Fill /opt/freifunk/* directory...${col_reset}"
	cp -rf freifunk /opt/

	# transfer several constants to update.sh
	sed -i "s/mac_addr=\".*\"/mac_addr=\"$mac_addr\"/g" /opt/freifunk/update.sh
	sed -i "s/mesh_ipv6_addr=\".*\"/mesh_ipv6_addr=\"$mesh_ipv6_addr\"/g" /opt/freifunk/update.sh
	sed -i "s/ff_prefix=\".*\"/ff_prefix=\"$ff_prefix\"/g" /opt/freifunk/update.sh
	sed -i "s/mesh_ipv4_addr=\".*\"/mesh_ipv4_addr=\"$mesh_ipv4_addr\"/g" /opt/freifunk/update.sh

	sed -i "s/community=\".*\"/community=\"$community_id\"/g" /opt/freifunk/update.sh

	# transfer run state to update.sh
	sed -i "s/run_mesh=.*/run_mesh=$setup_mesh/g" /opt/freifunk/update.sh
	sed -i "s/run_gateway=.*/run_gateway=$setup_gateway/g" /opt/freifunk/update.sh
	sed -i "s/run_webserver=.*/run_webserver=$setup_webserver/g" /opt/freifunk/update.sh
}

if [ -z "$(cat /etc/crontab | grep '/opt/freifunk/update.sh')" ]; then
	echo "(I) ${green}Add update.sh entry to /etc/crontab${col_reset}"
	echo '*/5 * * * * root /opt/freifunk/update.sh > /dev/null 2>&1' >> /etc/crontab
fi

# call update script once to start all remaining services
/opt/freifunk/update.sh

echo "setup done"

exit 0

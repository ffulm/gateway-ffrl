#!/bin/bash

echo "${green}****************************${col_reset}"
echo "${green}* set up gateway functions *${col_reset}"
echo "${green}****************************${col_reset}"


#Firewall
{	
	#only really needed for a gateway
	echo "(I) ${green}Installing persistent iptables${col_reset}"
	apt install --assume-yes iptables-persistent

	cp -rf etc/iptables/* /etc/iptables/
	/etc/init.d/netfilter-persistent restart
}

setup_ffrl() {
	# todo
	echo "Freifunk Rheinland"
}

#IPv6 Router Advertisments
{
	echo "(I) ${green}Install radvd.${col_reset}"
	apt install --assume-yes radvd

	echo "(I) ${green}Configure radvd${col_reset}"
	cp etc/radvd.conf /etc/
	sed -i "s/fdef:17a0:fff1:300::1/$mesh_ipv6_addr/g" /etc/radvd.conf
	sed -i "s/fdef:17a0:fff1:300::/$ff_prefix/g" /etc/radvd.conf
}

#IPv4 DHCP
{
	echo "(I) ${green}Install DHCP server${col_reset}"
	apt install --assume-yes isc-dhcp-server
	cp -f etc/dhcp/dhcpd.conf /etc/dhcp/
	cp -f etc/dhcp/isc-dhcp-server /etc/default/
	sed -i "s/DNS_SERVER/$mesh_ipv4_addr/g" /etc/dhcp/dhcpd.conf
	sed -i "s/DHCP_RANGE/$dhcp_ipv4_range/g" /etc/dhcp/dhcpd.conf
	# change log rules in rsyslogd
	cp -f etc/rsyslog.d/00-dhcp.conf /etc/rsyslog.d/
	# activate new rules...
	systemctl restart rsyslog
}

exit 0

#!/bin/bash

#This script is called every 5 minutes via crond

#Server address
mac_addr=""
ip_addr=""
ff_prefix=""
ipv4_mesh_interface=""

#For the map
geo=""
name="$(hostname)"
firmware="server"
community="ulm"
webserver="true" #start webserver, create map/status/status page
gateway="false" #start OpenVPN, bind, tayga, radvd, DHCP, batman gateway mode
statistics="true" #start and setup statistical output


##############

#abort script on first error
set -e
set -u

export PATH=$PATH:/usr/local/sbin:/usr/local/bin

#switch script directory
cd "$(dirname $0)"

#create an IPv6 ULA-address based on EUI-64
ula_addr()
{
        local prefix a prefix="$1" mac="$2" invert=${3:-0}

        #prefix="$(uci get network.globals.ula_prefix)"

        if [ $invert -eq 1 ]; then
                # translate to local administered mac
                a=${mac%%:*} #cut out first hex
                a=$((0x$a ^ 2)) #invert second least significant bit
                a=$(printf '%02x\n' $a) #convert back to hex
                mac="$a:${mac#*:}" #reassemble mac
        fi

        mac=${mac//:/} # remove ':'
        mac=${mac:0:6}fffe${mac:6:6} # insert fffe
        mac=$(echo $mac | sed 's/..../&:/g') # insert ':'

        # assemble IPv6 address
        echo "${prefix%%::*}:${mac%?}"
}


#limit name length
name="$(echo $name | cut -c 1-31)"

[ -n "$ff_prefix" ] || { echo "(E) ff_prefix not set!"; exit 1; }
[ -n "$ip_addr" ] || { echo "(E) ip_addr not set!"; exit 1; }
[ -n "$mac_addr" ] || { echo "(E) mac_addr not set!"; exit 1; }

is_running() {
	pidof "$1" > /dev/null || return $?
}

#make sure batman-adv is loaded
modprobe batman_adv

#enable forwarding
echo 1 > /proc/sys/net/ipv6/conf/default/forwarding
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
echo 1 > /proc/sys/net/ipv4/conf/default/forwarding
echo 1 > /proc/sys/net/ipv4/conf/all/forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward


if ! is_running "fastd"; then
	echo "(I) Start fastd."
	fastd --config /etc/fastd/fastd.conf --daemon
	sleep 1
fi

if [ $(batctl if | grep fastd_mesh -c) = 0 ]; then
	echo "(I) Add fastd interface to batman-adv."
	ip link set fastd_mesh up
	ip addr flush dev fastd_mesh
	batctl if add fastd_mesh
fi

if [ "$(cat /sys/class/net/bat0/address 2> /dev/null)" != "$mac_addr" ]; then
	echo "(I) Set MAC address for bat0."
	ip link set bat0 down
	ip link set bat0 address "$mac_addr"
	ip link set bat0 up
	#set IPv4 address on bat0 for DNS; This is gateway specific!
	ip addr add "$ipv4_mesh_interface/16" dev bat0 2> /dev/null && echo "(I) Add IPv4-Address $ipv4_mesh_interface to bat0"


        # Add IPv6 address the same way the routers do.
        # This makes the address consistent with the one used on the routers status page.
        macaddr="$(cat /sys/kernel/debug/batman_adv/bat0/originators | awk -F'[/ ]' '{print $7; exit;}')"
        ipaddr="$(ula_addr $ff_prefix $macaddr)"
        ip a a "$ipaddr/64" dev bat0

	# we do not accept a default gateway through bat0
	echo 0 > /proc/sys/net/ipv6/conf/bat0/accept_ra

	#set neighbor table times to ten times the default
	echo 600 > /proc/sys/net/ipv6/neigh/bat0/gc_stale_time
	echo 300000 > /proc/sys/net/ipv6/neigh/bat0/base_reachable_time_ms

	echo "(I) Configure batman-adv."
	echo 10000 >  /sys/class/net/bat0/mesh/orig_interval
	echo 1 >  /sys/class/net/bat0/mesh/distributed_arp_table
	echo 1 >  /sys/class/net/bat0/mesh/multicast_mode
	echo 1 >  /sys/class/net/bat0/mesh/bridge_loop_avoidance
	echo 1 >  /sys/class/net/bat0/mesh/aggregated_ogms

	#set size of neighbor table
	gc_thresh=1024 #default is 256

	sysctl -w net.ipv4.neigh.default.gc_thresh1=$(($gc_thresh * 1))
	sysctl -w net.ipv4.neigh.default.gc_thresh2=$(($gc_thresh * 2))
	sysctl -w net.ipv4.neigh.default.gc_thresh3=$(($gc_thresh * 4))

	sysctl -w net.ipv6.neigh.default.gc_thresh1=$(($gc_thresh * 1))
	sysctl -w net.ipv6.neigh.default.gc_thresh2=$(($gc_thresh * 2))
	sysctl -w net.ipv6.neigh.default.gc_thresh3=$(($gc_thresh * 4))
fi

if ip -6 addr add "$ip_addr/64" dev bat0 2> /dev/null; then
	echo "(I) Set IP-Address of bat0 to $ip_addr"
fi

if ! is_running "alfred"; then
	# remove remains
	rm -f /var/run/alfred/*
	# set minimum access rights for reading information out of kernel debug interface
	chown root.alfred /sys/kernel/debug
	chmod 750 /sys/kernel/debug
	# create separate run dir with appropriate access rights because it gets deleted with every reboot
	mkdir --parents --mode=775 /var/run/alfred/
	chown alfred.alfred /var/run/alfred/
	# wait for changes to settle before starting up alfred... 
	sleep 3
	echo "(I) Start alfred."
	# set umask of socket from 0117 to 0111 so that update.sh can access alfred.sock
	start-stop-daemon --start --quiet --pidfile /var/run/alfred/alfred.pid \
		--umask 0111 --make-pidfile --chuid alfred --group alfred \
		--background --exec `which alfred` --oknodo \
		-- -i bat0 -u /var/run/alfred/alfred.sock
	sleep 1
fi

#announce status website via alfred
{
	echo -n "{\"link\" : \"http://[$ip_addr]/index.html\", \"label\" : \"Freifunk Gateway $name\"}"
} | alfred -s 91 -u /var/run/alfred/alfred.sock


#announce map information via alfred
{
	vpn="true"

	echo -n "{"

	[ -n "$geo" ] && echo -n "\"geo\" : \"$geo\", "
	[ -n "$name" ] && echo -n "\"name\" : \"$name\", "
	[ -n "$firmware" ] && echo -n "\"firmware\" : \"$firmware\", "
	[ -n "$community" ] && echo -n "\"community\" : \"$community\", "
	[ -n "$vpn" ] && echo -n "\"vpn\" : $vpn, "
	[ -n "$gateway" ] && echo -n "\"gateway\" : $gateway, "
	echo -n "\"links\" : ["

	printLink() { echo -n "{ \"smac\" : \"$(cat /sys/class/net/$3/address)\", \"dmac\" : \"$1\", \"qual\" : $2 }"; }
	IFS="
"
	nd=0
	for entry in $(cat /sys/kernel/debug/batman_adv/bat0/originators |  tr '\t/[]()' ' ' |  awk '{ if($1==$4) print($1, $3, $5) }'); do
		[ $nd -eq 0 ] && nd=1 || echo -n ", "
		IFS=" "
		printLink $entry
	done

	echo -n '], '
	echo -n "\"clientcount\" : 0"
	echo -n '}'
} | gzip -c - | alfred -s 64 -u /var/run/alfred/alfred.sock

if [ "$webserver" = "true" ]; then

	if ! is_running "lighttpd"; then
                #if [ `ip addr | grep __IPV6__ | wc -l` != 1 ]; then
                #  echo "(I) Set autoupdater IP for vpn5."
                #  ip addr add __IPV6__ dev bat0
                #fi
                #if [ `ip addr | grep __IPV6__ | wc -l` != 1 ]; then
                #   # EUI64: ip v6 prefix + 3 bytes MAC + fffe + 3 bytes MAC
                #  echo "(I) Set IP for accessing vpn5 from node status page."
                #  ip addr add __IPV6__ dev bat0
                #  sleep 1
                #fi
		echo "(I) Start lighttpd."
		/etc/init.d/lighttpd start
	fi

	#collect all map pieces
	alfred -r 64 -u /var/run/alfred/alfred.sock > /tmp/maps.txt

	#create map data (old map)
	#./ffmap-backend.py -m /tmp/maps.txt -a ./aliases.json > /var/www/nodes.json
	# create map data (meshviewer)
        ./map-backend.py -m /tmp/maps.txt --meshviewer-nodes /var/www/meshviewer/nodes.json --meshviewer-graph /var/www/meshviewer/graph.json
        
	#update FF-Internal status page
	./status_page_create.sh '/var/www/index.html'

	#update nodes/clients/gateways counter
	./counter_update.py '/var/www/nodes.json' '/var/www/counter.svg'

	# statistics
	if [ "$statistics" = "true" ]; then
	  # add vnstat interface for bat0
	  vnstat -u -i bat0
	  # grant access for vnstat
	  chown vnstat.vnstat /var/lib/vnstat/bat0
	  if ! is_running "vnstatd"; then
	    /etc/init.d/vnstat start
	  fi
	fi
fi

if [ "$gateway" = "true" ]; then
	if ! is_running "openvpn"; then
		echo "(I) Start openvpn."
		/etc/init.d/openvpn start
	fi

	if ! is_running "tayga"; then
		echo "(I) Start tayga."
		tayga
	fi

	if ! is_running "named"; then
		echo "(I) Start bind."
		/etc/init.d/bind9 start
	fi

	if ! is_running "radvd"; then
		echo "(I) Start radvd."
		/etc/init.d/radvd restart
	fi
	if ! is_running "dhcpd"; then
		echo "(I) Start DHCP."
		/etc/init.d/isc-dhcp-server start
	fi

	# Activate the gateway announcements on a node that has a DHCP server running
	batctl gw_mode server
fi

echo "update done"


#!/bin/bash

sha256check() {
	local file="$1" hash="$2"
	if [ "$(sha256sum $file | cut -b 1-64)" != "$hash" ]; then
		echo "(E) ${red}Hash mismatch: $file${col_reset}"
		exit 1
	fi
}

echo "${green}***************************${col_reset}"
echo "${green}* set up meshing software *${col_reset}"
echo "${green}***************************${col_reset}"

{
	echo "(I) ${green}Install batman-adv, batctl and alfred ($batman_version).${col_reset}"
	apt install --assume-yes clang-format meson bison wget build-essential linux-headers-$(uname -r) pkg-config libnl-3-dev libjson-c-dev git libcap-dev pkg-config libnl-genl-3-dev libssl-dev libmnl-dev

	#install batman-adv
	wget -N --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$batman_version/batman-adv-$batman_version.tar.gz
	sha256check "batman-adv-$batman_version.tar.gz" "cff7a2f160045fd0dbf1f1cd7e35e93bf489e81cb8b9501b3756daa391f3eb1b"
	tar -xzf batman-adv-$batman_version.tar.gz
	cd batman-adv-$batman_version/
	make CONFIG_BATMAN_ADV_DEBUGFS=y
	make CONFIG_BATMAN_ADV_DEBUGFS=y install
	cd ..
	rm -rf batman-adv-$batman_version*

	#install batctl
	wget -N --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$batman_version/batctl-$batman_version.tar.gz
	sha256check "batctl-$batman_version.tar.gz" "b6d96e908e3295a1413e8ec4f0f9851f85c67c752ac45bebbbe58aad40fad8e7"
	tar -xzf batctl-$batman_version.tar.gz
	cd batctl-$batman_version/
	make
	make install
	cd ..
	rm -rf batctl-$batman_version*

	#install alfred
	wget -N --no-check-certificate http://downloads.open-mesh.org/batman/stable/sources/alfred/alfred-$batman_version.tar.gz
	sha256check "alfred-$batman_version.tar.gz" "4c79b6c45de4bcc8cbfe64cba9a0f8b4ef304ca84c194622f2bfa41e01e2cb95"
	tar -xzf alfred-$batman_version.tar.gz
	cd alfred-$batman_version/
	make CONFIG_ALFRED_GPSD=n CONFIG_ALFRED_VIS=n
	make CONFIG_ALFRED_GPSD=n CONFIG_ALFRED_VIS=n install
	cd ..
	rm -rf alfred-$batman_version*
}

{
	# set capablilities for alfred binary (create sockets and use elevated privs)
	# got reset by installation of new alfred binary above
	setcap cap_net_admin,cap_net_raw+ep `which alfred`

	# create alfred group
	addgroup --system alfred

	echo "(I) ${green}Create user alfred for alfred daemon.${col_reset}"
	adduser --system --home /var/run/alfred --shell /bin/false --ingroup alfred --disabled-password alfred
}

{
	echo "(I) ${green}Install fastd prerequisites${col_reset}"

	apt install --assume-yes git cmake-curses-gui libnacl-dev flex bison libcap-dev pkg-config zip libjson-c-dev

	echo "(I) ${green}Build and install libsodium${col_reset}"

	#install libsodium
	wget -N --no-check-certificate https://github.com/jedisct1/libsodium/releases/download/1.0.18-RELEASE/libsodium-1.0.18.tar.gz -O libsodium-1.0.18.tar.gz
	sha256check "libsodium-1.0.18.tar.gz" "6f504490b342a4f8a4c4a02fc9b866cbef8622d5df4e5452b46be121e46636c1"
	tar -xvzf libsodium-1.0.18.tar.gz
	cd libsodium-1.0.18
	./configure
	make
	make install
	cd ..
	rm -rf libsodium-*
	ldconfig

	echo "(I) ${green}Build and install libuecc${col_reset}"

	#install libuecc
	wget -N --no-check-certificate https://github.com/NeoRaider/libuecc/releases/download/v7/libuecc-7.tar.xz -O libuecc-7.tar.xz
	sha256check "libuecc-7.tar.xz" "b94aef08eab5359d0facaa7ead2ce81b193eef0c61379d9835213ebc0a46257a"
	tar xf libuecc-7.tar.xz
	mkdir libuecc_build
	cd libuecc_build
	cmake ../libuecc-7
	make
	make install
	cd ..
	rm -rf libuecc_build libuecc-7*
	ldconfig

	echo "(I) ${green}Build and install fastd${col_reset}"

	#install fastd
	wget -N --no-check-certificate https://github.com/NeoRaider/fastd/releases/download/v22/fastd-22.tar.xz -O fastd-22.tar.xz
	sha256check "fastd-22.tar.xz" "19750b88705d66811b7c21b672537909c19ae6b21350688cbd1a3a54d08a8951"
	tar xf fastd-22.tar.xz
	meson setup fastd-22 fastd-build -Dbuildtype=release -Db_lto=true
	cd fastd-build
	ninja
	ninja install
	cd ..
	rm -rf fastd*
}

{
	echo "(I) ${green}Configure fastd${col_reset}"
	cp -r etc/fastd /etc/
	ln -s /usr/local/bin/fastd /usr/local/bin/fastd-2
	ln -s /usr/local/bin/fastd /usr/local/bin/fastd-3

	if [ -z "$fastd_secret" ]; then
		echo "(I) ${green}Create fastd public/private key pair. This may take a while...${col_reset}"
		fastd_secret=$(fastd --generate-key --machine-readable)
	fi
	echo "secret \"$fastd_secret\";" >> /etc/fastd/fastd.conf
	fastd_key=$(echo "secret \"$fastd_secret\";" | fastd --config - --show-key --machine-readable)
	echo "#key \"$fastd_key\";" >> /etc/fastd/fastd.conf

	sed -i "s/eth0/$wan_iface/g" /etc/fastd/fastd.conf
}

if ! id nobody >/dev/null 2>&1; then
	echo "(I) ${green}Create user nobody for fastd.${col_reset}"
	useradd --system --no-create-home --shell /bin/false nobody
fi


exit 0


Freifunk-Ulm Server
===============

Scripte und Konfigurationsdateien zum schnellen Einrichten eines Servers für Freifunk-Ulm.
Vorausgesetzt wird eine Debian 9 Installation (Stretch).
Um einen Server einzurichten, reicht es, das Script "setup.sh" als Benutzer 'root' auszuführen:

```
apt-get install git
git clone https://github.com/ffulm/server-config.git
cd server-config
./setup.sh
```

Nach erfolgreichem Einrichten wird das Script "/opt/freifunk/update.sh" alle 5 Minuten
von crond aufgerufen. Dadurch wird die Karte regelmäßig aktualisiert und nach
einem Neustart notwendige Programme neu gestartet.

### Server
Für die Serverfunktion werden folgende Programme installiert und automatisch konfiguriert:

 * Routingprotokoll: [batman-adv](http://www.open-mesh.org/projects/batman-adv/wiki)
 * FF-VPN: [fastd](https://fastd.readthedocs.io/en/latest/)
 * Webserver: lighttpd

### Gateway
Wird die Variable "setup_gateway" im Setup-Script auf "1" gesetzt, wird der Server zusätzlich
als Gateway eingerichtet.

Für die Gatewayfunktion werden folgende Programme installiert und automatisch konfiguriert:

 * DNS64: bind
 * IPv6 Router Advertisment: radvd

### IPv4
Durch die Reaktivierung von IPv4 im Freifunk Netz werden weitere Dienste benötigt:
 * DHCP (isc-dhcp-server)

Alle Serverbetreiber müssen sich absprechen, was den Bereich der verteilten DHCP Adressen angeht, damit es zu keinen Adresskonflikten kommt.
 
Innerhalb des Freifunknetzes gibt es die DNS Zone ".ffulm". D.h. es können auch Namen wie "meinserver.ffulm" aufgelöst werden.
Falls weitere Server hinzugefügt werden, müssen die Zonendateien auf dem Master (db.10.33, db.ffulm, named.conf.local) manuell angepasst werden. Hierzu bitte auf der Mailingliste melden.

### alfred 
Des Weiteren sollte mindestens ein Server mit dem Schalter "-m" als alfred master betrieben werden. Zur Zeit ist dies map11.
(Schalter zu finden unter: https://github.com/ffulm/server-config/blob/master/freifunk/update.sh)

### Netz
Freifunk Ulm nutzt folgende Netze:
 * ipv4: ```10.33.0.0/16```
 * ipv6: ```fdef:17a0:fff1::/48```

#!/bin/bash
#title           :install_designate.sh
#description     :This script will install designate, powerDNS-server and powerDNS backend in all-in-one architecture.
#author          :Claudio Marques - OneSource
#date            :20140112
#version         :3.0
#usage           : ./install_designate.sh
#==============================================================================
sudo sed -i '$ a\nameserver 8.8.8.8'  /etc/resolv.conf
sudo sed -i '$ a\nameserver 8.8.4.4'  /etc/resolv.conf

########
IP=`ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}'`

#######
## Solve possible environment locale variable issues 

VAR=`locale -a 2>&1 >/dev/null | grep 'Cannot set'`
if [ -z "$VAR" ]
then
	echo ""
else
	echo "Updating locale settings"
	sleep 2
	echo 'LC_ALL="en_GB.utf8"'  >> /etc/environment
	export LANGUAGE=en_US.UTF-8
	export LANG=en_US.UTF-8
	export LC_ALL=en_US.UTF-8
	locale-gen en_US.UTF-8
	dpkg-reconfigure locales
fi

#### Update and upgarde an install designate .deb  source-list
apt-get update && apt-get -y  upgrade
apt-get debconf-utils sed
apt-get install --yes python-software-properties
apt-get install --yes ubuntu-cloud-keyring

echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" | sudo tee /etc/apt/sources.list.d/cloud-archive-havana.list
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" | sudo tee /etc/apt/sources.list.d/cloud-archive-havana.list

apt-add-repository --yes ppa:designate-ppa/havana
apt-get  update && apt-get -y  upgrade

#### Install MYQL and storing mysql password
MYSQL_PASSWORD="password"
echo "${txtgrn}Continuing with MySQL Installation${txtrst}"
echo "mysql-server-5.1 mysql-server/root_password password $MYSQL_PASSWORD" | debconf-set-selections
echo "mysql-server-5.1 mysql-server/root_password_again password $MYSQL_PASSWORD" | debconf-set-selections

apt-get -y -qq install mysql-server mysql-client

##  Install RabbitMQ Pdns-server Pdns-backend and designate main components
export DEBIAN_FRONTEND=noninteractive
apt-get install --yes rabbitmq-server pdns-server pdns-backend-mysql 
apt-get install --yes designateclient designate-api designate-central
sed -i '/service:central/a backend_driver = powerdns \n' /etc/designate/designate.conf
sed -i '/storage:sqlalchemy/a database_connection = mysql://root:'$MYSQL_PASSWORD'@127.0.0.1/designate \n' /etc/designate/designate.conf
sed -i '/backend:powerdns/a database_connection = mysql://root:'$MYSQL_PASSWORD'@127.0.0.1/powerdns \n' /etc/designate/designate.conf

mysql -u root -p$MYSQL_PASSWORD -e 'CREATE DATABASE designate; CREATE DATABASE powerdns;'
designate-manage database-init
designate-manage database-sync
designate-manage powerdns database-init
designate-manage powerdns database-sync
restart designate-central

sed -i '/launch.*/c\launch=gmysql' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-host.*/c\gmysql-host=localhost' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-port.*/c\gmysql-port=' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-dbname.*/c\gmysql-dbname=powerdns' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-user.*/c\gmysql-user=root' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-password.*/c\gmysql-password='$MYSQL_PASSWORD'' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-dnssec.*/c\gmysql-dnssec=yes' /etc/powerdns/pdns.d/pdns.local.gmysql

service pdns restart
echo -e "\n\n\nDESIGNATE IS INSTALLED
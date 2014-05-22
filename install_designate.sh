#!/bin/bash

#title           :install_designate.sh
#description     :This script will install designate, powerDNS-server and powerDNS backend in all-in-one architecture
#				 : and enables designate to provide NAPTR support!
#author          :Claudio Marques - OneSource
#date            :20140112
#version         :5.0
#usage           : ./install_designate.sh
#
#==============================================================================

#=== Add google NS servers IP to resolv.conf

sudo sed -i '$ a\nameserver 8.8.8.8'  /etc/resolv.conf
sudo sed -i '$ a\nameserver 8.8.4.4'  /etc/resolv.conf

########
#TIME_START=`date +%s`
IP=`ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}'`
#######

#=== Solve possible environment locale variable issues 

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

#==== Update/Upgrade and get source-list

apt-get update && apt-get -y  upgrade
apt-get debconf-utils sed
apt-get install --yes python-software-properties
apt-get install --yes ubuntu-cloud-keyring

echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" | sudo tee /etc/apt/sources.list.d/cloud-archive-havana.list
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" | sudo tee /etc/apt/sources.list.d/cloud-archive-havana.list
apt-add-repository --yes ppa:designate-ppa/havana
apt-get  update && apt-get -y  upgrade

#==== Install MySQL 

MYSQL_PASSWORD="password"

echo "${txtgrn}Continuing with MySQL Installation${txtrst}"
echo "mysql-server-5.1 mysql-server/root_password password $MYSQL_PASSWORD" | debconf-set-selections
echo "mysql-server-5.1 mysql-server/root_password_again password $MYSQL_PASSWORD" | debconf-set-selections

apt-get -y -qq install mysql-server mysql-client

#===  Install RabbitMQ Pdns-server Pdns-backend and designate main components

export DEBIAN_FRONTEND=noninteractive

apt-get install --yes rabbitmq-server pdns-server pdns-backend-mysql 
apt-get install --yes designateclient designate-api designate-central

sed -i '/service:central/a backend_driver = powerdns \n' /etc/designate/designate.conf
sed -i '/storage:sqlalchemy/a database_connection = mysql://root:'$MYSQL_PASSWORD'@127.0.0.1/designate \n' /etc/designate/designate.conf
sed -i '/backend:powerdns/a database_connection = mysql://root:'$MYSQL_PASSWORD'@127.0.0.1/powerdns \n' /etc/designate/designate.conf

#=== Extend API to suport NAPTR records 

rm /usr/share/pyshared/designate/storage/impl_sqlalchemy/models.py
rm /usr/share/pyshared/designate/resources/schemas/v1/record.json
rm /usr/share/pyshared/designateclient/resources/schemas/v1/record.json
rm /usr/share/pyshared/designate/storage/impl_sqlalchemy/migrate_repo/versions/011_support_sshfp_records.py
wget -O /usr/share/pyshared/designate/storage/impl_sqlalchemy/models.py https://raw.githubusercontent.com/clmarques/DNSaaS/master/naptr_files/models.py
wget -O /usr/share/pyshared/designate/resources/schemas/v1/record.json https://raw.githubusercontent.com/clmarques/DNSaaS/master/naptr_files/record.json
wget -O /usr/share/pyshared/designateclient/resources/schemas/v1/record.json https://raw.githubusercontent.com/clmarques/DNSaaS/master/naptr_files/record.json
wget -O /usr/share/pyshared/designate/storage/impl_sqlalchemy/migrate_repo/versions/011_support_sshfp_records.py https://raw.githubusercontent.com/clmarques/DNSaaS/master/naptr_files/011_support_sshfp_records.py
#=== Create databases and tables for DNSaaS

mysql -u root -p$MYSQL_PASSWORD -e 'CREATE DATABASE designate; CREATE DATABASE powerdns;'
designate-manage database-init
designate-manage database-sync
designate-manage powerdns database-init
designate-manage powerdns database-sync
service designate-central restart && service designate-api restart

#=== Setup PowerDns

sed -i '/launch.*/c\launch=gmysql' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-host.*/c\gmysql-host=localhost' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-port.*/c\gmysql-port=' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-dbname.*/c\gmysql-dbname=powerdns' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-user.*/c\gmysql-user=root' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-password.*/c\gmysql-password='$MYSQL_PASSWORD'' /etc/powerdns/pdns.d/pdns.local.gmysql
sed -i '/gmysql-dnssec.*/c\gmysql-dnssec=yes' /etc/powerdns/pdns.d/pdns.local.gmysql

service pdns restart

#===================== Uncoment if you don't want to use a ssh keys =====================
#
# This section of code creates a user and password and enables the cloud instance to 
# accept SSH login with password. This user will be added to the sudoers file
#
#=========================================================================================
#
#if [ $(id -u) -eq 0 ]; then
#	username=user1		# change the username
#	password=password	# change the password
#	
#	egrep "^$username" /etc/passwd >/dev/null
#	if [ $? -eq 0 ]; then
#		echo "$username exists!"
#		exit 1
#	else
#		pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
#		useradd -m -p $pass $username
#		[ $? -eq 0 ] && echo "User has been added to system!" || echo "Failed to add a user!"
#	fi
#else
#	echo "Only root may add a user to the system"
#	exit 2
#fi
#echo "user1 ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
#sed -i '/PasswordAuthentication no/c\PasswordAuthentication yes' /etc/ssh/sshd_config
#
#=========================================================================================
#
#TIME_END=`date +%s`
#TIME_EXEC=`expr $(( $TIME_END - $TIME_START ))`

echo -e "\n\n\nDESIGNATE IS INSTALLED :)\n" 
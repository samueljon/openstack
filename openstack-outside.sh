#!/bin/sh

echo -n " WARN: `basename $0` will modify your network settings. Continue? y/n: "
read answer
if ! [ "$answer" == "y" ]
then
        exit 1
fi

source /root/keystonerc_admin

interfaces(){
lines=`ifconfig | awk -F "[: ]+" '/inet addr:/ { if ($4 != "127.0.0.1") print $4 }' | cut -d. -f1,2,3| wc -l`
if [ $lines -gt 1 ]
then
	echo " WARN: More than 1 physical network interface found"
	echo " Pls edit the variable available to `basename $0`"
	exit 1
else
	vlan=`ifconfig | awk -F "[: ]+" '/inet addr:/ { if ($4 != "127.0.0.1") print $4 }' | cut -d. -f1,2,3`
fi
}

#interfaces #disable this if the script detects more than one interface  and enable the below line
vlan=192.168.11

now=`date +%Y%m%d%H%M`
device=eth0
start=$vlan.49
end=$vlan.99
gw=$vlan.254
dns1=$vlan.253
dns2=$vlan.254
dns3=
hwaddr=`cat /etc/udev/rules.d/70-persistent-net.rules | grep $device | cut -d, -f4 | sed 's/ ATTR{address}=="//g' | sed 's/"//g'`
IP=`ifconfig $device|grep -w inet|awk '{print $2}'|cut -d: -f2`
domain=villingaholt.nu
PublicNet=PublicNet
PublicSubNet=PublicSubNet

##determine one physical nic or more
##if one nic move ip from nic to br-ex in /etc/sysconfig/network-scripts
device_exist(){
ifconfig $device > /dev/null  2>&1
if ! [ $? -eq 0 ]
then
	echo " ERROR: $device not found"
	echo " Pls edit the variable available to `basename $0`"
	exit 2
fi
if [ -f /etc/sysconfig/network-scripts/ifcfg-br-ex ]
then
	echo " WARN: br-ex already configured. Backup & Continue?"
	read answer
	if ! [ "$answer" == "y" ]
	then
        	exit 4
	fi
	mv /etc/sysconfig/network-scripts/ifcfg-br-ex /root/ifcfg-br-ex-$now
	echo " WARN: /etc/sysconfig/network-scripts/ifcfg-br-ex found. Saving $device to /root/ifcfg-$device.$now"
	mv /etc/sysconfig/network-scripts/ifcfg-$device /root/ifcfg-$device.$now
fi
}

device_primary(){
cat >> /etc/sysconfig/network-scripts/ifcfg-$device << EOF
DEVICE=$device
HWADDR=$hwaddr
ONBOOT=yes
#TYPE=OVSPort
#DEVICETYPE=ovs
#OVS_BRIDGE=br-ex
EOF
}

device_bridge(){
cat >> /etc/sysconfig/network-scripts/ifcfg-br-ex << EOF
DEVICE=br-ex
IPADDR=$IP
PREFIX=24
GATEWAY=$gw 
DNS1=$dns1
DNS2=$dns2
DNS3=$dns3
SEARCH=$domain
ONBOOT=yes
#DEVICETYPE=ovs
#TYPE=OVSBridge
#BOOTPROTO=static
#NETMASK=255.255.255.0 
EOF
}

ovs(){ #open vswitch
ovs-vsctl add-port br-ex $device; service network restart
}

public_net(){
echo check if the public network exists
neutron net-show public > /dev/null 2>&1
if ! [ $? -eq 0 ]
then
	echo create the public net
	neutron net-create --tenant-id admin $PublicNet --router:external=True
fi
}

public_subnet(){
echo check if the public subnet exists
neutron subnet-show public_subnet > /dev/null 2>&1
if ! [ $? -eq 0 ]
then
	echo create the public subnet
	#neutron subnet-create --name $PublicSubNet $PublicNet $vlan.0/24
	neutron subnet-create --tenant-id admin --allocation-pool start=$start,end=$end --gateway=$gw --disable-dhcp --name $PublicSubNet $PublicNet $vlan.0/24
fi
}

public_router(){
echo check if the router1 exists
neutron router-show router1 > /dev/null 2>&1 #assuming our router isnt there
if ! [ $? -eq 0 ]
then
	echo create the public router
	neutron router-create PublicRouter
	neutron router-gateway-set PublicRouter $PublicNet
fi
}

public_floatingip(){
neutron floatingip-create $PublicNet
}

public_network(){
public_net
public_subnet
public_router
public_floatingip
}

###MAIN
check
device_primary
device_bridge
ovs
public_network

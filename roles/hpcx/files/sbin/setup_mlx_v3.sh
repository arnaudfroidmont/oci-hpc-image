#!/bin/bash
# switch must be setup with ETH flowcontrol RX enabled
PATH=/bin:/sbin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin:
if [ `id -u` != 0 ]
then
	echo $0: must run as root
	exit 1
fi
if [ $# -ne 3 ]
then
	echo $0: usage: $0: interface mlx5 port
	exit 1
fi

#
# set to "ETH" if you want to use ETH flow control, set to "PFC" if you want to use PFC.
# you must use one or the other, not both.
#
# FLOWCTL_TYPE="ETH"
FLOWCTL_TYPE="PFC"

#
# interface name
#
INTF=$1
#
# mlx5 name
#
MLX5=$2
#
# port number
#
PORT=$3

#
# this PCIE address should not be hardcoded, but it's verified by the installer
#
MLX5_PCIE_0=0000:5e:00.0
MLX5_PCIE_1=0000:5e:00.1

#
# RDMA packets are 4096 bytes, add a bit more for IPv4 headers
# https://community.mellanox.com/docs/DOC-1447
#
INTF_MTU=4220
#
#
#
echo $0: INTF=$INTF, MLX5=$MLX5, PORT=$PORT, MLX5_PCIE=$MLX5_PCIE_0/$MLX5_PCIE_1": setup with $FLOWCTL_TYPE flow control: " `date`
#
# set DSCP to 26 and ECN to 0x1 = (26 << 2) | 0x1 = 105
# https://community.mellanox.com/docs/DOC-2882
#
DSCP_IP_VALUE=00
DSCP_RDMA_VALUE=26
DSCP_CNP_VALUE=46
RDMA_DSCP_ECN_TOS_VALUE=105
DSCP_IP_TC=0
DSCP_RDMA_TC=5
DSCP_CNP_TC=6

IP_HPC=`/usr/sbin/ifconfig $INTF | grep "inet " | awk '{ print $2; }'`
if [ "$IP_HPC" == "" ]
then
    echo $0: interface $INTF does not have an IP address
    exit 1
fi
 
# for whatever reason the driver doesn't let setting autoneg to on
# turn off ETH flow control
if [ "$FLOWCTL_TYPE" == "PFC" ]
then
	echo $0: FLOWCTL_TYPE = $FLOWCTL_TYPE, disabling ETH flow control.
	ethtool -A $INTF autoneg off rx off tx off
else
	echo $0: FLOWCTL_TYPE = $FLOWCTL_TYPE, enabling ETH flow control.
	ethtool -A $INTF autoneg off rx on tx on
fi
ethtool -a $INTF
 
echo $0: configuring interface $INTF at $IP_HPC with mtu $INTF_MTU
#ifconfig $INTF up
#ifconfig $INTF $IP_HPC
ifconfig $INTF mtu $INTF_MTU

set_dscp_to_prio() {
	local __dscp=$1
	local __prio=$2
	echo $0: set DSCP $__dscp to PRIO $__prio
	echo $0: mlnx_qos -i $INTF --dscp2prio set,$__dscp,$__prio
	mlnx_qos -i $INTF --dscp2prio set,$__dscp,$__prio
}

# default Mellanox DSCP values
#	prio:0 dscp:07,06,05,04,03,02,01,00,
#	prio:1 dscp:15,14,13,12,11,10,09,08,
#	prio:2 dscp:23,22,21,20,19,18,17,16,
#	prio:3 dscp:31,30,29,28,27,26,25,24,
#	prio:4 dscp:39,38,37,36,35,34,33,32,
#	prio:5 dscp:47,46,45,44,43,42,41,40,
#	prio:6 dscp:55,54,53,52,51,50,49,48,
#	prio:7 dscp:63,62,61,60,59,58,57,56,
MLNX_DSCP="07 06 05 04 03 02 01 00 \
		15 14 13 12 11 10 09 08 \
		23 22 21 20 19 18 17 16 \
		31 30 29 28 27 26 25 24 \
		39 38 37 36 35 34 33 32 \
		47 46 45 44 43 42 41 40 \
		55 54 53 52 51 50 49 48 \
		63 62 61 60 59 58 57 56"
purge_dscp() {
	for __dscp in $MLNX_DSCP
	do
		#echo __dscp = $__dscp
		__dscp_is_set=`mlnx_qos -i $INTF | fgrep 'prio:' | fgrep $__dscp`
		if [ "$__dscp_is_set" != "" ]
		then
			if [ $__dscp == $DSCP_IP_VALUE ]
			then
				echo $0: ignoring DSCP_IP_VALUE $__dscp
				continue
			fi
			if [ $__dscp == $DSCP_RDMA_VALUE ]
			then
				echo $0: ignoring DSCP_RDMA_VALUE $__dscp
				continue
			fi
			if [ $__dscp == $DSCP_CNP_VALUE ]
			then
				echo $0: ignoring DSCP_CNP_VALUE $__dscp
				continue
			fi
			#echo __dscp_is_set = $__dscp_is_set
			__prio=`echo $__dscp_is_set | sed -e 's/:/ /' | awk ' { print $2; } '`
			#echo __prio = $__prio
			#echo purge $__dscp at $__prio
			#echo mlnx_qos -i $INTF --dscp2prio del,$__dscp,$__prio
			echo $0: purging unused DSCP labels: mlnx_qos -i $INTF --dscp2prio del,$__dscp,$__prio
			mlnx_qos -i $INTF --dscp2prio del,$__dscp,$__prio > /dev/null 2>&1
		fi
	done
}
 
 
#
# tell NIC to trust DSCP.
#
echo $0: trusting DSCP
mlnx_qos -i $INTF --trust dscp 2>&1 > /dev/null

# purse all DSCP values except the ones we want
purge_dscp

echo $0: set_dscp_to_prio DSCP=$DSCP_IP_VALUE PRIO=$DSCP_IP_TC
set_dscp_to_prio $DSCP_IP_VALUE $DSCP_IP_TC 2>&1 > /dev/null
echo $0: set_dscp_to_prio DSCP=$DSCP_RDMA_VALUE PRIO=$DSCP_RDMA_TC
set_dscp_to_prio $DSCP_RDMA_VALUE $DSCP_RDMA_TC 2>&1 > /dev/null
echo $0: set_dscp_to_prio DSCP=$DSCP_CNP_VALUE PRIO=$DSCP_CNP_TC
set_dscp_to_prio $DSCP_CNP_VALUE $DSCP_CNP_TC 2>&1 > /dev/null

#FLOWCTL_TYPE="ETH"
#FLOWCTL_TYPE="PFC"
if [ $FLOWCTL_TYPE == "PFC" ]
then
	## turn on PFC for RDMA only. RDMA is DSCP 26, hence MLNX prio 5
	echo $0: FLOWCTL_TYPE = $FLOWCTL_TYPE, enabling FPC for traffic class 5 '(RDMA DATA)'
	mlnx_qos -i $INTF --pfc 0,0,0,0,0,1,0,0 > /dev/null 2>&1
else
	echo $0: FLOWCTL_TYPE = $FLOWCTL_TYPE, disabling FPC
	mlnx_qos -i $INTF --pfc 0,0,0,0,0,0,0,0 > /dev/null 2>&1
fi

echo $0: setup 1:1 mapping prio queue to TC
## map priority queue to traffic class 1:1 (defaults has 0 and 1 swapped)
mlnx_qos -i $INTF -p 0,1,2,3,4,5,6,7 > /dev/null 2>&1

echo $0: QoS settings:
mlnx_qos -i $INTF
echo ''

#
# same as above, set traffic class
# https://community.mellanox.com/docs/DOC-2883
#
# this no longer exists in Oracle RDMA
#
if [ -f /sys/class/infiniband/$MLX5/tc/1/traffic_class ]
then
	echo $RDMA_DSCP_ECN_TOS_VALUE > /sys/class/infiniband/$MLX5/tc/1/traffic_class
	echo $0: RDMA_DSCP_ECN_TOS_VALUE = `cat /sys/class/infiniband/$MLX5/tc/1/traffic_class`
else
	echo $0: /sys/class/infiniband/$MLX5/tc/1/traffic_class does not exist: not setting TOS $RDMA_DSCP_ECN_TOS_VALUE in /sys/class/infiniband/$MLX5/tc/1/traffic_class
fi

#
# set RoCE v2
# see https://hpcadvisorycouncil.atlassian.net/wiki/spaces/HPCWORKS/pages/156237831/How+to+set+up+IntelMPI+over+RoCEv2
#
cma_roce_mode -d $MLX5 -p 1 -m 2
echo $0: ROCE_MODE = `cma_roce_mode -d $MLX5 -p 1`

#
# set RoCE TOS
#
cma_roce_tos -d $MLX5 -t $RDMA_DSCP_ECN_TOS_VALUE
echo $0: ROCE_TOS = `cma_roce_tos -d $MLX5`

#
# setup ECN on IP stack
#
sysctl -w net.ipv4.tcp_ecn=1
echo $0: IPV4 TCP_ECN = `sysctl net.ipv4.tcp_ecn`

#
# setup ecn on nic: https://community.mellanox.com/docs/DOC-2521
#

#
# Set DSCP and PRIO for L2
#
if [ -f /sys/class/net/$INTF/ecn/roce_np/cnp_802p_prio ]
then
	echo $DSCP_CNP_TC > /sys/class/net/$INTF/ecn/roce_np/cnp_802p_prio
	echo $0: L2 CNP TC: `cat /sys/class/net/$INTF/ecn/roce_np/cnp_802p_prio`
	echo $DSCP_CNP_VALUE > /sys/class/net/$INTF/ecn/roce_np/cnp_dscp
	echo $0: L2 CNP DSCP: `cat /sys/class/net/$INTF/ecn/roce_np/cnp_dscp`
else
	echo $0: /sys/class entries for L2 CNP TC and DSCP do not exist, skipping: /sys/class/net/$INTF/ecn/roce_np/cnp_802p_prio
fi

#
# Set DSCP and PRIO for L3
#
for pci_addr in $MLX5_PCIE_0 $MLX5_PCIE_1
do
	echo $DSCP_CNP_TC > /sys/kernel/debug/mlx5/$pci_addr/cc_params/np_cnp_prio
	echo $0: L3 CNP PRIO $pci_addr: `cat /sys/kernel/debug/mlx5/$pci_addr/cc_params/np_cnp_prio`
	echo $DSCP_CNP_VALUE > /sys/kernel/debug/mlx5/$pci_addr/cc_params/np_cnp_dscp
	echo $0: L3 CNP DSCP $pci_addr: `cat /sys/kernel/debug/mlx5/$pci_addr/cc_params/np_cnp_dscp`
done
 
echo $0: done INTF=$INTF, MLX5=$MLX5, PORT=$PORT, MLX5_PCIE=$MLX5_PCIE_0/$MLX5_PCIE_1: setup with $FLOWCTL_TYPE flow control: `date`
exit 0

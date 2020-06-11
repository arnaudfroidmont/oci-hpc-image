#!/bin/bash

if [ `id -u` -ne 0 ]
then
	echo $0: must run as root.
	exit 1
fi

PATH=/bin:/sbin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin:

# hardcoded
INTF=enp94s0f0
PCI_ADDR_0=0000:5e:00.0
PCI_ADDR_1=0000:5e:00.0
MLX5=mlx5_0
PORT=1
FLOWCTL_TYPE="PFC"

echo INTF=$INTF, MLX5=$MLX5, PORT=$PORT, PCI_ADDR_0=$PCI_ADDR_0, PCI_ADDR_1=$PCI_ADDR_1, FLOWCTL_TYPE=$FLOWCTL_TYPE

show_proc() {
	echo $1 = `cat $1`
}

ifconfig $INTF
mst start
mstflint -d $PCI_ADDR_0 query
mstconfig -d $PCI_ADDR_0 query
ethtool -a $INTF
mlnx_qos -i $INTF -a
echo ROCE_MODE = `cma_roce_mode -d $MLX5 -p $PORT`
echo ROCE_TOS = `cma_roce_tos -d $MLX5 -p $PORT`
show_proc /sys/class/infiniband/$MLX5/node_type 
show_proc /sys/class/infiniband/$MLX5/node_desc
show_proc /sys/class/infiniband/$MLX5/hca_type
show_proc /sys/class/infiniband/$MLX5/fw_pages 
show_proc /sys/class/infiniband/$MLX5/fw_ver 
show_proc /sys/class/infiniband/$MLX5/board_id 
show_proc /sys/class/infiniband/$MLX5/ports/$PORT/rate
show_proc /sys/class/infiniband/$MLX5/ports/$PORT/link_layer 
show_proc /sys/class/infiniband/$MLX5/ports/$PORT/sm_lid 
show_proc /sys/class/infiniband/$MLX5/ports/$PORT/sm_sl
show_proc /sys/class/infiniband/$MLX5/ports/$PORT/state
show_proc /sys/class/net/$INTF/dev_id
show_proc /sys/class/net/$INTF/dev_port
show_proc /sys/class/net/$INTF/duplex
show_proc /sys/class/net/$INTF/flags 
show_proc /sys/class/net/$INTF/ifalias 
show_proc /sys/class/net/$INTF/ifindex 
show_proc /sys/class/net/$INTF/link_mode 
show_proc /sys/class/net/$INTF/mtu 
show_proc /sys/class/net/$INTF/name_assign_type 
show_proc /sys/class/net/$INTF/netdev_group 
show_proc /sys/class/net/$INTF/operstate 
show_proc /sys/class/net/$INTF/speed 
show_proc /sys/class/net/$INTF/tx_queue_len 
echo RDMA_DSCP_ECN_TOS_VALUE = `cat /sys/class/infiniband/$MLX5/tc/1/traffic_class`
echo IPV4_TCP_ECN = `sysctl net.ipv4.tcp_ecn`
echo L2 CNP TC = `cat /sys/class/net/$INTF/ecn/roce_np/cnp_802p_prio`
echo L2 CNP DSCP = `cat /sys/class/net/$INTF/ecn/roce_np/cnp_dscp`
show_proc /sys/class/net/$INTF/ecn/roce_np/min_time_between_cnps 
show_proc /sys/class/net/$INTF/ecn/roce_np/enable/0 
show_proc /sys/class/net/$INTF/ecn/roce_np/enable/1
show_proc /sys/class/net/$INTF/ecn/roce_np/enable/2
show_proc /sys/class/net/$INTF/ecn/roce_np/enable/3
show_proc /sys/class/net/$INTF/ecn/roce_np/enable/4
show_proc /sys/class/net/$INTF/ecn/roce_np/enable/5
show_proc /sys/class/net/$INTF/ecn/roce_np/enable/6
show_proc /sys/class/net/$INTF/ecn/roce_np/enable/7
for pci_addr in $PCI_ADDR_0 $PCI_ADDR_1
do
	echo L3 CNP PRIO $pci_addr: `cat /sys/kernel/debug/mlx5/$pci_addr/cc_params/np_cnp_prio`
	echo L3 CNP PRIO MODE $pci_addr: `cat /sys/kernel/debug/mlx5/$pci_addr/cc_params/np_cnp_prio_mode`
	echo L3 CNP DSCP $pci_addr: `cat /sys/kernel/debug/mlx5/$pci_addr/cc_params/np_cnp_dscp`
done

exit 0

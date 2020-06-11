#!/bin/bash
period="$1"
if [ "$2" != "" ]
then
	MLX_DEV="$2"
else
	MLX_DEV=mlx5_0
fi
DEV_PORT=`ibdev2netdev | grep $MLX_DEV | awk '{ print $3; }'`
ETH_DEV=`ibdev2netdev | grep $MLX_DEV | awk '{ print $5; }'`
#echo MLX_DEV=$MLX_DEV, DEV_PORT=$DEV_PORT, ETH_DEV=$ETH_DEV
sw_path=/sys/class/infiniband/$MLX_DEV/ports/$DEV_PORT/counters
#echo sw_path=$sw_path
if [ "$period" == "" ]
then
	period=5
fi
prev_recv_data=0
prev_recv_packets=0
prev_xmit_data=0
prev_xmit_packets=0
first=1
while true
do
	dump_mlx_counters_port_rcv_data=`cat $sw_path"/port_rcv_data"`
	dump_mlx_counters_port_rcv_packets=`cat $sw_path"/port_rcv_packets"`
	dump_mlx_counters_port_xmit_data=`cat $sw_path"/port_xmit_data"`
	dump_mlx_counters_port_xmit_packets=`cat $sw_path"/port_xmit_packets"`
	#dump_mlx_counters_port_rcv_data=27483160224
	#dump_mlx_counters_port_rcv_packets=151781012
	#dump_mlx_counters_port_xmit_data=44559372836
	#dump_mlx_counters_port_xmit_packets=166930076
	if [ $first -eq 0 ]
	then
		#dump_mlx_counters_port_rcv_data=27483160224
		#dump_mlx_counters_port_rcv_packets=151781012
		#dump_mlx_counters_port_xmit_data=44559372836
		#dump_mlx_counters_port_xmit_packets=166930076
		curr_recv_data=$(($dump_mlx_counters_port_rcv_data - $prev_recv_data))
		curr_recv_packets=$(($dump_mlx_counters_port_rcv_packets - $prev_recv_packets))
		curr_xmit_data=$(($dump_mlx_counters_port_xmit_data - $prev_xmit_data))
		curr_xmit_packets=$(($dump_mlx_counters_port_xmit_packets - $prev_xmit_packets))
		echo `date`: recv_data=$curr_recv_data, recv_packets=$curr_recv_packets, xmit_data=$curr_xmit_data, xmit_packets=$curr_xmit_packets
	fi
	prev_recv_data=$dump_mlx_counters_port_rcv_data
	prev_recv_packets=$dump_mlx_counters_port_rcv_packets
	prev_xmit_data=$dump_mlx_counters_port_xmit_data
	prev_xmit_packets=$dump_mlx_counters_port_xmit_packets
	sleep $period
	first=0
done

#!/bin/bash
PATH=/bin:/sbin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin:/opt/oci-hpc/bin
#
# FIXME: HACK WARNING:
# either deprecate EXADATA FW and get rid of interface renaming, or change this tool to accept port numer as well, or interface name.
# right now it only works because we just grep for Up interfaces.
#
# arg1: mlx5_0 or mlx5_1
case $# in
	0)
		MLX_DEV="mlx5_0"
		;;
	1)
		MLX_DEV="$1"
		;;
	*)
		echo $0: usage: $0 '[mlx5_0|mlx5_1]'
		exit 1
		;;
esac
case "$MLX_DEV" in
"mlx5_0"|"mlx5_1")
	;;
*)
	echo $0: usage: $0 '[mlx5_0|mlx5_1]'
	exit 1
esac
DEV_PORT=`ibdev2netdev | grep Up | grep $MLX_DEV | awk '{ print $3; }'`
ETH_DEV=`ibdev2netdev | grep Up | grep $MLX_DEV | awk '{ print $5; }'`
if [ "$ETH_DEV" == "" ]
then
	echo $0: ERROR: invalid MLX_DEV=$MLX_DEV
	exit 1
fi
#
echo '#' $0: MLX_DEV=$MLX_DEV, DEV_PORT=$DEV_PORT, ETH_DEV=$ETH_DEV
#
# hw_counters with OFED 4.4.2 and MLX firmware 16.23.10xx
#
# req_remote_invalid_request  resp_cqe_error
# duplicate_request           resp_cqe_flush_error
# implied_nak_seq_err         resp_local_length_error
# lifespan                    resp_remote_access_errors
# local_ack_timeout_err       rnr_nak_retry_err
# np_cnp_sent                 rp_cnp_handled
# np_ecn_marked_roce_packets  rp_cnp_ignored
# out_of_buffer               rx_atomic_requests
# out_of_sequence             rx_dct_connect
# packet_seq_err              rx_icrc_encapsulated
# req_cqe_error               rx_read_requests
# req_cqe_flush_error         rx_write_requests
# req_remote_access_errors
#
hw_path="/sys/class/infiniband/$MLX_DEV/ports/$DEV_PORT/hw_counters"
#
# sw counters with OFED 4.4.2 and MLX firmware 16.23.10xx
#
# port_rcv_remote_physical_errors  port_rcv_switch_relay_errors
# excessive_buffer_overrun_errors  port_xmit_constraint_errors
# link_downed                      port_xmit_data
# link_error_recovery              port_xmit_discards
# local_link_integrity_errors      port_xmit_packets
# multicast_rcv_packets            port_xmit_wait
# multicast_xmit_packets           symbol_error
# port_rcv_constraint_errors       unicast_rcv_packets
# port_rcv_data                    unicast_xmit_packets
# port_rcv_errors                  VL15_dropped
# port_rcv_packets
sw_path=/sys/class/infiniband/$MLX_DEV/ports/$DEV_PORT/counters

eth_counters=" \
	rx_discards_phy \
"
for f in $hw_path/*
do
	__out=`cat $f`
	__name=`basename $f`
	echo "dump_mlx_counters_"$__name"="$__out
done
for f in $sw_path/*
do
	__out=`cat $f`
	__name=`basename $f`
	echo "dump_mlx_counters_"$__name"="$__out
done
for f in $eth_counters
do
	__out=`ethtool -S $ETH_DEV | fgrep $f | awk '{ print $2; }'`
	echo "dump_mlx_counters_"$f"="$__out
done

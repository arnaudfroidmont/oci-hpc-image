#!/bin/bash

#
# NEVER EXECUTE THIS FILE DIRECTLY. DOING SO COULD LEAD TO CORRUPT AND UNUSABLE MELLANOX CX-5.
# ALWAYS USE /opt/oci-hpc/sbin/mlnx_fw_ctl.sh
#

if [ `id -u` -ne 0 ]
then
	echo $0: must run as root.
	exit 1
fi

# hardcoded
PCI_ADDR="5e:00.0"
FW_IMAGES_DIR="/opt/oci-hpc/mellanox-fw/"
# current FW version
FW_VERSION="16.23.1020"
# current FW configuration
FW_CONFIGURATION_FILE="$FW_IMAGES_DIR/fw-ConnectX5-rel-16_23_1020-configuration.txt"

check_status() {
	local __status=$1; shift
	local __msg=$*
	if [ $__status -ne 0 ]
	then
		echo $0: ERROR: \"$__msg\" failed with status $__status
		exit $__status
	fi
}

mst_start() {
	mst start > /dev/null 2>&1
	__status=$?
	check_status $? "mst start"
}

show() {
	mstflint -d $PCI_ADDR query
	__status=$?
	check_status $? "mstflint query"
	mstconfig -d $PCI_ADDR query
	__status=$?
	check_status $? "mstconfig query"
}

show_h() {
	ibdev2netdev -v
	check_status $? "ibdev2netdev query"
}

show_f() {
	mstflint -d $PCI_ADDR query | grep "FW Version"
	check_status $? "mstflint query"
}

show_s() {
	mstconfig -d $PCI_ADDR query | egrep "CNP_DSCP_P|CNP_802P_PRIO_P|MULTI_PORT_VHCA_EN|PF_LOG_BAR_SIZE|VF_LOG_BAR_SIZE|SRIOV_EN|NUM_OF_VFS" | sort
	check_status $? "mstflint query"
}

set_defaults() {
	#
	mstflint -d $PCI_ADDR query
	__status=$?
	check_status $? "mstflint query"
	#
	echo $0: applying card defaults =============================
	mstconfig -y -d $PCI_ADDR reset
	__status=$?
	check_status $? "mstconfig reset"
	#
	echo $0: applying Mellanox defaults =============================
	mstconfig -y -d $PCI_ADDR set \
		CNP_DSCP_P1=46 CNP_802P_PRIO_P1=6 \
		CNP_DSCP_P2=46 CNP_802P_PRIO_P2=6 \
		MULTI_PORT_VHCA_EN=0 \
		PF_LOG_BAR_SIZE=5 VF_LOG_BAR_SIZE=1 \
		SRIOV_EN=0 NUM_OF_VFS=0
	__status=$?
	check_status $? "mstconfig set"
	echo $0: resetting CX-5 hardware, please wait =============================
	mlxfwreset -y -d $PCI_ADDR -l 3 reset
	__status=$?
	check_status $? "mlxfwreset"
}

check_update_defaults() {
	#
	# FIXME: need to check FW version once we support more than one FW version
	#
	echo $0: checking defaults for FW $FW_VERSION =============================
	echo $0: WARNING: TO AVOID POSSIBLE HARDWARE CORRUPTION, DO NOT INTERRUPT THIS COMMAND.
	__curr_settings_file=/tmp/mlnx_settings.$$.txt
	show_s > $__curr_settings_file 2>&1
	cmp $FW_CONFIGURATION_FILE $__curr_settings_file
	__status=$?
	if [ $__status == 0 ]
	then
		/bin/rm -f $__curr_settings_file
		echo $0: firmware configuration FW $FW_VERSION has correct defaults =============================
		show_s
	else
		echo $0: firmware configuration FW $FW_VERSION does not match defaults, reconfiguring =============================
		diff $FW_CONFIGURATION_FILE $__curr_settings_file
		/bin/rm -f $__curr_settings_file
		set_defaults
	fi
}

# on the first ifup event, the adapter status will shown as down, as we need to be ok with both (Up) and (down) for mlx5_0
check_hardware_status() {
	local __name=$1
	local __up=$2
	#
	# ibdev2netdev -v 
	# 0000:5e:00.0 mlx5_0 (MT4121 - 7359059    ) CX556A - ConnectX-5 QSFP28 fw 16.23.1020 port 1 (ACTIVE) ==> enp94s0f0 (Up)
	# 0000:5e:00.1 mlx5_1 (MT4121 - 7359059    ) CX556A - ConnectX-5 QSFP28 fw 16.23.1020 port 1 (DOWN  ) ==> enp94s0f1 (Down)
	#
	# ibdev2netdev -v | sed -e 's/(//g' -e 's/)//g' | grep mlx5_0 | awk '{print $8;}'
	# ConnectX-5
	# ibdev2netdev -v | sed -e 's/(//g' -e 's/)//g' | grep mlx5_0 | awk '{print $14;}'
	# ACTIVE
	#
	local __adapter_name=`ibdev2netdev -v | sed -e 's/(//g' -e 's/)//g' | grep $__name | awk '{print $8;}'`
	check_status $? "ibdev2netdev query"
	case "$__adapter_name" in
	"ConnectX-5")
		echo $0: hardware name $__adapter_name for $__name adapter is correct =============================
		;;
	*)
		echo $0: hardware name $__adapter_name for $__name adapter is incorrect =============================
		exit 1
		;;
	esac
	local __adapter_status=`ibdev2netdev -v | sed -e 's/(//g' -e 's/)//g' | grep $__name | awk '{print $14;}'`
	check_status $? "ibdev2netdev query"
	case "$__adapter_status" in
	"ACTIVE")
		if [ "$__up" == "true" ]
		then
			echo $0: hardware status $__adapter_status for $__name adapter is correct =============================
		else
			echo $0: hardware status $__adapter_status for $__name adapter is incorrect, should be DOWN =============================
		fi
		;;
	"DOWN")
		echo $0: hardware status $__adapter_status for $__name adapter is correct =============================
		;;
	*)
		echo $0: hardware status $__adapter_status for $__name adapter is incorrect =============================
		exit 1
		;;
	esac
}

#
# main
#

mst_start

command="$1"
case $command in
set_defaults)
	echo $0: setting Mellanox defaults =============================
	set_defaults
	exit 0
	;;
show)
	echo $0: query settings =============================
	show
	exit 0
	;;
check_update_defaults)
	check_update_defaults
	exit 0
	;;
check_hardware)
	check_hardware_status mlx5_0 true
	check_hardware_status mlx5_1 false
	;;
s)
	show_h
	show_f
	show_s
	exit 0
	;;
*)
	echo $0: usage: 'set_defaults|check_update_defaults|check_hardware|show|s'
	exit 1
	;;
esac

#!/bin/bash

#
# WARNING: do not use this tool on virtual machine instances.
# WARNING: only use this tool on bare metal instances.
#
# WARNING: you, the end user are responsible for the use of this tool.
#
# https://access.redhat.com/articles/3311301
#

if [ `id -u` -ne 0 ]
then
	echo $0: must run as root
	exit 1
fi

KDBGX86=/sys/kernel/debug/x86/
IBRS_ENABLED=$KDBGX86/ibrs_enabled
RETPOLINE_ENABLED=$KDBGX86/retpoline_enabled
if [ ! -f $RETPOLINE_ENABLED ]
then
	RETPOLINE_ENABLED=$KDBGX86/retp_enabled
fi
if [ ! -f $RETPOLINE_ENABLED ]
then
	RETPOLINE_ENABLED=$KDBGX86/retpoline_fallback
fi
IBPB_ENABLED=$KDBGX86/ibpb_enabled

# Common Warning MSG
WARNING_MSG1="$0: WARNING: "'This is not the security default for Spectre/Meltdown mitigation. See the following documents for further information:'
WARNING_MSG2='https://support.oracle.com/knowledge/Oracle%20Linux%20and%20Virtualization/2471704_1.html'
WARNING_MSG3='https://mosemp.us.oracle.com/epmos/faces/DocumentDisplay?id=2471704.1'
WARNING_MSG4='https://access.redhat.com/articles/3311301'
WARNING_MSG5='https://software.intel.com/security-software-guidance/'
WARNING_MSG6='https://software.intel.com/security-software-guidance/api-app/sites/default/files/Retpoline-A-Branch-Target-Injection-Mitigation.pdf'

do_warning="no"

warnings_if_needed() {
	if [ "$do_warning" == "yes" ]
	then
		echo $WARNING_MSG1
		echo $WARNING_MSG2
		echo $WARNING_MSG3
		echo $WARNING_MSG4
		echo $WARNING_MSG5
		echo $WARNING_MSG6
	fi
}

set_ibrs() {
	echo "$1" > $IBRS_ENABLED
	if [ "$1" == "0" ]
	then
		echo $0: WARNING: IBRS Disabled.
		do_warning="yes"
	fi
}
set_retp() {
	echo "$1" > $RETPOLINE_ENABLED
	if [ "$1" == "1" ]
	then
		if [ `cat $IBRS_ENABLED` -eq 0 ]
		then
			echo $0: WARNING: RETPOLINE Enabled, IBRS Disabled.
			do_warning="yes"
		fi
	else
		if [ `cat $IBRS_ENABLED` -eq 0 ]
		then
			echo $0: WARNING: RETPOLINE and IBRS Disabled.
			do_warning="yes"
		fi
	fi
}
#
# IBPB only applies to virtual machines, not bare metal -- not penalty in disabling it
#
set_ibpb() {
	if [ $1 -eq 0 ]
	then
		# fails on RHEL, so ignore errors
		echo "$1" > $IBPB_ENABLED 2> /dev/null
		# NO NEED TO ISSUE A WARNING FOR BARE METAL MACHINES
		# echo $0: WARNING: IBPB Disabled.
		# do_warning="yes"
	else
		# on some kernels ibpb is set to 2, on others to 1
		# try 2 first, if it fails, try 1
		echo "2" > $IBPB_ENABLED 2> /dev/null
		if [ $? -ne 0 ]
		then
			# fails on RHEL, so ignore errors
			echo "1" > $IBPB_ENABLED 2> /dev/null
		fi
	fi
}

options_given="no"

while [ $# -ne 0 ]
do
	options_given="yes"
	case "$1" in
	ibrs-enable|ibrs=1)
		set_ibrs 1
		;;
	ibrs-disable|ibrs=0)
		set_ibrs 0
		;;
	retp-enable|retp=1)
		set_retp 1
		;;
	retp-disable|retp=0)
		set_retp 0
		;;
	ibpb-enable|ibpb=1)
		set_ibpb 1
		;;
	ibpb-disable|ibpb=0)
		set_ibpb 0
		;;
	# ibrs-prot|default-prot)
	# 	set_ibrs 1
	# 	set_retp 0
	# 	set_ibpb 1
	# 	;;
	# retp-prot)
	# 	set_ibrs 0
	# 	set_retp 1
	# 	set_ibpb 0
	# 	;;
	# no-prot)
	# 	set_ibrs 0
	# 	set_retp 0
	# 	set_ibpb 0
	# 	;;
	'--help'|'-h'|*)
		echo $0: usage:
		echo '         ' 'ibrs-enable|ibrs=1|ibrs-disable|ibrs=0'
		echo '         ' 'retp-enable|retp=1|retp-disable|retp=0'
		echo '         ' 'ibpb-enable|ibpb=1|ibpb-disable|ibpb=0'
		echo ''
		echo '         ' 'NOTE: option order is significant'
		echo ''
		exit 0
		;;
	esac
	shift
done

ibrs_enabled=`cat $IBRS_ENABLED`
retpoline_enabled=`cat $RETPOLINE_ENABLED`
ibpb_enabled=`cat $IBPB_ENABLED`

echo $0: ibrs_enabled=$ibrs_enabled retpoline_enabled=$retpoline_enabled ibpb_enabled=$ibpb_enabled

if [ $options_given == "no" ]
then
	if [ $ibrs_enabled -eq 0 ]
	then
		echo $0: WARNING: IBRS disabled.
		do_warning="yes"
	fi
	if [ \( $retpoline_enabled -eq 0 \) -a \( $ibrs_enabled -eq 0 \) ]
	then
		echo $0: WARNING: both RETPOLINE and IBRS disabled.
		do_warning="yes"
	fi
fi

warnings_if_needed

exit 0

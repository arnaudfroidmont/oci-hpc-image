#!/bin/bash

if [ `id -u` -ne 0 ]
then
	echo $0: must run as root.
	exit 1
fi

PATH="/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin:/opt/oci-hpc/bin:/usr/sbin:/usr/local/sbin:/sbin:"

#
# indirectly execute real code under flock.
# given we are manipulating firmware and hardware, we want this to be serialized to corrupting hardware.
#
trap "" SIGINT
trap "" SIGQUIT
trap "" SIGHUP
trap "" SIGTSTP
trap "" SIGSTOP

flock -x /opt/oci-hpc/sbin/mlnx_fw_ctl.sh bash /opt/oci-hpc/sbin/mlnx_fw_ctl_impl.sh $*
exit $?

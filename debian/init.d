#!/bin/sh
#
# Modified by Francisco José Canedo Dominguez for this package.
#
# Example init.d script with LSB support.
#
# Please read this init.d carefully and modify the sections to
# adjust it to the program you want to run.
#
# Copyright (c) 2007 Javier Fernandez-Sanguino <jfs@debian.org>
#
# This is free software; you may redistribute it and/or modify
# it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2,
# or (at your option) any later version.
#
# This is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License with
# the Debian operating system, in /usr/share/common-licenses/GPL;  if
# not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA 02111-1307 USA
#
### BEGIN INIT INFO
# Provides:          vbox-control
# Required-Start:    $network $local_fs vboxdrv
# Required-Stop:
# Should-Start:      $named
# Should-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Starts VirtualBox instances
# Description:       Starts VirtualBox instances at boot-time.
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

NAME=vbox-control              # Introduce the short server's name here
DESC=vbox-control              # Introduce a short description here
LOGDIR=/var/log/vbox-control  # Log directory to use

. /lib/lsb/init-functions

# Default options, these can be overriden by the information
# at /etc/default/$NAME
DAEMONUSER=vbox
VMS=""
TIMEOUT=60
TYPE="vrdp"
ACTION="$1"

# Include defaults if available
if [ -f /etc/default/$NAME ] ; then
	. /etc/default/$NAME
fi

# Override the configured VMs with the ones specified on the command line
if [ "$#" -gt 1 ]
then
	shift
	VMS="$@"
fi

# Use this if you want the user to explicitly set 'RUN' in
# /etc/default/
if [ "x$RUN" != "xyes" ] ; then
    log_failure_msg "$NAME disabled, please adjust the configuration to your needs "
    log_failure_msg "and then set RUN to 'yes' in /etc/default/$NAME to enable it."
    exit 0
fi

if [ -z "$VMS" ]
then
	log_warning_msg "There are no VMs defined to start or stop; see /etc/default/$NAME"
	log_end_msg 0
	exit 0
fi

# Check that the user exists (if we set a user)
# Does the user exist?
if [ -n "$DAEMONUSER" ] ; then
    if getent passwd | grep -q "^$DAEMONUSER:"; then
        # Obtain the uid and gid
        DAEMONUID=`getent passwd |grep "^$DAEMONUSER:" | awk -F : '{print $3}'`
        DAEMONGID=`getent passwd |grep "^$DAEMONUSER:" | awk -F : '{print $4}'`
    else
        log_failure_msg "The user $DAEMONUSER, required to run $NAME does not exist."
        exit 1
    fi
fi


set -e

start_vm() {
	su - $DAEMONUSER -c "VBoxManage startvm $1 --type $TYPE"
}

stop_vm() {
	su - $DAEMONUSER -c "VBoxManage controlvm $1 acpipowerbutton"
}

kill_vm() {
	su - $DAEMONUSER -c "VBoxManage controlvm $1 poweroff"
}

is_running() {
	su - $DAEMONUSER -c "VBoxManage list runningvms" | grep -q "^\"$1\".*$"
}

wait_for_shutdown() {
	I=0
	while [ "$I" -lt "$TIMEOUT" ]
	do
		I=`expr "$I" + 1`
		log_progress_msg .
		sleep 1
		ANY_RUNNING=FALSE
		for VM in $VMS
		do
			if is_running $VM
			then
				continue 2
			fi
		done

		log_end_msg 0
		exit 0
	done

	log_warning_msg "Failed to stop some VMs"

	for VM in $VMS
	do
		if is_running $VM
		then
			log_warning_msg "VM $VM still running"
		fi
	done

	log_end_msg "One or more VMs still running" 1
	exit 1
}

case "$ACTION" in
  start)
	unset FAILED
	log_daemon_msg "Starting $DESC " "$NAME"
  	for VM in $VMS
	do
	    if is_running $VM
	    then
	    	log_action_msg "VM $VM is already started"
	    else
            	log_action_msg "Starting VM $VM"
		if start_vm $VM
		then
			true
		else
			errcode=$?
            		log_action_msg "Failed to start VM $VM"
			FAILED=TRUE
		fi
	    fi
	done

	if  [ -z "$FAILED" ]
	then
		log_end_msg 0
	else
		log_end_msg $errcode
	fi
	;;
  stop)
	unset FAILED
        log_daemon_msg "Stopping $DESC" "$NAME"
	for VM in $VMS
	do
		if is_running $VM
		then
			if stop_vm $VM
			then
				true
			else
				errcode=$?
				log_action_msg "Failed to stop VM $VM"
				FAILED=TRUE
			fi
		else
			log_action_msg "VM $VM is not running"
		fi
	done

	wait_for_shutdown

	if  [ -z "$FAILED" ]
	then
		log_end_msg 0
	else
		log_end_msg $errcode
	fi
	;;
  force-stop)
	unset FAILED
        log_daemon_msg "Force stopping $DESC" "$NAME"
	for VM in $VMS
	do
		if is_running $VM
		then
			if kill_vm $VM
			then
				true
			else
				errcode=$?
				log_action_msg "Failed to stop VM $VM"
				FAILED=TRUE
			fi
		else
			log_action_msg "VM $VM is not running"
		fi
	done

	wait_for_shutdown

	if  [ -z "$FAILED" ]
	then
		log_end_msg 0
	else
		log_end_msg $errcode
	fi
	;;
  restart|force-reload)
  	$0 stop $VMS
	$0 start $VMS
	;;
  status)
        log_daemon_msg "Checking status of $DESC" "$NAME"
	for VM in $VMS
	do
		if is_running $VM
		then
			log_action_msg "VM $VM is running"
		else
			log_action_msg "VM $VM is NOT running"
		fi
	done
	log_end_msg 0
        ;;
  # Use this if the daemon cannot reload
  reload)
        log_warning_msg "Reloading $NAME daemon: not implemented, as the daemon"
        log_warning_msg "cannot re-read the config file (use restart)."
        ;;

  *)
	N=/etc/init.d/$NAME
	echo "Usage: $N {start|stop|force-stop|restart|force-reload|status} [VM]" >&2
	exit 1
	;;
esac

exit 0

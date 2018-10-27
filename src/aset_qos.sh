#!/bin/bash

#### User configurations

# config file location
#CONFFILE=/etc/aset/qos/qos.conf
CONFFILE=/home/kimsh/QoS/git/aset_qos/conf/qos.conf

# QoS device definitions
NDEV=enp0s8
INGRESS=true

#### End of user configuration



# Ingress device setting
IFBMOD=ifb
IFBDEV=ifb0

if [ $INGRESS == "true" ]; then
	QOSDEV=$IFBDEV
else
	QOSDEV=$NDEV
fi


# Default priorities
PRIO_DEFAULT=7

# configuration file index
#   common component index
CONFIDX_TYPE=0
CONFIDX_ID=1
CONFIDX_TCID=2
#   root component index
CONFIDX_R_LIMIT=3
#   group component index
CONFIDX_G_LLIMIT=3
CONFIDX_G_ULIMIT=4
#   node component index
CONFIDX_N_P_ID=3
CONFIDX_N_P_TCID=4
CONFIDX_N_LLIMIT=5
CONFIDX_N_ULIMIT=6
CONFIDX_N_PROTOCOL=7
CONFIDX_N_SRC_IP=8
CONFIDX_N_SRC_PORT=9
CONFIDX_N_DST_IP=10
CONFIDX_N_DST_PORT=11
CONFIDX_N_PRIO=12


PROTOCOL_TCP=6
PROTOCOL_UDP=17

tcRes=true

function read_conf_file() {
	local counter=0
	while IFS='' read -r line || [[ -n "$line" ]]; do
		conf_lines[$counter]=$line
		#echo "QOS config: $line"
		((counter++))
	done < $CONFFILE
	nlines=$counter
}


#
# Functions to execute TC commands
#

# add root class by tc command
#   tc_add_rootqdisc
function tc_add_rootqdisc() {
	echo tc qdisc add dev $QOSDEV root handle 1: htb default 2
	tc qdisc add dev $QOSDEV root handle 1: htb default 2
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# add root class by tc command
#   tc_add_rootclass <max_bps>
#       class_id is always 1
function tc_add_rootclass() {
	echo tc class add dev $QOSDEV parent 1: classid 1:1 htb rate $1
	tc class add dev $QOSDEV parent 1: classid 1:1 htb rate $1
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# replace root class by tc command
#   tc_replace_rootclass <max_bps>
#       class_id is always 1
function tc_replace_rootclass() {
	echo tc class replace dev $QOSDEV classid 1:1 htb rate $1
	tc class replace dev $QOSDEV classid 1:1 htb rate $1
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# add default node to root class by tc command
#   tc_add_defaultnode <max_bps>
#       class_id is 2
function tc_add_defaultnode() {
	echo tc class add dev $QOSDEV parent 1:1 classid 1:2 htb rate $1 prio $PRIO_DEFAULT
	tc class add dev $QOSDEV parent 1:1 classid 1:2 htb rate $1 prio $PRIO_DEFAULT
	if [ $? != 0 ]; then
		tcRes=false
	fi

	echo tc qdisc add dev $QOSDEV parent 1:2 handle 2: pfifo_fast
	tc qdisc add dev $QOSDEV parent 1:2 handle 2: pfifo_fast
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# replace default node of root class by tc command
#   tc_replace_defaultnode <max_bps>
#       class_id is 2
function tc_replace_defaultnode() {
	echo tc class replace dev $QOSDEV classid 1:2 htb rate $1 prio $PRIO_DEFAULT
	tc class replace dev $QOSDEV classid 1:2 htb rate $1 prio $PRIO_DEFAULT
	if [ $? != 0 ]; then
		tcRes=false
	fi
}




# add a class by tc command
#	tc_add_class $1=<class_id> $2=<parent_id> $3=<min_bps> $4=<max_bps> [$5=<prio>]
function tc_add_class() {
	local __prio=""
	if [ "$5" != "" ]; then
		__prio="prio $5"
	fi
	echo tc class add dev $QOSDEV parent 1:$2 classid 1:$1 htb rate $3 ceil $4 $__prio
	tc class add dev $QOSDEV parent 1:$2 classid 1:$1 htb rate $3 ceil $4 $__prio
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# replace a class by tc command
#	tc_replace_class $1=<class_id> $2=<min_bps> $3=<max_bps> [$4=<prio>]
function tc_replace_class() {
	local __prio=""
	if [ "$4" != "" ]; then
		__prio="prio $4"
	fi
	echo tc class replace dev $QOSDEV  classid 1:$1 htb rate $2 ceil $3 $__prio
	tc class replace dev $QOSDEV classid 1:$1 htb rate $2 ceil $3 $__prio
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# delete class by tc command
#	tc_del_class <tcid>
function tc_del_class() {
	local __classinfo=$(tc class show dev $QOSDEV classid 1:$1)
	if [ "$__classinfo" == "" ]; then
		echo There is no class 1:$1. Already deleted.
		return
	fi

	echo tc class delete dev $QOSDEV classid 1:$1
	tc class delete dev $QOSDEV classid 1:$1
	if [ $? != 0 ]; then
		tcRes=false
	fi
}




# add a filter by tc command
#	tc_add_filter $1=<tcid>
#                 $2=<protocol>
#                 $3=<src_ip> $4=<src_port>
#                 $5=<dst_ip> $6=<dst_port>
function tc_add_filter() {
	local __param=""

	# protocol
	local __protocol=""
	if [ "$2" == "tcp" ]; then
		__protocol=$PROTOCOL_TCP
	elif [ "$2" == "udp" ]; then
		__protocol=$PROTOCOL_UDP
	fi
	if [ "$__protocol" != "" ]; then
		__param="$__param match ip protocol $__protocol 0xff"
	fi

	# src_ip
	if [ "$3" != "0" ]; then
		#__param="$__param match ip src $3/32"
		__param="$__param match ip src $3"
	fi

	# src_port
	if [ "$4" != "0" ]; then
		__param="$__param match ip sport $4 0xffff"
	fi

	# dst_ip
	if [ "$5" != "0" ]; then
		#__param="$__param match ip dst $5/32"
		__param="$__param match ip dst $5"
	fi

	# dst_port
	if [ "$6" != "0" ]; then
		__param="$__param match ip dport $6 0xffff"
	fi

	__param="$__param flowid 1:$1"
	#echo $__param
	echo tc filter add dev $QOSDEV parent 1: prio $1 protocol ip u32 $__param
	tc filter add dev $QOSDEV parent 1: prio $1 protocol ip u32 $__param
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# delete filter by tc command
#	tc_del_filter <tcid>
function tc_del_filter() {
	local __filterinfo=$(tc filter show dev $QOSDEV prio $1)
	if [ "$__filterinfo" == "" ]; then
		echo There is no filter $1. Already deleted.
		return
	fi

	echo tc filter delete dev $QOSDEV prio $1
	tc filter delete dev $QOSDEV prio $1
	if [ $? != 0 ]; then
		tcRes=false
	fi
}




# add pfifo_fast qdisc to the leaf node by tc command
#	tc_add_qdisc_pfifo_fast <tcid>
function tc_add_leafqdisc() {
	echo tc qdisc add dev $QOSDEV parent 1:$1 handle 10:$1 pfifo_fast
	tc qdisc add dev $QOSDEV parent 1:$1 handle $1: pfifo_fast
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# delete leaf qdisc by tc command
#	tc_del_leafqdisc <tcid>
function tc_del_leafqdisc() {
	local __qdiscinfo=$(tc qdisc show dev $QOSDEV | grep -w $1:)
	if [ "$__qdiscinfo" == "" ]; then
		echo There is no qdisc $1:. Already deleted.
		return
	fi

	echo tc qdisc delete dev $QOSDEV handle $1: parent 1:$1
	tc qdisc delete dev $QOSDEV handle $1: parent 1:$1
	if [ $? != 0 ]; then
		tcRes=false
	fi
}




# add root to TC
#	tc_add_root <max_bps>
function tc_add_root() {
	tc_add_rootqdisc
	tc_add_rootclass $1
	tc_add_defaultnode $1
}

# replace root to TC
#	tc_replace_root <max_bps>
function tc_replace_root() {
	tc_replace_rootclass $1
	tc_replace_defaultnode $1
}




# add group to TC
#	tc_add_group <tcid> <min_bps> <max_bps>
function tc_add_group() {
	tc_add_class $1 1 $2 $3
}

# replace group to TC
#	tc_replace_group <tcid> <min_bps> <max_bps>
function tc_replace_group() {
	tc_replace_class $1 $2 $3
}

# delete group by tc command. Delete class
#	tc_del_group <tcid>
function tc_del_group() {
	tc_del_class $1
}




# add a node to TC
#	tc_add_node $1=<tcid> $2=<parent_tcid>
#               $3=<min_bps> $4=<max_bps>
#               $5=<protocol>
#               $6=<src_ip> $7=<src_port>
#               $8=<dst_ip> $9=<dst_port>
#               $10=<prio>
function tc_add_node() {
	tc_add_class $1 $2 $3 $4 ${10}
	tc_add_filter $1 $5 $6 $7 $8 $9
	tc_add_leafqdisc $1
}

# replace a node to TC
#	tc_replace_node $1=<tcid>
#               $2=<min_bps> $3=<max_bps>
#               $4=<protocol>
#               $5=<src_ip> $6=<src_port>
#               $7=<dst_ip> $8=<dst_port>
#               $9=<prio>
function tc_replace_node() {
	tc_replace_class $1 $2 $3 $9
	tc_del_filter $1
	tc_add_filter $1 $4 $5 $6 $7 $8
}

# delete node by tc command. Delete filter and leaf class
#	tc_del_node <tcid>
function tc_del_node() {
	tc_del_leafqdisc $1
	tc_del_filter $1
	tc_del_class $1
}




# initialize qos environment
function init() {
	echo qos initialize

	# initialize ingress virtual device, ifb0
	if [[ $INGRESS == "true" ]]; then
		echo Loading ifb device
		modprobe $IFBMOD
		ifconfig $IFBDEV up

		echo Ingress QoS setting
		echo tc qdisc add dev $NDEV ingress
		tc qdisc add dev $NDEV ingress
		echo tc filter add dev $NDEV parent ffff: u32 match u32 0 0 action mirred egress redirect dev $IFBDEV
		tc filter add dev $NDEV parent ffff: u32 match u32 0 0 action mirred egress redirect dev $IFBDEV
	fi

	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			#echo ... Comment line
			continue;
		fi

		local array=(${line//,/ })
		#echo ... "${array[0]}"
		if [ "${array[$CONFIDX_TYPE]}" = "root" ]; then
			tc_add_root ${array[$CONFIDX_R_LIMIT]}
		elif [ "${array[$CONFIDX_TYPE]}" = "group" ]; then
			tc_add_group ${array[$CONFIDX_TCID]} ${array[$CONFIDX_G_LLIMIT]} ${array[$CONFIDX_G_ULIMIT]} 
		elif [ "${array[$CONFIDX_TYPE]}" = "node" ]; then
			tc_add_node ${array[$CONFIDX_TCID]} ${array[$CONFIDX_N_P_TCID]} \
					${array[$CONFIDX_N_LLIMIT]} ${array[$CONFIDX_N_ULIMIT]} \
					${array[$CONFIDX_N_PROTOCOL]} \
					${array[$CONFIDX_N_SRC_IP]} ${array[$CONFIDX_N_SRC_PORT]} \
					${array[$CONFIDX_N_DST_IP]} ${array[$CONFIDX_N_DST_PORT]} \
					${array[$CONFIDX_N_PRIO]}
		fi
	done
}


# clear all qdiscs, classes, and filters, but not delete configurations
function clear() {
	echo Clearing all TC settings.
	tc qdisc delete dev $QOSDEV root
	if [ $INGRESS == "true" ]; then
		echo Clearing ingress qos device
		tc qdisc delete dev $NDEV ingress
		ifconfig ifb0 down
		rmmod ifb
		echo Finished
	fi
}




# get new tc id
#	read config file and get new tc id
function get_new_tcid() {
	local __tcid=$1
	local __ids=""

	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			continue;
		fi
		local array=(${line//,/ })

		__ids[${array[$CONFIDX_TCID]}]=1
	done

	local counter=3
	until [ "${__ids[$counter]}" != "1" ]; do
		((counter++))
	done

	return $counter
}

# get tcid from group_id or node_id
#	get_tcid <id>
function get_tcid() {
	local __tcid=$2
	local __found=false;

	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			continue;
		fi
		local array=(${line//,/ })
		if [ "${array[$CONFIDX_ID]}" == "$1" ]; then
			__found=true;
			break;
		fi
	done < $CONFFILE

	if [ "$__found" == "false" ]; then
		return 0
	else
		return ${array[$CONFIDX_TCID]}
	fi
}




# make string to store the root info in config file
#	make_root_conf <id> <max_bps>
function make_root_conf() {
	echo "root,$1,1,$2"
}

# add root
#   add_root $1=<root_id> $2=<max_bps>
function add_root() {
	tc_add_root $2
	if [ $tcRes == true ]; then
		echo $(make_root_conf $1 $2) >> $CONFFILE
	fi
}

# replace root
#   replace_root $1=<max_bps>
function replace_root() {
	tc_replace_root $1
	if [ $tcRes != true ]; then
		return
	fi

	local __tmpfile=$(dirname "${CONFFILE}")/.$(basename "${CONFFILE}").tmp$$
	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			echo "$line" >> $__tmpfile
			continue;
		fi
		local array=(${line//,/ })

		# check id of config
		if [ "${array[$CONFIDX_TYPE]}" == "root" ]; then
			echo $(make_root_conf ${array[$CONFIDX_ID]} $1) >> $__tmpfile
		else
			echo "$line" >> $__tmpfile
		fi
	done
	mv -f $__tmpfile $CONFFILE
}




# make string to store the group info in config file
#	make_group_conf <id> <tcid> <min_bps> <max_bps>
function make_group_conf() {
	echo "group,$1,$2,$3,$4"
}

# add new group
#	add_new_group $1=<group_id> $2=<min_bps> $3=<max_bps>
function add_new_group() {
	get_new_tcid
	local __tcid=$?
	echo New ID: $__tcid
	tc_add_group $__tcid $2 $3
	if [ $tcRes == true ]; then
		echo $(make_group_conf $1 $__tcid $2 $3) >> $CONFFILE
	fi
}

# replace group
#	replace_group $1=<group_id> $2=<min_bps> $3=<max_bps>
function replace_group() {
	get_tcid $1
	local __tcid=$?
	if [ "$__tcid" == "0" ]; then
		echo "Cannot find the ID $1"
		return
	fi

	tc_replace_group $__tcid $2 $3
	if [ $tcRes != true ]; then
		return
	fi

	local __tmpfile=$(dirname "${CONFFILE}")/.$(basename "${CONFFILE}").tmp$$
	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			echo "$line" >> $__tmpfile
			continue;
		fi
		local array=(${line//,/ })

		# check id of config
		if [ "${array[$CONFIDX_TYPE]}" == "group" ] && [ "${array[$CONFIDX_ID]}" == "$1" ]; then
			echo $(make_group_conf $1 $__tcid $2 $3) >> $__tmpfile
		else
			echo "$line" >> $__tmpfile
		fi
	done
	mv -f $__tmpfile $CONFFILE
}

# delete group. It delete all child nodes
#	del_group <id>
function del_group() {
	local __tmpfile=$(dirname "${CONFFILE}")/.$(basename "${CONFFILE}").tmp$$
	local __ncounter=0
	local __gcounter=0
	local __gid=0

	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			echo "$line" >> $__tmpfile
			continue;
		fi
		local array=(${line//,/ })

		# check id of config
		if [ "${array[$CONFIDX_TYPE]}" == "group" ] && [ "${array[$CONFIDX_ID]}" == "$1" ]; then
			# will delete this group after delete all child nodes
			((__gcounter++))
			__gid=${array[$CONFIDX_TCID]}
		elif [ "${array[$CONFIDX_TYPE]}" == "node" ] && [ "${array[$CONFIDX_N_P_ID]}" == "$1" ]; then
			# child node to delete
			tc_del_node ${array[$CONFIDX_TCID]}
			((__ncounter++))
		else
			echo "$line" >> $__tmpfile
		fi
	done


	if [ "$__gcounter" != "0" ]; then
		tc_del_group $__gid
	fi

	if [ "$__gcounter" == "0" ] && [ "$__ncounter" == "0" ]; then
		echo "There is no $ID node"
		rm -f $__tmpfile
		return
	fi

	mv -f $__tmpfile $CONFFILE
}




# make string to store the node info in config file
#	make_node_conf $1=<id> $2=<tcid> $3=<parent_id> $4=<parent_tcid>
#                  $5=<min_bps> $6=<max_bps>
#                  $7=<protocol>
#                  $8=<src_ip> $9=<src_port>
#                  $10=<dst_ip> $11=<dst_port>
#                  $12=<prio>
function make_node_conf() {
	echo "node,$1,$2,$3,$4,$5,$6,$7,$8,$9,${10},${11},${12}"
}

# add new node
#	add_new_node $1=<id> $2=<parent_id>
#                $3=<min_bps> $4=<max_bps>
#                $5=<protocol>
#                $6=<src_ip> $7=<src_port>
#                $8=<dst_ip> $9=<dst_port>
#                $10=<prio>
function add_new_node() {
	if [ "$6" == "0" ] && [ "$7" == "0" ] && [ "$8" == "0" ] && [ "$9" == "0" ]; then
		echo Error. All filter values are 0s. One of them must be specified.
		return
	fi

	get_new_tcid
	local __tcid=$?
	echo New ID: $__tcid
	get_tcid $2
	local __parent_tcid=$?
	if [ "$__parent_tcid" == "0" ]; then
		echo "Cannot find the parent ID $2"
		return
	fi
	echo Parent ID: $__parent_tcid

	local __prio=${10}
	if [ "$__prio" == "" ]; then
		__prio=$PRIO_DEFAULT
	fi
	tc_add_node $__tcid $__parent_tcid $3 $4 $5 $6 $7 $8 $9 $__prio
	if [ $tcRes == true ]; then
		echo $(make_node_conf $1 $__tcid $2 $__parent_tcid $3 $4 $5 $6 $7 $8 $9 $__prio) >> $CONFFILE
	fi
}

# replace node
#	replace_node $1=<id>
#                $2=<min_bps> $3=<max_bps>
#                $4=<protocol>
#                $5=<src_ip> $6=<src_port>
#                $7=<dst_ip> $8=<dst_port>
#                $9=<prio>
function replace_node() {
	if [ "$5" == "0" ] && [ "$6" == "0" ] && [ "$7" == "0" ] && [ "$8" == "0" ]; then
		echo Error. All filter values are 0s. One of them must be specified.
		return
	fi

	get_tcid $1
	local __tcid=$?
	if [ "$__tcid" == "0" ]; then
		echo "Cannot find the ID $1"
		return
	fi

	local __prio=$9
	if [ "$__prio" == "" ]; then
		__prio=$PRIO_DEFAULT
	fi
	tc_replace_node $__tcid $2 $3 $4 $5 $6 $7 $8 $__prio
	if [ $tcRes != true ]; then
		return
	fi

	local __tmpfile=$(dirname "${CONFFILE}")/.$(basename "${CONFFILE}").tmp$$
	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			echo "$line" >> $__tmpfile
			continue;
		fi
		local array=(${line//,/ })

		# check id of config
		if [ "${array[$CONFIDX_TYPE]}" == "node" ] && [ "${array[$CONFIDX_ID]}" == "$1" ]; then
			echo $(make_node_conf $1 $__tcid ${array[$CONFIDX_N_P_ID]} ${array[$CONFIDX_N_P_TCID]} $2 $3 $4 $5 $6 $7 $8 $__prio) >> $__tmpfile
		else
			echo "$line" >> $__tmpfile
		fi
	done
	mv -f $__tmpfile $CONFFILE
}

# delete node.
#	del_node <id>
function del_node() {
	local __tmpfile=$(dirname "${CONFFILE}")/.$(basename "${CONFFILE}").tmp$$
	local __counter=0

	for line in "${conf_lines[@]}"; do
		#echo "QOS config: $line"
		if [[ "$line" == "#"* ]]; then
			echo "$line" >> $__tmpfile
			continue;
		fi
		local array=(${line//,/ })

		# check id of config
		if [ "${array[$CONFIDX_ID]}" != "$1" ]; then
			echo "$line" >> $__tmpfile
			continue;
		fi

		# if the id is not node, error
		if [ "${array[$CONFIDX_TYPE]}" != "node" ]; then
			echo "ID $1 is not node, but ${array[$CONFIDX_TYPE]}"
			rm -f $__tmpfile
			exit 1
		fi

		tc_del_node ${array[$CONFIDX_TCID]}
		((__counter++))
	done

	if [ "$__counter" == "0" ]; then
		echo "There is no $ID node"
		rm -f $__tmpfile
		exit 1
	fi

	mv -f $__tmpfile $CONFFILE
}


function list_all() {
	echo "list_all() function is not implemented yet"
}

function list_group() {
	echo "list_group() function is not implemented yet"
}

function list_node() {
	echo "list_node() function is not implemented yet"
}


read_conf_file

case "$1" in
	init)
		init
		;;
	clear)
		clear
		;;
	add)
		shift 1
		case "$1" in
			root)
				shit 1
				add_root $*
				;;
			group)
				shift 1
				add_new_group $*
				;;
			node)
				shift 1
				add_new_node $*
				;;
			*)
				echo "Usage: $0 add root  <id> <uppper_limit>"
				echo "       $0 add group <id> <low_limit> <uppper_limit>"
				echo "       $0 add node  <id> <parent_id> <low_limit> <uppper_limit> <protocol> <src_ip> <src_port> <dst_ip> <dst_port> [<priority>]"
				echo "       If you don't want to specify protocol, src_ip, src_port, dst_ip, dst_port, please write 0"
				echo "       Default priority is $PRIO_DEFAULT when you do not specify priority"
				exit 1
		esac
		;;
	del*)
		shift 1
		case "$1" in
			group)
				shift 1
				del_group $*
				;;
			node)
				shift 1
				del_node $*
				;;
			*)
				echo "Usage: $0 del <id>"
				exit 1
		esac
		;;
	replace)
		shift 1
		case "$1" in
			root)
				shift 1
				replace_root $*
				;;
			group)
				shift 1
				replace_group $*
				;;
			node)
				shift 1
				replace_node $*
				;;
			*)
				echo "Usage: $0 replace root  <uppper_limit>"
				echo "       $0 replace group <id> <low_limit> <uppper_limit>"
				echo "       $0 replace node  <id> <low_limit> <uppper_limit> <protocol> <src_ip> <src_port> <dst_ip> <dst_port> [<priority>]"
				echo "       If you don't want to specify protocol, src_ip, src_port, dst_ip, dst_port, please write 0"
				echo "       Default priority is $PRIO_DEFAULT when you do not specify priority"
				exit 1
		esac
		;;
	list)
		shift 1
		if [ $# -eq 0 ]; then
			list_all
		else
			case "$1" in
				group)
					list_group $*
					;;
				node)
					list_node $*
					;;
				all)
					list_all
					;;
				*)
					echo "Usage: $0 list all"
					echo "       $0 list group [-r] id"
					echo "       $0 list node id"
					exit 1
			esac
					
		fi
		;;
	*)
		echo "Usage: $0 {init|clear|add|delete|list} [paramters]"
		exit 1
esac

if [ $tcRes == false ]; then
	echo Error during executing tc command
	exit 1
fi
exit 0


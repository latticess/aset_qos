#!/bin/bash

CONFFILE=/etc/aset/qos/qos.conf
#CONFFILE=/home/kimsh/QoS/conf/qos.conf
#QOSDEV=enp0s9
QOSDEV=ifb0


# get new group id
#	read config file and get new group id
function get_new_id() {
	local __id=$1
	local __ids=""
	# read config file and add qos configs
	while IFS='' read -r line || [[ -n "$line" ]]; do
		#echo "QOS config: $line"
		if [[ "$line" == "#"* ]]; then
			continue;
		fi
		local array=(${line//,/ })

		__ids[${array[1]}]=1

	done < $CONFFILE

	local counter=2
	until [ "${__ids[$counter]}" != "1" ]
	do
		((counter++))
	done

	eval $__id="'$counter'"
}


# make string to store the group info in config file
#	make_group_conf <id> <min_bps> <max_bps>
function make_group_conf() {
	echo "group,$1,$2,$3"
}


# make string to store the node info in config file
#	make_node_conf <id> <parent_id> <min_bps> <max_bps> <src_ip> <src_port> <dst_ip> <dst_port>
function make_node_conf() {
	echo "node,$1,$2,$3,$4,$5,$6,$7,$8"
}




# initialize qos environment
function init() {
	echo qos initialize

	# initialize ingress virtual device, ifb0
	modprobe ifb
	ifconfig ifb0 up

	# initialize root qdisc
	#tc qdisc add dev $QOSDEV root handle 1: htb
	#tc class add dev $QOSDEV parent 1: classid 1:1 htb rate 100mbit
	echo tc qdisc add dev $QOSDEV root handle 1: htb
	echo tc class add dev $QOSDEV parent 1: classid 1:1 htb rate 100mbit

	# read config file and add qos configs
	while IFS='' read -r line || [[ -n "$line" ]]; do
		echo "QOS config: $line"
		if [[ "$line" == "#"* ]]; then
			echo ... Comment line
			continue;
		fi
		local array=(${line//,/ })
		#echo ... "${array[0]}"
		if [ "${array[0]}" = "group" ]; then
			add_group ${array[1]} ${array[2]} ${array[3]} 
		elif [ "${array[0]}" = "node" ]; then
			add_node ${array[1]} ${array[2]} ${array[3]} ${array[4]} ${array[5]} ${array[6]} ${array[7]} ${array[8]}
		fi
	done < $CONFFILE
}


# add a class by tc command
#	tc_add_class <class_id> <parent_id> <min_bps> <max_bps>
function tc_add_class() {
	#tc class add dev $QOSDEV parent 1:$1 classid 1:$2 htb rate $3 ceil $4 
	echo tc class add dev $QOSDEV parent 1:$2 classid 1:$1 htb rate $3 ceil $4 
}


# add a filter by tc command
#	tc_add_filter <id> <src_ip> <src_port> <dst_ip> <dst_port>
function tc_add_filter() {
	param="prio $1 protocol ip u32"
	if [ "$2" != "0" ]; then
		param="$param match ip src $2/32"
	fi
	if [ "$3" != "0" ]; then
		param="$parm match tcp src $3 0xffff"
	fi
	if [ "$4" != "0" ]; then
		param="$param match ip dst $4/32"
	fi
	if [ "$5" != "0" ]; then
		param="$parm match tcp dst $4 0xffff"
	fi
	param="$param flowid 1:$1"
	#echo $param
	#tc filter add dev $QOSDEV parent 1: prio $1 protocol ip u32 $param
	echo tc filter add dev $QOSDEV parent 1: prio $1 protocol ip u32 $param
}


# delete filter by tc command
#	tc_del_filter <id>
function tc_del_filter() {
	#tc filter delete dev $QOSDEV parent 1: prio $1
	echo tc filter delete dev $QOSDEV prio $1
}


# delete class by tc command
#	tc_del_class <id>
function tc_del_class() {
	#tc class delete dev $QOSDEV classid 1:$1
	echo tc class delete dev $QOSDEV classid 1:$1
}


# delete node by tc command. Delete filter and leaf class
#	tc_del_node <id>
function tc_del_node() {
	tc_del_filter $1
	tc_del_class $1
}


# add group
#	add_group <id> <min_bps> <max_bps>
function add_group() {
	tc_add_class 1 $*
}


# add a node
#	add_node <id> <parent_id> <min_bps> <max_bps> <src_ip> <src_port> <dst_ip> <dst_port>
function add_node() {
	tc_add_class $1 $2 $3 $4
	tc_add_filter $1 $5 $6 $7 $8
}


# add new group
#	add_new_group <min_bps> <max_bps>
function add_new_group() {
	# read file and get a new id
	get_new_id id
	echo New ID: $id
	add_group $id $*
	echo $(make_group_conf $id $*) >> $CONFFILE
}


# add new node
#	add_new_node <id> <parent_id> <min_bps> <max_bps> <src_ip> <src_port> <dst_ip> <dst_port>
function add_new_node() {
	# read file and get a new id
	get_new_id id
	echo New ID: $id
	add_node $id $*
	echo $(make_node_conf $id $*) >> $CONFFILE
}


# delete group. It delete all child nodes
#	del_group <id>
function del_group() {
	local __tmpfile=$(dirname "${CONFFILE}")/.$(basename "${CONFFILE}").tmp$$
	local __ncounter=0
	local __gcounter=0

	# read config file
	while IFS='' read -r line || [[ -n "$line" ]]; do
		#echo "QOS config: $line"
		if [[ "$line" == "#"* ]]; then
			echo "$line" >> $__tmpfile
			continue;
		fi
		local array=(${line//,/ })

		# check id of config
		if [ "${array[0]}" == "group" ] && [ "${array[1]}" == "$1" ]; then
			# will delete this group after delete all child nodes
			((__gcounter++))
		elif [ "${array[0]}" == "node" ] && [ "${array[2]}" == "$1" ]; then
			# child node to delete
			tc_del_node ${array[1]}
			((__ncounter++))
		else
			echo "$line" >> $__tmpfile
		fi
	done < $CONFFILE

	if [ "$__gcounter" != "0" ]; then
		tc_del_class $1
	fi

	if [ "$__gcounter" == "0" ] && [ "$__ncounter" == "0" ]; then
		echo "There is no $ID node"
		rm -f $__tmpfile
		exit 1
	fi

	mv $__tmpfile $CONFFILE
}


# delete node.
#	del_node <id>
function del_node() {
	local __tmpfile=$(dirname "${CONFFILE}")/.$(basename "${CONFFILE}").tmp$$
	local __counter=0

	# read config file
	while IFS='' read -r line || [[ -n "$line" ]]; do
		#echo "QOS config: $line"
		if [[ "$line" == "#"* ]]; then
			echo "$line" >> $__tmpfile
			continue;
		fi
		local array=(${line//,/ })

		# check id of config
		if [ "${array[1]}" != "$1" ]; then
			echo "$line" >> $__tmpfile
			continue;
		fi

		# if the id is not node, error
		if [ "${array[0]}" != "node" ]; then
			echo "ID $1 is not node, ${array[0]}"
			rm -f $__tmpfile
			exit 1
		fi

		tc_del_node $1
		((__counter++))
	done < $CONFFILE

	if [ "$__counter" == "0" ]; then
		echo "There is no $ID node"
		rm -f $__tmpfile
		exit 1
	fi

	mv $__tmpfile $CONFFILE
}


case "$1" in
	init)
		init
		;;
	start)
		start
		;;
	add)
		shift 1
		case "$1" in
			group)
				shift 1
				add_new_group $*
				;;
			node)
				shift 1
				add_new_node $*
				;;
			*)
				echo "Usage: $0 add {group|node}"
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
	*)
		echo "Usage: $0 {init|add}"
		exit 1
esac


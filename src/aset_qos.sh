#!/bin/bash

#CONFFILE=/etc/aset/qos/qos.conf
CONFFILE=/home/kimsh/QoS/git/aset_qos/conf/qos.conf
QOSDEV=enp0s9
#QOSDEV=ifb0


# configuration file index
#   common component index
CONFIDX_TYPE=0
CONFIDX_ID=1
CONFIDX_TCID=2
#   group component index
CONFIDX_G_LLIMIT=3
CONFIDX_G_ULIMIT=4
#   node component index
CONFIDX_N_P_ID=3
CONFIDX_N_P_TCID=4
CONFIDX_N_LLIMIT=5
CONFIDX_N_ULIMIT=6
CONFIDX_N_SRC_IP=7
CONFIDX_N_SRC_PORT=8
CONFIDX_N_DST_IP=9
CONFIDX_N_DST_PORT=10



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

# add a class by tc command
#	tc_add_class <class_id> <parent_id> <min_bps> <max_bps>
function tc_add_class() {
	echo tc class add dev $QOSDEV parent 1:$2 classid 1:$1 htb rate $3 ceil $4 
	tc class add dev $QOSDEV parent 1:$2 classid 1:$1 htb rate $3 ceil $4 
}

# add a filter by tc command
#	tc_add_filter <tcid> <src_ip> <src_port> <dst_ip> <dst_port>
function tc_add_filter() {
	local __param=""
	if [ "$2" != "0" ]; then
		__param="$__param match ip src $2/32"
	fi
	if [ "$3" != "0" ]; then
		__param="$__param match tcp src $3 0xffff"
	fi
	if [ "$4" != "0" ]; then
		__param="$__param match ip dst $4/32"
	fi
	if [ "$5" != "0" ]; then
		__param="$__param match tcp dst $5 0xffff"
	fi
	__param="$__param flowid 1:$1"
	#echo $__param
	echo tc filter add dev $QOSDEV parent 1: prio $1 protocol ip u32 $__param
	tc filter add dev $QOSDEV parent 1: prio $1 protocol ip u32 $__param
}

# add pfifo_fast qdisc to the leaf node by tc command
#	tc_add_qdisc_pfifo_fast <tcid>
function tc_add_leafqdisc() {
	echo tc qdisc add dev $QOSDEV parent 1:$1 handle 10:$1 pfifo_fast
	tc qdisc add dev $QOSDEV parent 1:$1 handle $1: pfifo_fast
}


# delete class by tc command
#	tc_del_class <tcid>
function tc_del_class() {
	echo tc class delete dev $QOSDEV classid 1:$1
	tc class delete dev $QOSDEV classid 1:$1
}

# delete filter by tc command
#	tc_del_filter <tcid>
function tc_del_filter() {
	echo tc filter delete dev $QOSDEV prio $1
	tc filter delete dev $QOSDEV parent 1: prio $1
}

# delete leaf qdisc by tc command
#	tc_del_leafqdisc <tcid>
function tc_del_leafqdisc() {
	tc qdisc delete dev $QOSDEV handle $1: parent 1:$1
}

# add group to TC
#	tc_add_group <tcid> <min_bps> <max_bps>
function tc_add_group() {
	tc_add_class $1 1 $2 $3
}

# add a node to TC
#	tc_add_node <tcid> <parent_tcid> <min_bps> <max_bps> <src_ip> <src_port> <dst_ip> <dst_port>
function tc_add_node() {
	tc_add_class $1 $2 $3 $4
	tc_add_filter $1 $5 $6 $7 $8
	tc_add_leafqdisc $1
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
	#modprobe ifb
	#ifconfig ifb0 up

	# initialize root qdisc
	echo tc qdisc add dev $QOSDEV root handle 1: htb
	tc qdisc add dev $QOSDEV root handle 1: htb
	echo tc class add dev $QOSDEV parent 1: classid 1:1 htb rate 100mbit
	tc class add dev $QOSDEV parent 1: classid 1:1 htb rate 100mbit


	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			#echo ... Comment line
			continue;
		fi

		local array=(${line//,/ })
		#echo ... "${array[0]}"
		if [ "${array[$CONFIDX_TYPE]}" = "group" ]; then
			tc_add_group ${array[$CONFIDX_TCID]} ${array[$CONFIDX_G_LLIMIT]} ${array[$CONFIDX_G_ULIMIT]} 
		elif [ "${array[$CONFIDX_TYPE]}" = "node" ]; then
			tc_add_node ${array[$CONFIDX_TCID]} ${array[$CONFIDX_N_P_TCID]} \
					${array[$CONFIDX_N_LLIMIT]} ${array[$CONFIDX_N_ULIMIT]} \
					${array[$CONFIDX_N_SRC_IP]} ${array[$CONFIDX_N_SRC_PORT]} \
					${array[$CONFIDX_N_DST_IP]} ${array[$CONFIDX_N_DST_PORT]}
		fi

	done
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

	local counter=2
	until [ "${__ids[$counter]}" != "1" ]
	do
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

# make string to store the group info in config file
#	make_group_conf <id> <tcid> <min_bps> <max_bps>
function make_group_conf() {
	echo "group,$1,$2,$3,$4"
}

# make string to store the node info in config file
#	make_node_conf <id> <tcid> <parent_id> <parent_tcid> <min_bps> <max_bps> <src_ip> <src_port> <dst_ip> <dst_port>
function make_node_conf() {
	echo "node,$1,$2,$3,$4,$5,$6,$7,$8,$9,${10}"
}

# add new group
#	add_new_group <group_id> <min_bps> <max_bps>
function add_new_group() {
	get_new_tcid
	tcid=$?
	echo New ID: $tcid
	tc_add_group $tcid $2 $3
	echo $(make_group_conf $1 $tcid $2 $3) >> $CONFFILE
}

# add new node
#	add_new_node <id> <parent_id> <min_bps> <max_bps> <src_ip> <src_port> <dst_ip> <dst_port>
function add_new_node() {
	get_new_tcid
	tcid=$?
	echo New ID: $tcid
	get_tcid $2
	parent_tcid=$?
	if [ "$parent_tcid" == "0" ]; then
		echo "Cannot found the parent ID $2"
		return
	fi

	echo Parent ID: $parent_tcid
	tc_add_node $tcid $parent_tcid $3 $4 $5 $6 $7 $8
	echo $(make_node_conf $1 $tcid $2 $parent_tcid $3 $4 $5 $6 $7 $8) >> $CONFFILE
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
		tc_del_class $__gid
	fi

	if [ "$__gcounter" == "0" ] && [ "$__ncounter" == "0" ]; then
		echo "There is no $ID node"
		rm -f $__tmpfile
		return
	fi

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
				echo "Usage: $0 add group <id> <low_limit> <uppper_limit>"
				echo "       $0 add node <id> <parent_id> <low_limit> <uppper_limit> <src_ip>, <src_port> <dst_ip> <dst_port>"
				echo "       If you don't want to specify src/dst ip/port, please write 0"
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
	list)
		shift 1
		if [ $# -eq 0 ]; then
			list_all
		else
			case "$1" in
				group)
					list_group
					;;
				node)
					list_node
					;;
				all)
					list_all
					;;
				*)
					echo "Usage: $0 list {all|group|node}"
					exit 1
			esac
					
		fi
		;;
	*)
		echo "Usage: $0 {init|add|delete|list}"
		exit 1
esac


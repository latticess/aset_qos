#!/bin/bash

#### User configurations

# config file location
#CONFFILE=/etc/aset/qos/qos.conf
CONFFILE=/home/kimsh/QoS/git/aset_qos/conf/qos3.conf

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
	if [ ! -f $CONFFILE ]; then
		echo Warning!! Config file does not exist.
		return
	fi

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
	local __max_bps=$1

	echo tc class add dev $QOSDEV parent 1: classid 1:1 htb rate $__max_bps
	tc class add dev $QOSDEV parent 1: classid 1:1 htb rate $__max_bps
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# replace root class by tc command
#   tc_replace_rootclass <max_bps>
#       class_id is always 1
function tc_replace_rootclass() {
	local __max_bps=$1

	echo tc class replace dev $QOSDEV classid 1:1 htb rate $__max_bps
	tc class replace dev $QOSDEV classid 1:1 htb rate $__max_bps
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# add default node to root class by tc command
#   tc_add_defaultnode <max_bps>
#       class_id is 2
function tc_add_defaultnode() {
	local __max_bps=$1

	echo tc class add dev $QOSDEV parent 1:1 classid 1:2 htb rate $__max_bps prio $PRIO_DEFAULT
	tc class add dev $QOSDEV parent 1:1 classid 1:2 htb rate $__max_bps prio $PRIO_DEFAULT
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
	local __max_bps=$1

	echo tc class replace dev $QOSDEV classid 1:2 htb rate $__max_bps prio $PRIO_DEFAULT
	tc class replace dev $QOSDEV classid 1:2 htb rate $__max_bps prio $PRIO_DEFAULT
	if [ $? != 0 ]; then
		tcRes=false
	fi
}




# add a class by tc command
#	tc_add_class <class_id> <parent_id> <min_bps> <max_bps> [<prio>]
function tc_add_class() {
	local __class_id=$1
	local __parent_id=$2
	local __min_bps=$3
	local __max_bps=$4
	local __prio=""
	if [ "$5" != "" ]; then
		__prio="prio $5"
	fi

	echo tc class add dev $QOSDEV parent 1:$__parent_id classid 1:$__class_id htb rate $__min_bps ceil $__max_bps $__prio
	tc class add dev $QOSDEV parent 1:$__parent_id classid 1:$__class_id htb rate $__min_bps ceil $__max_bps $__prio
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# replace a class by tc command
#	tc_replace_class <class_id> <min_bps> <max_bps> [<prio>]
function tc_replace_class() {
	local __class_id=$1
	local __min_bps=$2
	local __max_bps=$3
	local __prio=""
	if [ "$4" != "" ]; then
		__prio="prio $4"
	fi

	echo tc class replace dev $QOSDEV  classid 1:$__class_id htb rate $__min_bps ceil $__max_bps $__prio
	tc class replace dev $QOSDEV classid 1:$__class_id htb rate $__min_bps ceil $__max_bps $__prio
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# delete class by tc command
#	tc_del_class <tcid>
function tc_del_class() {
	local __tcid=$1

	local __classinfo=$(tc class show dev $QOSDEV classid 1:$__tcid)
	if [ "$__classinfo" == "" ]; then
		echo Warning!! There is no class 1:$1. Already deleted.
		return
	fi

	echo tc class delete dev $QOSDEV classid 1:$__tcid
	tc class delete dev $QOSDEV classid 1:$__tcid
	if [ $? != 0 ]; then
		tcRes=false
	fi
}




# add a filter by tc command
#	tc_add_filter <tcid> <protocol>
#                 <src_ip> <src_port>
#                 <dst_ip> <dst_port>
function tc_add_filter() {
	local __tcid=$1
	local __protocol=$2
	local __src_ip=$3
	local __src_port=$4
	local __dst_ip=$5
	local __dst_port=$6

	local __param=""

	# protocol
	local __protocol=""
	if [ "$__protocol" == "tcp" ]; then
		__protocol=$PROTOCOL_TCP
	elif [ "$__protocol" == "udp" ]; then
		__protocol=$PROTOCOL_UDP
	fi
	if [ "$__protocol" != "" ]; then
		__param="$__param match ip protocol $__protocol 0xff"
	fi

	# src_ip
	if [ "$__src_ip" != "0" ]; then
		#__param="$__param match ip src $__src_ip/32"
		__param="$__param match ip src $__src_ip"
	fi

	# src_port
	if [ "$__src_port" != "0" ]; then
		__param="$__param match ip sport $__src_port 0xffff"
	fi

	# dst_ip
	if [ "$__dst_ip" != "0" ]; then
		#__param="$__param match ip dst $__dst_ip/32"
		__param="$__param match ip dst $__dst_ip"
	fi

	# dst_port
	if [ "$__dst_port" != "0" ]; then
		__param="$__param match ip dport $__dst_port 0xffff"
	fi

	__param="$__param flowid 1:$__tcid"
	#echo $__param
	echo tc filter add dev $QOSDEV parent 1: prio $__tcid protocol ip u32 $__param
	tc filter add dev $QOSDEV parent 1: prio $__tcid protocol ip u32 $__param
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# delete filter by tc command
#	tc_del_filter <tcid>
function tc_del_filter() {
	local __tcid=$1

	local __filterinfo=$(tc filter show dev $QOSDEV prio $__tcid)
	if [ "$__filterinfo" == "" ]; then
		echo Warning!! There is no filter $__tcid. Already deleted.
		return
	fi

	echo tc filter delete dev $QOSDEV prio $__tcid
	tc filter delete dev $QOSDEV prio $__tcid
	if [ $? != 0 ]; then
		tcRes=false
	fi
}




# add pfifo_fast qdisc to the leaf node by tc command
#	tc_add_qdisc_pfifo_fast <tcid>
function tc_add_leafqdisc() {
	local __tcid=$1

	echo tc qdisc add dev $QOSDEV parent 1:$__tcid handle 10:$__tcid pfifo_fast
	tc qdisc add dev $QOSDEV parent 1:$__tcid handle $__tcid: pfifo_fast
	if [ $? != 0 ]; then
		tcRes=false
	fi
}

# delete leaf qdisc by tc command
#	tc_del_leafqdisc <tcid>
function tc_del_leafqdisc() {
	local __tcid=$1

	local __qdiscinfo=$(tc qdisc show dev $QOSDEV | grep -w $__tcid:)
	if [ "$__qdiscinfo" == "" ]; then
		echo Warning!! There is no qdisc $__tcid:. Already deleted.
		return
	fi

	echo tc qdisc delete dev $QOSDEV handle $__tcid: parent 1:$__tcid
	tc qdisc delete dev $QOSDEV handle $__tcid: parent 1:$__tcid
	if [ $? != 0 ]; then
		tcRes=false
	fi
}




# add root to TC
#	tc_add_root <max_bps>
function tc_add_root() {
	local __max_bps=$1

	tc_add_rootqdisc
	tc_add_rootclass $__max_bps
	tc_add_defaultnode $__max_bps
}

# replace root to TC
#	tc_replace_root <max_bps>
function tc_replace_root() {
	local __max_bps=$1

	tc_replace_rootclass $__max_bps
	tc_replace_defaultnode $__max_bps
}




# add group to TC
#	tc_add_group <tcid> <min_bps> <max_bps>
function tc_add_group() {
	local __tcid=$1
	local __min_bps=$2
	local __max_bps=$3

	tc_add_class $__tcid 1 $__min_bps $__max_bps
}

# replace group to TC
#	tc_replace_group <tcid> <min_bps> <max_bps>
function tc_replace_group() {
	local __tcid=$1
	local __min_bps=$2
	local __max_bps=$3

	tc_replace_class $__tcid $__min_bps $__max_bps
}

# delete group by tc command. Delete class
#	tc_del_group <tcid>
function tc_del_group() {
	local __tcid=$1

	tc_del_class $__tcid
}




# add a node to TC
#	tc_add_node <tcid> <parent_tcid>
#               <min_bps> <max_bps>
#               <protocol>
#               <src_ip> <src_port>
#               <dst_ip> <dst_port>
#               <prio>
function tc_add_node() {
	local __tcid=$1
	local __parent_tcid=$2
	local __min_bps=$3
	local __max_bps=$4
	local __protocol=$5
	local __src_ip=$6
	local __src_port=$7
	local __dst_ip=$8
	local __dst_port=$9
	local __prio=${10}

	tc_add_class $__tcid $__parent_tcid $__min_bps $__max_bps $__prio
	tc_add_filter $__tcid $__protocol $__src_ip $__src_port $__dst_ip $__dst_port
	tc_add_leafqdisc $__tcid
}

# replace a node to TC
#	tc_replace_node <tcid>
#               <min_bps> <max_bps>
#               <protocol>
#               <src_ip> <src_port>
#               <dst_ip> <dst_port>
#               <prio>
function tc_replace_node() {
	local __tcid=$1
	local __min_bps=$2
	local __max_bps=$3
	local __protocol=$4
	local __src_ip=$5
	local __src_port=$6
	local __dst_ip=$7
	local __dst_port=$8
	local __prio=$9

	tc_replace_class $__tcid $__min_bps $__max_bps $__prio
	tc_del_filter $__tcid
	tc_add_filter $__tcid $__protocol $__src_ip $__src_port $__dst_ip $__dst_port
}

# delete node by tc command. Delete filter and leaf class
#	tc_del_node <tcid>
function tc_del_node() {
	local __tcid=$1

	tc_del_leafqdisc $__tcid
	tc_del_filter $__tcid
	tc_del_class $__tcid
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
#	local __tcid=$1
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
	local __id=$1
	local __found=false;

	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			continue;
		fi
		local array=(${line//,/ })
		if [ "${array[$CONFIDX_ID]}" == "$__id" ]; then
			__found=true;
			break;
		fi
	done

	if [ "$__found" == "false" ]; then
		return 0
	else
		return ${array[$CONFIDX_TCID]}
	fi
}




# make string to store the root info in config file
#	make_root_conf <root_id> <max_bps>
function make_root_conf() {
	local __root_id=$1
	local __max_bps=$2

	echo "root,$__root_id,1,$__max_bps"
}

# add root
#   add_root <root_id> <max_bps>
function add_root() {
	local __root_id=$1
	local __max_bps=$2

	# check if params are valid
	param_valid_id_and_exit "$__root_id" "root ID"
	param_valid_rate_and_exit "$__max_bps" "max_limit"

	# check if root already exist
	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			continue;
		fi
		local array=(${line//,/ })
		if [ "${array[$CONFIDX_TYPE]}" == "root" ]; then
			echo "Error!! root node already exists"
			exit 1
		fi
	done

	tc_add_root $__max_bps
	if [ $tcRes == true ]; then
		echo $(make_root_conf $__root_id $__max_bps) >> $CONFFILE
	fi
}

# replace root
#   replace_root <max_bps>
function replace_root() {
	local __max_bps=$1

	# check if params are valid
	param_valid_rate_and_exit "$__max_bps" "max_limit"

	# check if root exists
	local __found=false;
	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			continue;
		fi
		local array=(${line//,/ })
		if [ "${array[$CONFIDX_TYPE]}" == "root" ]; then
			__found=true;
			break;
		fi
	done
	if [ "$__found" == "false" ]; then
		echo Warning!! root node is not defined yet.
		return
	fi


	tc_replace_root $__max_bps
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
			echo $(make_root_conf ${array[$CONFIDX_ID]} $__max_bps) >> $__tmpfile
		else
			echo "$line" >> $__tmpfile
		fi
	done
	mv -f $__tmpfile $CONFFILE
}




# make string to store the group info in config file
#	make_group_conf <group_id> <tcid> <min_bps> <max_bps>
function make_group_conf() {
	local __group_id=$1
	local __tcid=$2
	local __min_bps=$3
	local __max_bps=$4

	echo "group,$__group_id,$__tcid,$__min_bps,$__max_bps"
}

# add new group
#	add_new_group <group_id> <min_bps> <max_bps>
function add_new_group() {
	local __group_id=$1
	local __min_bps=$2
	local __max_bps=$3

	# check if params are valid
	param_valid_id_and_exit "$__group_id" "group ID"
	param_valid_rate_and_exit "$__min_bps" "min_limit"
	param_valid_rate_and_exit "$__max_bps" "max_limit"

	# check if ID is already exist
	get_tcid $__group_id
	if [ "$?" != "0" ]; then
		echo Error!! $__group_id already exists.
		exit 1
	fi

	get_new_tcid
	local __tcid=$?
	echo New ID: $__tcid
	tc_add_group $__tcid $__min_bps $__max_bps
	if [ $tcRes == true ]; then
		echo $(make_group_conf $1 $__tcid $__min_bps $__max_bps) >> $CONFFILE
	fi
}

# replace group
#	replace_group <group_id> <min_bps> <max_bps>
function replace_group() {
	local __group_id=$1
	local __min_bps=$2
	local __max_bps=$3

	# check if params are valid
	param_valid_id_and_exit "$__group_id" "group ID"
	param_valid_rate_and_exit "$__min_bps" "min_limit"
	param_valid_rate_and_exit "$__max_bps" "max_limit"

	get_tcid $__group_id
	local __tcid=$?
	if [ "$__tcid" == "0" ]; then
		echo "Error!! Cannot find the ID $__group_id"
		exit 1
	fi

	tc_replace_group $__tcid $__min_bps $__max_bps
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
		if [ "${array[$CONFIDX_TYPE]}" == "group" ] && [ "${array[$CONFIDX_ID]}" == "$__group_id" ]; then
			echo $(make_group_conf $__group_id $__tcid $__min_bps $__max_bps) >> $__tmpfile
		else
			echo "$line" >> $__tmpfile
		fi
	done
	mv -f $__tmpfile $CONFFILE
}

# delete group. It delete all child nodes
#	del_group <id>
function del_group() {
	local __group_id=$1

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
		if [ "${array[$CONFIDX_TYPE]}" == "group" ] && [ "${array[$CONFIDX_ID]}" == "$__group_id" ]; then
			# will delete this group after delete all child nodes
			((__gcounter++))
			__gid=${array[$CONFIDX_TCID]}
		elif [ "${array[$CONFIDX_TYPE]}" == "node" ] && [ "${array[$CONFIDX_N_P_ID]}" == "$__group_id" ]; then
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
		echo "Warning!! There is no $__group_id node"
		rm -f $__tmpfile
		return
	fi

	mv -f $__tmpfile $CONFFILE
}




# make string to store the node info in config file
#	make_node_conf <id> <tcid> <parent_id> <parent_tcid>
#                  <min_bps> <max_bps>
#                  <protocol>
#                  <src_ip> <src_port>
#                  <dst_ip> <dst_port>
#                  <prio>
function make_node_conf() {
	local __id=$1
	local __tcid=$2
	local __parent_id=$3
	local __parent_tcid=$4
	local __min_bps=$5
	local __max_bps=$6
	local __protocol=$7
	local __src_ip=$8
	local __src_port=$9
	local __dst_ip=${10}
	local __dst_port=${11}
	local __prio=${12}

	local __nodeinfo="node,$__id,$__tcid,$__parent_id,$__parent_tcid"
	local __classinfo="$__min_bps,$__max_bps"
	local __filterinfo="$__protocol,$__src_ip,$__src_port,$__dst_ip,$__dst_port"
	echo "$__nodeinfo,$__classinfo,$__filterinfo,$__prio"
}

# add new node
#	add_new_node <id> <parent_id>
#                <min_bps> <max_bps>
#                <protocol>
#                <src_ip> <src_port>
#                <dst_ip> <dst_port>
#                <prio>
function add_new_node() {
	local __id=$1
	local __parent_id=$2
	local __min_bps=$3
	local __max_bps=$4
	local __protocol=$5
	local __src_ip=$6
	local __src_port=$7
	local __dst_ip=$8
	local __dst_port=$9
	local __prio=${10}
	if [ "$__prio" == "" ]; then
		__prio=$PRIO_DEFAULT
	fi

	# check if params are valid
	param_valid_id_and_exit "$__id" "node ID"
	param_valid_id_and_exit "$__parent_id" "parent ID"
	param_valid_rate_and_exit "$__min_bps" "min_limit"
	param_valid_rate_and_exit "$__max_bps" "max_limit"
	param_valid_protocol_and_exit "$__protocol"
	param_valid_ip_and_exit "$__src_ip" "src_ip"
	param_valid_port_and_exit "$__src_port" "src_port"
	param_valid_ip_and_exit "$__dst_ip" "dst_ip"
	param_valid_port_and_exit "$__dst_port" "dst_port"
	if [ "$__src_ip" == "0" ] && [ "$__src_port" == "0" ] && [ "$__dst_ip" == "0" ] && [ "$__dst_port" == "0" ]; then
		echo Error!! No filters are specified. At least one filter must be specified.
		exit 1
	fi
	param_valid_prio_and_exit "$__prio"

	# check if ID is already exist
	get_tcid $__id
	if [ "$?" != "0" ]; then
		echo Error!! $__id already exists.
		exit 1
	fi

	get_new_tcid
	local __tcid=$?
	echo New ID: $__tcid
	get_tcid $__parent_id
	local __parent_tcid=$?
	if [ "$__parent_tcid" == "0" ]; then
		echo "Error!! Cannot find the parent ID $__parent_id"
		exit 1
	fi
	echo Parent ID: $__parent_tcid

	tc_add_node $__tcid $__parent_tcid $__min_bps $__max_bps $__protocol $__src_ip $__src_port $__dst_ip $__dst_port $__prio
	if [ $tcRes == true ]; then
		echo $(make_node_conf $__id $__tcid $__parent_id $__parent_tcid $__min_bps $__max_bps $__protocol $__src_ip $__src_port $__dst_ip $__dst_port $__prio) >> $CONFFILE
	fi
}

# replace node
#	replace_node <id>
#                <min_bps> <max_bps>
#                <protocol>
#                <src_ip> <src_port>
#                <dst_ip> <dst_port>
#                <prio>
function replace_node() {
	local __id=$1
	local __min_bps=$2
	local __max_bps=$3
	local __protocol=$4
	local __src_ip=$5
	local __src_port=$6
	local __dst_ip=$7
	local __dst_port=$8
	local __prio=$9
	if [ "$__prio" == "" ]; then
		__prio=$PRIO_DEFAULT
	fi

	# check if params are valid
	param_valid_id_and_exit "$__id" "node ID"
	param_valid_rate_and_exit "$__min_bps" "min_limit"
	param_valid_rate_and_exit "$__max_bps" "max_limit"
	param_valid_protocol_and_exit "$__protocol"
	param_valid_ip_and_exit "$__src_ip" "src_ip"
	param_valid_port_and_exit "$__src_port" "src_port"
	param_valid_ip_and_exit "$__dst_ip" "dst_ip"
	param_valid_port_and_exit "$__dst_port" "dst_port"
	if [ "$__src_ip" == "0" ] && [ "$__src_port" == "0" ] && [ "$__dst_ip" == "0" ] && [ "$__dst_port" == "0" ]; then
		echo Error!! No filters are specified. At least one filter must be specified.
		exit 1
	fi
	param_valid_prio_and_exit "$__prio"

	get_tcid $__id
	local __tcid=$?
	if [ "$__tcid" == "0" ]; then
		echo "Error!! Cannot find the ID $__id"
		exit 1
	fi

	tc_replace_node $__tcid $__min_bps $__max_bps $__protocol $__src_ip $__src_port $__dst_ip $__dst_port $__prio
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
			echo $(make_node_conf $1 $__tcid ${array[$CONFIDX_N_P_ID]} ${array[$CONFIDX_N_P_TCID]} $__min_bps $__max_bps $__protocol $__src_ip $__src_port $__dst_ip $__dst_port $__prio) >> $__tmpfile
		else
			echo "$line" >> $__tmpfile
		fi
	done
	mv -f $__tmpfile $CONFFILE
}

# delete node.
#	del_node <id>
function del_node() {
	local __id=$1

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
		if [ "${array[$CONFIDX_ID]}" != "$__id" ]; then
			echo "$line" >> $__tmpfile
			continue;
		fi

		# if the id is not node, error
		if [ "${array[$CONFIDX_TYPE]}" != "node" ]; then
			echo "Error!! ID $__id is not node, but ${array[$CONFIDX_TYPE]}"
			rm -f $__tmpfile
			exit 1
		fi

		tc_del_node ${array[$CONFIDX_TCID]}
		((__counter++))
	done

	if [ "$__counter" == "0" ]; then
		echo "Warning!! There is no $ID node"
		rm -f $__tmpfile
		return
	fi

	mv -f $__tmpfile $CONFFILE
}


function list_all() {
	echo "list_all() function is not implemented yet"
}

function list_group() {
	echo "list_group() function is not implemented yet"
}

function print_node_array()
{
	local __node_id=$1
	local __node_p_id=$2
	local __node_llimit=$3
	local __node_ulimit=$4
	local __node_prio=$5
	local __node_protocol=$6
	local __node_src_ip=$7
	local __node_src_port=$8
	local __node_dst_ip=$9
	local __node_dst_port=${10}

	echo "Node [$__node_id] (Group $__node_p_id)"
	echo "    Speed  $__node_llimit ~ $__node_ulimit"
	local __prio=$PRIO_DEFAULT
	if [ "$__node_prio" != "" ]; then
		__prio=$__node_prio
	fi
	echo "    Prio   $__prio"
	echo -n "    Filter"
	local __proto=all
	if [ "$__node_protocol" != "0" ]; then
		__proto=$__node_protocol
	fi
	echo              " protocol=$__proto"
	if [ "$__node_src_ip" != "0" ]; then
		echo "           source ip=$__node_src_ip"
	fi
	if [ "$__node_src_port" != "0" ]; then
		echo "           source port=$__node_src_port"
	fi
	if [ "$__node_dst_ip" != "0" ]; then
		echo "           dest ip=$__node_dst_ip"
	fi
	if [ "${array[$CONFIDX_N_DST_PORT]}" != "0" ]; then
		echo "           dest port=$__node_dst_port"
	fi

}

function list_node() {
	local __counter=0
	for line in "${conf_lines[@]}"; do
		if [[ "$line" == "#"* ]]; then
			continue;
		fi
		local array=(${line//,/ })

		# check id of config
		if [ "${array[$CONFIDX_TYPE]}" == "node" ] && [ "${array[$CONFIDX_ID]}" == "$1" ]; then
			print_node_array ${array[$CONFIDX_ID]} \
							 ${array[$CONFIDX_N_P_ID]} \
							 ${array[$CONFIDX_N_LLIMIT]} \
							 ${array[$CONFIDX_N_ULIMIT]} \
							 ${array[$CONFIDX_N_PRIO]} \
							 ${array[$CONFIDX_N_PROTOCOL]} \
							 ${array[$CONFIDX_N_SRC_IP]} \
							 ${array[$CONFIDX_N_SRC_PORT]} \
							 ${array[$CONFIDX_N_DST_IP]} \
							 ${array[$CONFIDX_N_DST_PORT]}
			((__counter++))
		fi
	done
	if [ "$__counter" == "0" ]; then
		echo Warning!! There is no node $1
	fi
}



function param_valid_id() {
	local __id=$1
	local __stat=true

	if [[ $__id =~ ^[a-zA-Z0-9_\-]+$ ]]; then
		__stat=true
	else
		__stat=false
	fi

	echo $__stat
}

function param_valid_id_and_exit() {
	local __id=$1
	local __param_string=$2

	if [ "$__id" == "" ]; then
		echo Error!! $__param_string is not specified
		exit 1
	fi
	local __stat=$(param_valid_id $__id)
	if [ $__stat == false ]; then
		echo Error!! ID $__id contains invalid characters.
		exit 1
	fi
}


function param_valid_rate() {
	local __rate=$1
	local __stat=true

	if [[ $__rate =~ ^[0-9]+[kKmMgG]{0,1}bit$ ]]; then
		__stat=true
	else
		__stat=false
	fi

	echo $__stat
}

function param_valid_rate_and_exit() {
	local __rate=$1
	local __param_string=$2

	if [ "$__rate" == "" ]; then
		echo Error!! $__param_string is not specified
		exit 1
	fi

	local __stat=$(param_valid_rate $__rate)
	if [ $__stat == false ]; then
		echo Error!! $__param_string is invalid.
		exit 1
	fi
}


function param_valid_protocol() {
	local __protocol=$1
	local __stat=true

	if [ "$__protocol" != "tcp" ] && [ "$__protocol" != "TCP" ] && [ "$__protocol" != "udp" ] && [ "$__protocol" != "UDP" ]; then
		__stat=false
	fi

	echo $__stat
}

function param_valid_protocol_and_exit() {
	local __protocol=$1

	if [ "$__protocol" == "" ]; then
		echo Error!! protocol is not specified
		exit 1
	fi

	if [ "$__protocol" == "0" ]; then
		return
	fi

	local __stat=$(param_valid_protocol $__protocol)
	if [ $__stat == false ]; then
		echo Error!! protocol is invalid.
		exit 1
	fi
}


function param_valid_ip() {
	local __ip=$1
	local __ipaddr=0.0.0.0
	local __netmask=32
	local __stat=true

	if [[ $__ip =~ ^[0-9\.]+/[0-9]{1,2}$ ]]; then
		OIFS=$IFS
		IFS='/'
		__ip=($__ip)
		IFS=$OIFS
		__ipaddr=${__ip[0]}
		__netmask=${__ip[1]}
	else
		__ipaddr=$__ip
	fi

	if [[ $__ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=$IFS
		IFS='.'
		__ip=($__ip)
		IFS=$OIFS
		if [[ ${ip[0]} -gt 255 || ${ip[1]} -gt 255 || ${ip[2]} -gt 255 || ${ip[3]} -gt 255 ]]; then
			__stat=false
		fi
	else
		__stat=false
	fi

	if [[ $__netmask =~ ^[0-9]{1,2}$ ]]; then
		if [[ $__netmask -gt 32 ]]; then
			__stat=false
		fi
	else
		__stat=false
	fi

	echo $__stat
}

function param_valid_ip_and_exit() {
	local __ip=$1
	local __param_string=$2

	if [ "$__ip" == "" ]; then
		echo Error!! $__param_string is not specified
		exit 1
	fi

	if [ "$__ip" == "0" ]; then
		return
	fi

	local __stat=$(param_valid_ip $__ip)
	if [ $__stat == false ]; then
		echo Error!! $__param_string is invalid.
		exit 1
	fi
}


function param_valid_port() {
	local __port=$1
	local __stat=true

	if [[ $__port =~ ^[0-9]{1,5}$ ]]; then
		if [[ $__port -gt 65535 ]]; then
			__stat=false
		fi
	else
		__stat=false
	fi

	echo $__stat
}

function param_valid_port_and_exit() {
	local __port=$1
	local __param_string=$2

	if [ "$__port" == "" ]; then
		echo Error!! $__param_string is not specified
		exit 1
	fi

	if [ "$__port" == "0" ]; then
		return
	fi

	local __stat=$(param_valid_port $__port)
	if [ $__stat == false ]; then
		echo Error!! $__param_string is invalid.
		exit 1
	fi
}



function param_valid_prio() {
	local __prio=$1
	local __stat=true

	if [[ $__prio =~ ^[0-7]$ ]]; then
		__stat=true
	else
		__stat=false
	fi

	echo $__stat
}

function param_valid_prio_and_exit() {
	local __prio=$1

	if [ "$__prio" == "" ]; then
		return
	fi

	local __stat=$(param_valid_prio $__prio)
	if [ $__stat == false ]; then
		echo Error!! priority is invalid.
		exit 1
	fi
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
				shift 1
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
					shift 1
					list_group $*
					;;
				node)
					shift 1
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
	reset)
		echo Reset all QoS settings
		shift 1
		clear
		sleep 1
		init
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


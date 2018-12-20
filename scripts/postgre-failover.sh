#! /bin/sh
# Execute command by failover.
# special values:  %d = node id
#                  %h = host name
#                  %p = port number
#                  %D = database cluster path
#                  %m = new master node id
#                  %M = old master node id
#                  %H = new master node host name
#                  %P = old primary node id
#                  %R = new master database cluster path
#                  %r = new master port number
#                  %% = '%' character
failed_node_id=$1
failed_host_name=$2
failed_port=$3
failed_db_cluster=$4
new_master_id=$5
old_master_id=$6
new_master_host_name=$7
old_primary_node_id=$8
new_master_port_number=$9
new_master_db_cluster=${10}

date > /proc/1/fd/2
echo "failed_node_id $failed_node_id failed_host_name $failed_host_name failed_port $failed_port failed_db_cluster $failed_db_cluster new_master_id $new_master_id old_master_id $old_master_id new_master_host_name $new_master_host_name old_primary_node_id $old_primary_node_id new_master_port_number $new_master_port_number new_master_db_cluster $new_master_db_cluster" > /proc/1/fd/2

if [ a"$failed_node_id" = a"$old_primary_node_id" ]; then	# master failed
    kubectl exec ${new_master_host_name} -- pg_ctl -D /var/lib/postgresql/data/pgdata promote 2>&1 > /proc/1/fd/2
fi
      
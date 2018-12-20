#!/usr/bin/env bash

set -e

# StatefulSet Name and POD Serial ID
IFS='-' read -ra ADDR <<< "$(hostname)"
SETNAME=${ADDR[0]}
SERIAL=${ADDR[-1]}

PGSQL_PRIMARY=pgsql-primary

SPEC_REPLICAS=`kubectl get sts ${SETNAME} -o json | jq .spec.replicas`

generate_common_conf() {
    replicas=$1

    cp /usr/local/etc/pgpool.conf /usr/local/etc/pgpool.common.conf

    for idx in `seq 0 $((SPEC_REPLICAS-1))`; do
        cat<<EOF >> /usr/local/etc/pgpool.common.conf
# __START_BACKEND__${idx}
backend_hostname${idx} = 'postgres-${idx}.postgres'
backend_port${idx} = 5432
backend_weight${idx} = 1
backend_data_directory${idx} = '/var/lib/pgsql/data/pgdata'
backend_flag${idx} = 'ALLOW_TO_FAILOVER'
# __END__BACKEND__${idx}
EOF
    done
}

generate_backend_conf() {
   cp /usr/local/etc/pgpool.common.conf /usr/local/etc/pgpool-${SERIAL}.conf
   cat<<EOF >> /usr/local/etc/pgpool-${SERIAL}.conf
use_watchdog = on
failover_when_quorum_exists = on
wd_lifecheck_method = 'heartbeat'
wd_heartbeat_port = 9694
wd_hostname = ${HOSTNAME}.${SETNAME}
wd_authkey = ''
wd_priority = $((SERIAL+1))
EOF
    idx=0
    for i in `seq 0 $((SPEC_REPLICAS-1))`; do
        [[ $i -eq $SERIAL ]] && continue        
        cat<<EOF >> /usr/local/etc/pgpool-${SERIAL}.conf
other_pgpool_hostname${idx} = ${SETNAME}-${i}.${SETNAME}
other_pgpool_port${idx} = 5433
other_wd_port${idx} = 9000

heartbeat_destination${idx} = ${SETNAME}-${i}.${SETNAME}
heartbeat_destination_port${idx} = 9694
EOF
        idx=$((idx+1))
    done
}


pod_init() {
    cp /initdb.d/* /docker-entrypoint-initdb.d/

    if [[ ${SERIAL} -eq 0 ]]; then
        echo "Serial is 0"
        # Create Replication Slots

        for idx in `seq 1 $((SPEC_REPLICAS-1))`; do            
            cat <<EOF >> /docker-entrypoint-initdb.d/replications-slots.sql
SELECT * FROM pg_create_physical_replication_slot('base_backup_${idx}');
EOF
        done
        if [[ $(kubectl get pod -l pgsql-role=primary -o json | jq .items | jq length) -eq 0 ]];  then
            kubectl label pod ${SETNAME}-0 pgsql-role=primary
        else
            echo "${HOSTNAME}: Already have pod labled master"
        fi
    else
        echo "Serial is not 0, populating data from primary"        
        pg_basebackup --host ${PGSQL_PRIMARY} --user postgres --write-recovery-conf --wal-method=stream --slot=base_backup_${SERIAL} -D /var/lib/postgresql/data/pgdata
    fi
}

if [[ -f /var/lib/postgresql/data/pgdata/PG_VERSION ]]; then
    echo "data volume already populated"
    sleep 24h
fi

if [[ "$1" = 'pod-init' ]]; then
    pod_init
    exit 0
fi

generate_common_conf
generate_backend_conf
rm  -v /usr/local/etc/pgpool.conf && ln -sv /usr/local/etc/pgpool-${SERIAL}.conf /usr/local/etc/pgpool.conf

# fixup ~/.pcppass
cp ${HOME}/.pcppass ${HOME}/.pcppass-new
for i in `seq 0 $((SPEC_REPLICAS-1))`; do
    sed 's/localhost/'${SETNAME}-${i}'/' ${HOME}/.pcppass >> ${HOME}/.pcppass-new
done
mv ${HOME}/.pcppass-new ${HOME}/.pcppass

until psql -Upgpool_checker --host localhost postgres -c "SELECT 1"; do echo "waiting for own postgres" 2>&1>/dev/null; sleep 5s; done
for i in `seq $((SERIAL+1)) $((SPEC_REPLICAS-1))`; do
    until ping -c1 ${SETNAME}-${i}.${SETNAME} 2>&1>/dev/null; do echo "waiting for ${SETNAME}-${i}.${SETNAME} to appear..";sleep 5s; done
done

for i in `seq $((SERIAL+1)) $((SPEC_REPLICAS-1))`; do
    until psql -Upgpool_checker --host ${SETNAME}-${i}.${SETNAME} postgres -c "SELECT 1"; do 
        echo "waiting for ${SETNAME}-${i}.${SETNAME} be ready..";sleep 2s; 
    done
done

echo "Executing $@"
exec "$@"
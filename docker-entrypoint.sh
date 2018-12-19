#!/usr/bin/env bash

set -e

# StatefulSet Name and POD Serial ID
IFS='-' read -ra ADDR <<< "$(hostname)"
SETNAME=${ADDR[0]}
SERIAL=${ADDR[-1]}

PGSQL_PRIMARY=pgsql-primary

generate_common_conf() {
    replicas=$1

    cp /usr/local/etc/pgpool.conf /usr/local/etc/pgpool.common.conf

    for idx in `seq 0 $((replicas-1))`; do
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
   replicas=$1

   cp /usr/local/etc/pgpool.common.conf /usr/local/etc/pgpool-${SERIAL}.conf
   cat<<EOF >> /usr/local/etc/pgpool-${SERIAL}.conf
use_watchdog = on
wd_lifecheck_method = 'query'
wd_lifecheck_user = 'pgpool_checker'
wd_hostname = ${HOSTNAME}.${SETNAME}
wd_authkey = ''
EOF
    for idx in `seq 0 $((replicas-1))`; do
        [[ $idx -eq $SERIAL ]] && continue
        cat<<EOF >> /usr/local/etc/pgpool-${SERIAL}.conf
other_pgpool_hostname${idx} = ${SETNAME}-${idx}.${SETNAME}
other_pgpool_port${idx} = 5433
other_wd_port${idx} = 9000
EOF
    done
}


pod_init() {
    cp /initdb.d/* /docker-entrypoint-initdb.d/

    if [[ ${SERIAL} -eq 0 ]]; then
        echo "Serial is 0"
        if [[ $(kubectl get pod -l pgsql-role=primary -o json | jq .items | jq length) -eq 0 ]];  then
            kubectl label pod ${SETNAME}-0 pgsql-role=primary
        else
            echo "${HOSTNAME}: Already have pod labled master"
        fi
    else
        echo "Serial is not 0, populating data from primary"        
        pg_basebackup --host ${PGSQL_PRIMARY} -Upostgres -D /var/lib/postgresql/data/pgdata
    fi
}

if [[ "$1" = 'pod-init' ]]; then
    pod_init
    exit 0
fi


spec_replicas=`kubectl get sts ${SETNAME} -o json | jq .spec.replicas`

generate_common_conf ${spec_replicas}
generate_backend_conf ${spec_replicas}
rm  -v /usr/local/etc/pgpool.conf && ln -sv /usr/local/etc/pgpool-${SERIAL}.conf /usr/local/etc/pgpool.conf

# fixup ~/.pcppass
cp ${HOME}/.pcppass ${HOME}/.pcppass-new
for i in `seq 0 $((spec_replicas-1))`; do
    sed 's/localhost/'${SETNAME}-${i}'/' ${HOME}/.pcppass >> ${HOME}/.pcppass-new
done
mv ${HOME}/.pcppass-new ${HOME}/.pcppass

for i in `seq $((SERIAL+1)) $((spec_replicas-1))`; do
    until ping -c1 ${SETNAME}-${i}.${SETNAME}; do echo "waiting for ${SETNAME}-${i}.${SETNAME} to appear..";sleep 2s; done
done

until psql -Upgpool_checker --host localhost postgres -c "SELECT 1"; do echo "waiting for own postgres"; sleep 2s; done
echo "Executing $@"
exec "$@"
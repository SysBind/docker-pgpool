#!/usr/bin/env bash

set -e

# StatefulSet Name and POD Serial ID
IFS='-' read -ra ADDR <<< "$(hostname)"
SETNAME=${ADDR[0]}
SERIAL=${ADDR[-1]}

PGSQL_PRIMARY=pgsql-primary


generate_pgpool_backend_conf() {
   cat<<EOF > /usr/local/etc/pgpool-backend.conf
# __BACKEND__$SERIAL
backend_hostname$SERIAL = 'postgres-$SERIAL.postgres'
backend_port$SERIAL = 5432
backend_weight$SERIAL = 1
backend_data_directory$SERIAL = '/var/lib/pgsql/data/pgdata'
backend_flag$SERIAL = 'ALLOW_TO_FAILOVER'
EOF
}

pod_init() {
    cp /initdb.d/* /docker-entrypoint-initdb.d/

    if [[ ${SERIAL} -eq 0 ]]; then
        echo "Serial is 0"
        if [[ ! kubectl get pod -l pgsql-role=primary ]];  then
            kubectl label pod ${SETNAME}-0 pgsql-role=primary
        else
            echo "${HOSTNAME}: Already have pod labled master"
        fi
    else
        echo "Serial is not 0, populating data from primary"
        pg_basebackup --host $PGSQL_PRIMARY -R -X stream -Upostgres -D /var/lib/postgresql/data/pgdata
    fi


    if [[ ! -f /usr/local/etc/bound/pgpool.conf ]]; then
        echo "first cluster turn-up, populating pgpool.conf and others"
        touch ./pool_passwd
        generate_pgpool_backend_conf
        cat /usr/local/etc/pgpool.conf /usr/local/etc/pgpool-backend.conf > ./pgpool.conf
        kubectl create secret generic pgpool-config --dry-run -o yaml \
                --from-file=./pgpool.conf \
                --from-file=/usr/local/etc/pcp.conf \
                --from-file=./pool_passwd | kubectl apply -f -
        # Wait for secret propagation to volume mount:
        until [[ -f /usr/local/etc/bound/pgpool.conf ]];
            do echo "Waiting for bound/pgpool.conf to appear..."; sleep 2s;
        done
    fi
}

if [[ "$1" = 'pod-init' ]]; then
    pod_init
    exit 0
fi

if !  grep backend_hostname$SERIAL /usr/local/etc/bound/pgpool.conf; then
    echo "not found self in pgpool conf, updating and taking over.."
    kubectl create secret generic pgpool-config --from-file=./pgpool.conf --dry-run -o yaml | kubectl apply -f -
fi

echo "Executing $@"
exec "$@"
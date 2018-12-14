#!/usr/bin/env bash

set -e

# StatefulSet Name and POD Serial ID
IFS='-' read -ra ADDR <<< "$(hostname)"
SETNAME=${ADDR[0]}
SERIAL=${ADDR[-1]}

PGSQL_PRIMARY=pgsql-primary

if [ "$1" = 'pod-init' ]; then
    cp /initdb.d/* /docker-entrypoint-initdb.d/

    if [ $SERIAL -eq 0 ]; then
        echo "Serial is 0"
    else
        echo "Serial is not 0, populating data from primary"
        pg_basebackup --host $PGSQL_PRIMARY -Upostgres -D /var/lib/postgresql/data/pgdata
    fi
    exit 0
fi
echo "Executing $@"
exec "$@"
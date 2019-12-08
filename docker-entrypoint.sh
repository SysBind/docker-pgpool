#!/bin/bash

set -e


if [ -z ${BACKENDS+x} ]; then
    >&2 echo "error: BACKENDS must be set";
    exit 2
fi

if [ -z ${INIT_DELAY+x} ]; then
    INIT_DELAY=0
fi

if [  -f /usr/local/etc/pgpool.conf.original] ]; then
   cp -v /usr/local/etc/pgpool.conf.original /usr/local/etc/pgpool.conf
else
   cp -v /usr/local/etc/pgpool.conf /usr/local/etc/pgpool.conf.original
fi

add_backend() {
    backend_idx=$1
    backend_spec=$2
    echo "add backend $backend_idx: $backend_spec"
    port=5432
    host=''
    path=/var/lib/pgsql/data
    while IFS=':' read -ra data; do
	for i in "${!data[@]}"; do
            case $i in
		0) host=${data[0]}
		   ;;
		1) port=${data[1]}
		   ;;
		2) path=${data[2]}
		   ;;
	    esac
	done
    done <<< "$backend_spec"

    echo "host=$host port=$port"
    cat <<EOF >> /usr/local/etc/pgpool.conf
backend_hostname$backend_idx = '$host'
backend_port$backend_idx = $port
backend_weight$backend_idx = 1
backend_data_directory$backend_idx = '$path'
backend_flag$backend_idx = 'ALLOW_TO_FAILOVER'
EOF

}

configure_healthcheck() {
    hc_user=pgpool_checker
    hc_pass=""
    if [ ! -z ${HEALTHCHECK}+x} ]; then
      echo "found HEALTHCHECK env var.."
      while IFS=':' read -ra data; do
       for i in "${!data[@]}"; do
        case $i in
         0) hc_user=${data[0]}
         ;;
         1) hc_pass=${data[1]}
         ;;
        esac
       done
     done <<< "$HEALTHCHECK"
    else
     echo "NO HEALTHCHECK env var.., using defaults"
    fi
    cat <<EOF >>  /usr/local/etc/pgpool.conf
health_check_user = '$hc_user'
health_check_password = '$hc_pass'
EOF

}

configure_sr_check() {
    sr_user=pgpool_checker
    sr_pass=""
    if [ ! -z ${SR_CHECK}+x} ]; then
      echo "found SR_CHECK env var..: $SR_CHECK"
      while IFS=':' read -ra data; do
       for i in "${!data[@]}"; do
        case $i in
         0) sr_user=${data[0]}
            echo "sr_user = $sr_user"
         ;;
         1) sr_pass=${data[1]}
	    echo "sr_pass = $sr_pass"
         ;;
        esac
       done
     done <<< "$SR_CHECK"
    else
     echo "NO SR_CHECK env var.., using defaults"
    fi
    cat <<EOF >>  /usr/local/etc/pgpool.conf
sr_check_user = '$sr_user'
sr_check_password = '$sr_pass'
EOF

} 

echo "configuring pgpool.."

while IFS=' ' read -ra backend; do
    for i in "${!backend[@]}"; do
        add_backend $i ${backend[i]}
    done
done <<< "$BACKENDS"

configure_healthcheck
configure_sr_check

echo "waiting for postgres.."
sleep ${INIT_DELAY}s

echo "Executing pgpool.."
pgpool -n

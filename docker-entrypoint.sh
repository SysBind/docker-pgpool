#!/bin/bash

set -e

if [ -z ${BACKEND_HOSTNAME0+x} ]; then
    >&2 echo "error: at least BACKEND_HOSTNAME0 must be set";
    exit 2
fi
			 
echo "Executing pgpool"
pgpool -n

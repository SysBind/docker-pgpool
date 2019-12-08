# docker-pgpool
Docker image for pgpool-II



## Configuration
BACKENDS (Required)
syntax:
BACKENDS=host0:port0:datadir0 host1:port1:datadir1 ... hostN:portN:datadirN
at least one backend.
port and datadir can be ommited, default: 5432, /var/lib/pgsql/data e.g:
BACKENDS=host0 host1
(no quotation marks)

HEALTHCHECK=user:password
SR_CHECK=user:password


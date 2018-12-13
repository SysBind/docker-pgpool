FROM postgres:11-alpine

MAINTAINER Asaf Ohayon <asaf@sysbind.co.il>

ENV PGPOOL_VERSION=4.0.2
ENV PGPOOL_SHA256 a9324dc84e63961476cd32e74e66b6fdebc5ec593942f8710a688eb88e50dcc1

RUN set -ex \
	\
	&& apk add --no-cache --virtual .fetch-deps \
		tar \
    && wget -O pgpool-II.tar.gz "http://www.pgpool.net/mediawiki/images/pgpool-II-$PGPOOL_VERSION.tar.gz" \
    && echo "$PGPOOL_SHA256 *pgpool-II.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/src/pgpool-II \
    && tar \
    		--extract \
    		--file pgpool-II.tar.gz \
    		--directory /usr/src/pgpool-II \
    		--strip-components 1 \
    && rm pgpool-II.tar.gz \
    && apk add --no-cache --virtual .build-deps \
       gcc \
       libc-dev \
       linux-headers \
       make


RUN set -ex \
    \
    && cd /usr/src/pgpool-II \
    && ./configure \
    && make \
    && make install \
    && apk del .fetch-deps .build-deps

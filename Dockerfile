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

COPY fix_compile_alpine38.patch /

RUN set -ex \
    \
    && cd /usr/src/pgpool-II \
    && patch -p1 < /fix_compile_alpine38.patch \
    && ./configure \
    && make \
    && make install \
    && apk del .fetch-deps .build-deps \
    && rm /*.patch

RUN apk add jq

RUN mkdir -p /var/run/pgpool && chown -R postgres:postgres /var/run/pgpool && chmod 2777 /var/run/pgpool

RUN mkdir /initdb.d/
COPY initdb.d/* /initdb.d/

# kubectl
RUN wget -O /usr/local/bin/kubectl \
            https://storage.googleapis.com/kubernetes-release/release/v1.13.1/bin/linux/amd64/kubectl \
    && chmod +x /usr/local/bin/kubectl

COPY pgpool.conf /usr/local/etc/pgpool.conf
COPY pcp.conf /usr/local/etc/pcp.conf
COPY dot_pcppass /root/.pcppass
RUN chmod 0600  /root/.pcppass
COPY docker-entrypoint.sh /usr/local/bin/
COPY scripts/postgre-failover.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 5432

CMD ["pgpool","-n"]
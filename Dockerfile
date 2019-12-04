FROM alpine:3

MAINTAINER Asaf Ohayon <asaf@sysbind.co.il>

ARG PGPOOL_VERSION=4.1.0
ARG PGPOOL_SHA256=a2515d3d046afda0612b34c2aeca14a2071020dafb1f32e745b4a3054c0018df

RUN set -ex \
	&& apk add --no-cache --update libpq \
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
	postgresql-dev \
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

RUN mkdir -p /var/run/pgpool && chown -R postgres:postgres /var/run/pgpool && chmod 2777 /var/run/pgpool

COPY pgpool.conf /usr/local/etc/pgpool.conf
COPY pcp.conf /usr/local/etc/pcp.conf
COPY dot_pcppass /root/.pcppass
RUN chmod 0600  /root/.pcppass
COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 5432

CMD ["pgpool","-n"]

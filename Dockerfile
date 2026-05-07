FROM debian:13-slim AS build

RUN apt-get update && \
#    apt-get upgrade && \
    apt-get install -y --no-install-recommends \
            vim ca-certificates pkg-config git gcc cmake make automake autoconf libtool patch \
            bzip2 zlib1g-dev libssl-dev libedit-dev libcurl4-openssl-dev procps \
            libjson-c-dev libsqlite3-dev libpam0g-dev uuid-dev libreadline-dev librabbitmq-dev \
            gosu

# gosu working?
RUN gosu nobody true

ARG LEGA_GID=1000

RUN \
<<EOFPWD cat > /etc/passwd && \
<<EOFGRP cat > /etc/group && \
<<EOFSHADOW cat > /etc/shadow
root:x:0:0:root:/root:/bin/bash
_apt:x:42:65534::/nonexistent:/usr/sbin/nologin
ega-sshd:x:75:$((LEGA_GID + 1)):"Privilege-separated SSH":/var/empty/sshd:/usr/sbin/nologin
rabbitmq:x:999:$((LEGA_GID + 2)):"RabbitMQ":/var/lib/rabbitmq:/usr/sbin/nologin
EOFPWD
root:x:0:
shadow:x:1:
lega:x:${LEGA_GID}:
ega-sshd:x:$((LEGA_GID + 1)):ega-sshd
rabbitmq:x:$((LEGA_GID + 2)):rabbitmq
EOFGRP
root:*:19702:0:99999:7:::
_apt:*:20564:0:99999:7:::
ega-sshd:*:19702:0:99999:7:::
rabbitmq:!:19702:0:99999:7:::
EOFSHADOW

RUN chgrp shadow /etc/shadow && \
    chmod 640    /etc/shadow && \
# /var/empty/sshd must be owned by root and not group or world-writable.
    mkdir -p /var/empty/sshd && \
    chmod 700 /var/empty/sshd

COPY src/openssh /var/src/openssh
COPY src/patches /var/src/patches

######### OpenSSH
WORKDIR /var/src/openssh

# Patching the sftp-server.c
RUN cp ../patches/fega-mq.c .
RUN patch -p1 < ../patches/lega.patch

# (re)Build OpenSSH
RUN autoreconf && \
    ./configure --prefix=/opt/openssh \
                --with-pam --with-pam-service=ega \
		--with-zlib \
		--with-openssl \
		--with-libedit \
		--with-privsep-user=ega-sshd \
	        --with-privsep-path=/var/empty/sshd \
	        --without-xauth \
 	        --without-maildir \
		--without-selinux \
		--without-systemd \
		--with-pid-dir=/run

RUN  make && \
# rsa, dsa and ed25519 keys are created in the entrypoint
     make install-nosysconf

# Install EGA PAM
COPY src/auth/src /var/src/auth
WORKDIR /var/src/auth
RUN mkdir -p /usr/local/lib/ega && \
    make NSS_CFGFILE='/etc/ega/auth.conf' && \
    make install

COPY conf/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN mkdir /etc/ega && \
    chmod 755 /usr/local/bin/entrypoint.sh && \
    echo '/usr/local/lib' >> /etc/ld.so.conf.d/ega.conf && \
    echo '/usr/local/lib/ega' >> /etc/ld.so.conf.d/ega.conf && \
    sed -i -e 's/^passwd:\(.*\)files/passwd:\1files ega/' /etc/nsswitch.conf && \
    sed -i -e 's/^shadow:\(.*\)files/shadow:\1files ega/' /etc/nsswitch.conf && \
    ldconfig -v

#################################################
## RabbitMQ
#################################################
FROM rabbitmq:4.2.6 AS rabbitmq

#################################################
##
## Final image
##
#################################################

FROM debian:13-slim

LABEL maintainer="EGA System Developers"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.vcs-url="https://github.com/EGA-archive/LocalEGA-inbox"

EXPOSE 9000
EXPOSE 15672
EXPOSE 5672
VOLUME /ega/inbox

# Use the latest stable RabbitMQ release (https://www.rabbitmq.com/download.html)
ENV RABBITMQ_VERSION=4.2.6
# https://www.rabbitmq.com/signatures.html#importing-gpg
ENV RABBITMQ_HOME=/opt/rabbitmq
# Add RabbitMQ+Erlang to PATH
ENV PATH=$RABBITMQ_HOME/sbin:/opt/erlang/bin:$PATH

ENV LANG=C.UTF-8 LANGUAGE=C.UTF-8 LC_ALL=C.UTF-8

# the rabbitmq-server startup script uses RUNNING_UNDER_SYSTEMD to determine if the erl command
# should be started via exec, which results in beam.smp becoming PID 1 in the container
ENV RUNNING_UNDER_SYSTEMD=true

COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /etc/shadow /etc/shadow
COPY --from=build /etc/group /etc/group

# RabbitMQ files
COPY --from=rabbitmq /opt/erlang /opt/erlang
COPY --from=rabbitmq /opt/openssl /opt/openssl
COPY --from=rabbitmq /opt/rabbitmq /opt/rabbitmq
COPY --from=rabbitmq --chown=rabbitmq:rabbitmq /etc/rabbitmq /etc/rabbitmq
COPY --from=rabbitmq --chown=rabbitmq:rabbitmq /var/lib/rabbitmq /var/lib/rabbitmq
COPY --from=rabbitmq --chown=rabbitmq:rabbitmq /var/log/rabbitmq /var/log/rabbitmq
COPY --from=rabbitmq --chown=rabbitmq:rabbitmq /tmp/rabbitmq-ssl /tmp/rabbitmq-ssl

ARG ARCH=x86_64

COPY --from=build /opt/openssh /opt/openssh
COPY --from=build /usr/local/bin /usr/local/bin
COPY --from=build /usr/local/lib /usr/local/lib
COPY --from=build /usr/lib/$ARCH-linux-gnu/ /usr/lib/$ARCH-linux-gnu/

#COPY --from=build /lib/security/pam_ega_* /lib/security/
COPY --from=build /lib/security/pam_ega_auth.so /lib/security/pam_ega_auth.so
COPY --from=build /lib/security/pam_ega_acct.so /lib/security/pam_ega_acct.so
COPY --from=build /lib/security/pam_ega_session.so /lib/security/pam_ega_session.so

COPY --from=build /usr/sbin/gosu /usr/sbin/gosu

RUN chmod 755 /usr/local/bin/entrypoint.sh && \
    echo '/usr/local/lib' >> /etc/ld.so.conf.d/ega.conf && \
    echo '/usr/local/lib/ega' >> /etc/ld.so.conf.d/ega.conf && \
    sed -i -e 's/^passwd:\(.*\)files/passwd:\1files ega/' /etc/nsswitch.conf && \
    sed -i -e 's/^shadow:\(.*\)files/shadow:\1files ega/' /etc/nsswitch.conf && \
    ldconfig -v && \
    mkdir -p /etc/ega        && \
# /var/empty/sshd must be owned by root and not group or world-writable.
    mkdir -p /var/empty/sshd && \
    chmod 700 /var/empty/sshd && \
# make sure the metrics collector is re-enabled
    rm -f /etc/rabbitmq/conf.d/20-management_agent.disable_metrics_collector.conf

COPY conf/sshd_config /etc/ega/sshd_config
COPY conf/pam.ega /etc/pam.d/ega
COPY conf/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=rabbitmq:rabbitmq conf/mq /etc/rabbitmq
COPY conf/banner /etc/ega/banner

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

ARG COMMIT
ARG BUILD_DATE
LABEL org.label-schema.build-date=$BUILD_DATE
LABEL org.label-schema.vcs-ref=$COMMIT

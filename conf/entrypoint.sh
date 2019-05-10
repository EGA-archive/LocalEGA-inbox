#!/bin/bash

set -e

# Some env must be defined
[[ -z "${CEGA_ENDPOINT}" ]] && echo 'Environment CEGA_ENDPOINT is empty' 1>&2 && exit 1
[[ ! -z "${CEGA_USERNAME}" && ! -z "${CEGA_PASSWORD}" ]] && CEGA_ENDPOINT_CREDS="${CEGA_USERNAME}:${CEGA_PASSWORD}"
[[ -z "${CEGA_ENDPOINT_CREDS}" ]] && echo 'Environment CEGA_ENDPOINT_CREDS is empty' 1>&2 && exit 1

# Check if set
[[ -z "${CEGA_ENDPOINT_JSON_PREFIX+x}" ]] && echo 'Environment CEGA_ENDPOINT_JSON_PREFIX must be set' 1>&2 && exit 1

# Broker connection settings
[[ -z "${MQ_CONNECTION}" ]] && echo 'Environment MQ_CONNECTION is empty' 1>&2 && exit 1

EGA_GID=$(getent group lega | awk -F: '{ print $3 }')

cat > /etc/ega/auth.conf <<EOF
##################
# Central EGA
##################

cega_endpoint_username = ${CEGA_ENDPOINT%/}/%s?idType=username
cega_endpoint_uid = ${CEGA_ENDPOINT%/}/%u?idType=uid
cega_creds = ${CEGA_ENDPOINT_CREDS}
cega_json_prefix = ${CEGA_ENDPOINT_JSON_PREFIX}

verify_peer = ${AUTH_VERIFY_PEER:-no}
verify_hostname = ${AUTH_VERIFY_HOSTNAME:-no}
EOF

[[ -n "${AUTH_CA}" ]] && echo "cacertfile = ${AUTH_CA}" >> /etc/ega/auth.conf
[[ -n "${AUTH_CLIENT_CERT}" ]] && echo "certfile = ${AUTH_CLIENT_CERT}" >> /etc/ega/auth.conf
[[ -n "${AUTH_CLIENT_KEY}" ]] && echo "keyfile = ${AUTH_CLIENT_KEY}" >> /etc/ega/auth.conf

cat >> /etc/ega/auth.conf <<EOF

##################
# NSS & PAM
##################
#prompt = Knock Knock:
#ega_shell = /bin/bash
#ega_uid_shift = 10000

ega_gid = ${EGA_GID}
chroot_sessions = yes
db_path = /run/ega.db
ega_dir = /ega/inbox
ega_dir_attrs = 2750 # rwxr-s---
#ega_dir_umask = 027 # world-denied
EOF

cat > /etc/ega/mq.conf <<EOF
##################
# Broker
##################

# of the form amqp(s)://user:password@host:port/vhost
connection = ${MQ_CONNECTION}

verify_peer = ${MQ_VERIFY_PEER:-no}
verify_hostname = ${MQ_VERIFY_HOSTNAME:-no}

connection_attempts = 10
retry_delay = 10
# in seconds

heartbeat = 0

# Where to send the notifications
exchange = ${MQ_EXCHANGE:-cega}
routing_key = ${MQ_ROUTING_KEY:-files.inbox}
EOF

# For server verification
if [ "${MQ_VERIFY_PEER}" == 'yes' ] && [ -f "${MQ_CA}" ]; then
    # or Yes, Y, 1, True, true...
    echo "cacertfile = ${MQ_CA}" >> /etc/ega/mq.conf
fi

# For client verification
if [ -f "${MQ_CLIENT_KEY}" ]; then
    # Keyfile must be non group nor world writable
    chmod 600 ${MQ_CLIENT_KEY}
    echo "keyfile = ${MQ_CLIENT_KEY}" >> /etc/ega/mq.conf
fi

if [ -f "${MQ_CLIENT_CERT}" ]; then
    if [ ! -f "${MQ_CLIENT_KEY}" ]; then
	echo 'You must specify the keyfile in MQ_CLIENT_KEY' &1>2
	exit 2
    fi
    echo "certfile = ${MQ_CLIENT_CERT}" >> /etc/ega/mq.conf
fi


# Changing permissions
echo "Changing permissions for /ega/inbox"
chgrp lega /ega/inbox
chmod 750 /ega/inbox
chmod g+s /ega/inbox # setgid bit

echo 'Welcome to Local EGA Demo instance' > /etc/ega/banner

echo 'Creating rsa, dsa and ed25519 keys'
rm -f /etc/{ega,ssh}/ssh_host_{rsa,dsa,ed25519}_key
# No passphrase so far
/opt/openssh/bin/ssh-keygen -t rsa     -N '' -f /etc/ega/ssh_host_rsa_key
/opt/openssh/bin/ssh-keygen -t dsa     -N '' -f /etc/ega/ssh_host_dsa_key
/opt/openssh/bin/ssh-keygen -t ed25519 -N '' -f /etc/ega/ssh_host_ed25519_key

echo "Starting the SFTP server"
# Use -o LogLevel=VERBOSE to see the MQ connection parameters
exec /opt/openssh/sbin/ega-sshd -D -e -f /etc/ega/sshd_config -Z /etc/ega/mq.conf

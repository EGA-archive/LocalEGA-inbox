#!/bin/bash

set -e

# Some env must be defined
[[ -z "${CEGA_ENDPOINT}" ]] && echo 'Environment CEGA_ENDPOINT is empty' 1>&2 && exit 1
[[ ! -z "${CEGA_USERNAME}" && ! -z "${CEGA_PASSWORD}" ]] && CEGA_ENDPOINT_CREDS="${CEGA_USERNAME}:${CEGA_PASSWORD}"
[[ -z "${CEGA_ENDPOINT_CREDS}" ]] && echo 'Environment CEGA_ENDPOINT_CREDS is empty' 1>&2 && exit 1

LEGA_GID=$(getent group lega | awk -F: '{ print $3 }')

cat > /etc/ega/auth.conf <<EOF
cega_endpoint_username = ${CEGA_ENDPOINT%/}/username/%s
cega_endpoint_uid = ${CEGA_ENDPOINT%/}/user-id/%u
cega_creds = ${CEGA_ENDPOINT_CREDS}

db_path = /run/ega.db

#shell = /bin/bash
#uid_shift = 10000

gid = ${LEGA_GID}
homedir_prefix = /ega/inbox

shadow_min = 0
shadow_max = 99999
shadow_warn = 7

verify_peer = ${AUTH_VERIFY_PEER:-no}
verify_hostname = ${AUTH_VERIFY_HOSTNAME:-no}
EOF

[[ -n "${AUTH_CA}" ]] && echo "cacertfile = ${AUTH_CA}" >> /etc/ega/auth.conf
[[ -n "${AUTH_CLIENT_CERT}" ]] && echo "certfile = ${AUTH_CLIENT_CERT}" >> /etc/ega/auth.conf
[[ -n "${AUTH_CLIENT_KEY}" ]] && echo "keyfile = ${AUTH_CLIENT_KEY}" >> /etc/ega/auth.conf

# Changing permissions
echo "Changing permissions for /ega/inbox"
chgrp lega /ega/inbox
chmod 750 /ega/inbox
chmod g+s /ega/inbox # setgid bit

echo 'Creating rsa and ed25519 keys (on each boot)'
rm -f /etc/{ega,ssh}/ssh_host_{rsa,ed25519}_key
# No passphrase so far
/opt/openssh/bin/ssh-keygen -t rsa     -N '' -f /etc/ega/ssh_host_rsa_key
/opt/openssh/bin/ssh-keygen -t ed25519 -N '' -f /etc/ega/ssh_host_ed25519_key

if [ -f /etc/rabbitmq/definitions.json ]; then
    echo 'Starting the local RabbitMQ'
    # enforce rabbitmq user
    find /var/lib/rabbitmq \! -user rabbitmq -exec chown rabbitmq '{}' +
    chown -R rabbitmq /etc/rabbitmq
    # ... and cue music
    gosu rabbitmq rabbitmq-server &
fi

echo "Starting the SFTP server"
exec /opt/openssh/sbin/sshd -D -e -f /etc/ega/sshd_config

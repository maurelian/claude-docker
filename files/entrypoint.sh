#!/bin/sh
# Entrypoint runs as root: sets up SSH, then drops to the non-root user.

if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
  cp -r /etc/ssh.original/. /etc/ssh/
  ssh-keygen -A
fi
cp /etc/ssh.original/sshd_config /etc/ssh/sshd_config

exec /usr/sbin/sshd -D

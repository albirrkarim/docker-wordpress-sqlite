#!/usr/bin/env bash
set -e

mkdir -p /data/uploads
mkdir -p /data/database

chown -R www-data:www-data /data

exec /usr/local/bin/docker-entrypoint.sh "$@"

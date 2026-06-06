#!/usr/bin/env bash
set -e

WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
WORDPRESS_TARGET_DIR="/var/www/html"

mkdir -p /data/uploads
mkdir -p /data/database
mkdir -p "$WORDPRESS_TARGET_DIR"

# Force-copy WordPress files if /var/www/html is empty or missing index.php
if [ ! -f "$WORDPRESS_TARGET_DIR/index.php" ]; then
  echo "WordPress not found in /var/www/html. Copying from /usr/src/wordpress..."

  rm -rf "$WORDPRESS_TARGET_DIR"/*
  cp -a "$WORDPRESS_SOURCE_DIR"/. "$WORDPRESS_TARGET_DIR"/
fi

# Replace uploads with persistent Railway volume path
rm -rf "$WORDPRESS_TARGET_DIR/wp-content/uploads"
ln -s /data/uploads "$WORDPRESS_TARGET_DIR/wp-content/uploads"

# Replace SQLite database folder with persistent Railway volume path
rm -rf "$WORDPRESS_TARGET_DIR/wp-content/database"
ln -s /data/database "$WORDPRESS_TARGET_DIR/wp-content/database"

chown -R www-data:www-data /data
chown -R www-data:www-data "$WORDPRESS_TARGET_DIR"

echo "WordPress files ready."
echo "Uploads path: /data/uploads"
echo "SQLite database path: /data/database"

exec /usr/local/bin/docker-entrypoint.sh "$@"

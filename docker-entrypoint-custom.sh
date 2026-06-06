#!/usr/bin/env bash
set -e

WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
WORDPRESS_TARGET_DIR="/var/www/html"

echo "Custom entrypoint is running..."

mkdir -p /data/uploads
mkdir -p /data/database
mkdir -p "$WORDPRESS_TARGET_DIR"

# If WordPress core is missing, copy it from the image source.
if [ ! -f "$WORDPRESS_TARGET_DIR/index.php" ]; then
  echo "WordPress index.php missing. Rebuilding /var/www/html..."

  find "$WORDPRESS_TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  rsync -a "$WORDPRESS_SOURCE_DIR"/ "$WORDPRESS_TARGET_DIR"/
fi

# Make media persistent.
rm -rf "$WORDPRESS_TARGET_DIR/wp-content/uploads"
ln -sfn /data/uploads "$WORDPRESS_TARGET_DIR/wp-content/uploads"

# Make SQLite DB persistent.
rm -rf "$WORDPRESS_TARGET_DIR/wp-content/database"
ln -sfn /data/database "$WORDPRESS_TARGET_DIR/wp-content/database"

chown -R www-data:www-data /data
chown -R www-data:www-data "$WORDPRESS_TARGET_DIR"

echo "WordPress ready."
ls -la "$WORDPRESS_TARGET_DIR"

exec /usr/local/bin/docker-entrypoint.sh "$@"

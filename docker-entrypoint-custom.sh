#!/usr/bin/env bash
set -Eeuo pipefail

WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
WORDPRESS_TARGET_DIR="/var/www/html"

PERSISTENT_WP_CONTENT="/data/wp-content"
PERSISTENT_WP_CONFIG="/data/wp-config.php"

echo "Custom entrypoint is running..."

mkdir -p /data
mkdir -p "$WORDPRESS_TARGET_DIR"

# 1. Restore WordPress core if /var/www/html is empty.
if [ ! -f "$WORDPRESS_TARGET_DIR/index.php" ]; then
  echo "WordPress core missing. Copying from image..."

  find "$WORDPRESS_TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  rsync -a "$WORDPRESS_SOURCE_DIR"/ "$WORDPRESS_TARGET_DIR"/
fi

# 2. Persist whole wp-content.
if [ ! -d "$PERSISTENT_WP_CONTENT" ] || [ -z "$(ls -A "$PERSISTENT_WP_CONTENT" 2>/dev/null)" ]; then
  echo "/data/wp-content does not exist or is empty. Copying current wp-content..."

  mkdir -p "$PERSISTENT_WP_CONTENT"

  if [ -d "$WORDPRESS_TARGET_DIR/wp-content" ] && [ ! -L "$WORDPRESS_TARGET_DIR/wp-content" ]; then
    rsync -a "$WORDPRESS_TARGET_DIR/wp-content"/ "$PERSISTENT_WP_CONTENT"/
  else
    rsync -a "$WORDPRESS_SOURCE_DIR/wp-content"/ "$PERSISTENT_WP_CONTENT"/
  fi
fi

# 3. Make sure SQLite integration exists in persistent wp-content.
if [ ! -f "$PERSISTENT_WP_CONTENT/db.php" ] && [ -f "$WORDPRESS_SOURCE_DIR/wp-content/db.php" ]; then
  cp -a "$WORDPRESS_SOURCE_DIR/wp-content/db.php" "$PERSISTENT_WP_CONTENT/db.php"
fi

if [ ! -d "$PERSISTENT_WP_CONTENT/mu-plugins/sqlite-database-integration" ] && [ -d "$WORDPRESS_SOURCE_DIR/wp-content/mu-plugins/sqlite-database-integration" ]; then
  mkdir -p "$PERSISTENT_WP_CONTENT/mu-plugins"
  rsync -a "$WORDPRESS_SOURCE_DIR/wp-content/mu-plugins/sqlite-database-integration" "$PERSISTENT_WP_CONTENT/mu-plugins/"
fi

# 4. Link wp-content from persistent storage.
rm -rf "$WORDPRESS_TARGET_DIR/wp-content"
ln -sfn "$PERSISTENT_WP_CONTENT" "$WORDPRESS_TARGET_DIR/wp-content"

# 5. Persist wp-config.php.
# Important:
# - If /data/wp-config.php exists, use it.
# - If it does not exist, copy the current valid wp-config.php once.
# - Never regenerate it on every deploy.
# - Never sed-patch it.
if [ -f "$PERSISTENT_WP_CONFIG" ]; then
  echo "Using existing persistent wp-config.php..."
else
  echo "/data/wp-config.php does not exist. Copying current wp-config.php once..."

  if [ -f "$WORDPRESS_TARGET_DIR/wp-config.php" ] && [ ! -L "$WORDPRESS_TARGET_DIR/wp-config.php" ]; then
    cp -a "$WORDPRESS_TARGET_DIR/wp-config.php" "$PERSISTENT_WP_CONFIG"
  elif [ -f "$WORDPRESS_SOURCE_DIR/wp-config-docker.php" ]; then
    cp -a "$WORDPRESS_SOURCE_DIR/wp-config-docker.php" "$PERSISTENT_WP_CONFIG"
  else
    echo "ERROR: no wp-config.php source found."
    exit 1
  fi
fi

# 6. Validate config before linking.
if ! php -l "$PERSISTENT_WP_CONFIG"; then
  echo "ERROR: /data/wp-config.php has PHP syntax error."
  echo "Fix or restore /data/wp-config.php before starting."
  exit 1
fi

rm -f "$WORDPRESS_TARGET_DIR/wp-config.php"
ln -sfn "$PERSISTENT_WP_CONFIG" "$WORDPRESS_TARGET_DIR/wp-config.php"

chown -R www-data:www-data /data
chown -h www-data:www-data "$WORDPRESS_TARGET_DIR/wp-content" "$WORDPRESS_TARGET_DIR/wp-config.php"

echo "WordPress ready."
echo "Persistent wp-content: /data/wp-content"
echo "Persistent wp-config: /data/wp-config.php"

ls -la "$WORDPRESS_TARGET_DIR"
ls -la /data

exec "$@"

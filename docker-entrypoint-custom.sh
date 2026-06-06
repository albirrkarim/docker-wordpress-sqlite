#!/usr/bin/env bash
set -Eeuo pipefail

WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
WORDPRESS_TARGET_DIR="/var/www/html"

PERSISTENT_WP_CONTENT="/data/wp-content"
PERSISTENT_WP_CONFIG="/data/wp-config.php"

echo "Custom entrypoint is running..."

mkdir -p /data
mkdir -p "$WORDPRESS_TARGET_DIR"

# If WordPress core is missing, copy it from the image source.
if [ ! -f "$WORDPRESS_TARGET_DIR/index.php" ]; then
  echo "WordPress index.php missing. Rebuilding /var/www/html..."

  find "$WORDPRESS_TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  rsync -a "$WORDPRESS_SOURCE_DIR"/ "$WORDPRESS_TARGET_DIR"/
fi

# Seed the whole wp-content into persistent storage once.
if [ ! -d "$PERSISTENT_WP_CONTENT" ] || [ -z "$(ls -A "$PERSISTENT_WP_CONTENT" 2>/dev/null)" ]; then
  echo "Seeding full wp-content to /data/wp-content..."
  mkdir -p "$PERSISTENT_WP_CONTENT"

  if [ -d "$WORDPRESS_TARGET_DIR/wp-content" ] && [ ! -L "$WORDPRESS_TARGET_DIR/wp-content" ]; then
    rsync -a "$WORDPRESS_TARGET_DIR/wp-content"/ "$PERSISTENT_WP_CONTENT"/
  else
    rsync -a "$WORDPRESS_SOURCE_DIR/wp-content"/ "$PERSISTENT_WP_CONTENT"/
  fi
fi

# Safety repair: keep SQLite integration inside persistent wp-content.
if [ ! -f "$PERSISTENT_WP_CONTENT/db.php" ] && [ -f "$WORDPRESS_SOURCE_DIR/wp-content/db.php" ]; then
  echo "Restoring SQLite db.php..."
  cp -a "$WORDPRESS_SOURCE_DIR/wp-content/db.php" "$PERSISTENT_WP_CONTENT/db.php"
fi

if [ ! -d "$PERSISTENT_WP_CONTENT/mu-plugins/sqlite-database-integration" ] && [ -d "$WORDPRESS_SOURCE_DIR/wp-content/mu-plugins/sqlite-database-integration" ]; then
  echo "Restoring SQLite mu-plugin..."
  mkdir -p "$PERSISTENT_WP_CONTENT/mu-plugins"
  rsync -a "$WORDPRESS_SOURCE_DIR/wp-content/mu-plugins/sqlite-database-integration" "$PERSISTENT_WP_CONTENT/mu-plugins/"
fi

# Replace WordPress wp-content with persistent wp-content.
rm -rf "$WORDPRESS_TARGET_DIR/wp-content"
ln -sfn "$PERSISTENT_WP_CONTENT" "$WORDPRESS_TARGET_DIR/wp-content"

# Persist wp-config.php exactly as requested.
if [ -f "$PERSISTENT_WP_CONFIG" ]; then
  echo "/data/wp-config.php exists. Linking it to /var/www/html/wp-config.php..."
else
  echo "/data/wp-config.php does not exist. Copying current /var/www/html/wp-config.php into /data..."
  
  ls -a "$WORDPRESS_TARGET_DIR"

  if [ -f "$WORDPRESS_TARGET_DIR/wp-config.php" ] && [ ! -L "$WORDPRESS_TARGET_DIR/wp-config.php" ]; then
    php -l "$WORDPRESS_TARGET_DIR/wp-config.php"
    cp -a "$WORDPRESS_TARGET_DIR/wp-config.php" "$PERSISTENT_WP_CONFIG"
  else
    echo "ERROR: /data/wp-config.php does not exist and /var/www/html/wp-config.php is missing."
    echo "Create a valid wp-config.php once, then redeploy."
    exit 1
  fi
fi

# Validate persistent wp-config.php before linking.
php -l "$PERSISTENT_WP_CONFIG"

# Replace live wp-config.php with symlink to persistent config.
ln -sfn "$PERSISTENT_WP_CONFIG" "$WORDPRESS_TARGET_DIR/wp-config.php"

chown -R www-data:www-data /data
chown -R www-data:www-data "$WORDPRESS_TARGET_DIR"
chown -h www-data:www-data "$WORDPRESS_TARGET_DIR/wp-content" "$WORDPRESS_TARGET_DIR/wp-config.php"

echo "WordPress ready."
echo "Persistent wp-content: /data/wp-content"
echo "Persistent wp-config: /data/wp-config.php"

ls -la "$WORDPRESS_TARGET_DIR"
ls -la /data
ls -la "$PERSISTENT_WP_CONTENT"

exec /usr/local/bin/docker-entrypoint.sh "$@"

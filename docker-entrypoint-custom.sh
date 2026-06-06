#!/usr/bin/env bash
set -e

WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
WORDPRESS_TARGET_DIR="/var/www/html"
PERSISTENT_WP_CONTENT="/data/wp-content"
PERSISTENT_WP_CONFIG="/data/wp-config.php"

echo "Custom entrypoint is running..."

mkdir -p /data
mkdir -p "$WORDPRESS_TARGET_DIR"

# Build dynamic public URL.
if [ -n "${WORDPRESS_SITE_URL:-}" ]; then
  PUBLIC_URL="${WORDPRESS_SITE_URL}"
elif [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
elif [ -n "${RAILWAY_STATIC_URL:-}" ]; then
  PUBLIC_URL="${RAILWAY_STATIC_URL}"
else
  PUBLIC_URL=""
fi

PUBLIC_URL="${PUBLIC_URL%/}"

# Copy WordPress core if missing.
if [ ! -f "$WORDPRESS_TARGET_DIR/index.php" ]; then
  echo "WordPress index.php missing. Rebuilding /var/www/html..."

  find "$WORDPRESS_TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  rsync -a "$WORDPRESS_SOURCE_DIR"/ "$WORDPRESS_TARGET_DIR"/
fi

# Seed full wp-content once.
if [ ! -d "$PERSISTENT_WP_CONTENT" ] || [ -z "$(ls -A "$PERSISTENT_WP_CONTENT" 2>/dev/null)" ]; then
  echo "Seeding full wp-content to /data/wp-content..."
  mkdir -p "$PERSISTENT_WP_CONTENT"
  rsync -a "$WORDPRESS_TARGET_DIR/wp-content"/ "$PERSISTENT_WP_CONTENT"/
fi

# Ensure SQLite integration remains available.
if [ ! -f "$PERSISTENT_WP_CONTENT/db.php" ] && [ -f "$WORDPRESS_SOURCE_DIR/wp-content/db.php" ]; then
  echo "Restoring SQLite db.php..."
  cp -a "$WORDPRESS_SOURCE_DIR/wp-content/db.php" "$PERSISTENT_WP_CONTENT/db.php"
fi

if [ ! -d "$PERSISTENT_WP_CONTENT/mu-plugins/sqlite-database-integration" ] && [ -d "$WORDPRESS_SOURCE_DIR/wp-content/mu-plugins/sqlite-database-integration" ]; then
  echo "Restoring SQLite mu-plugin..."
  mkdir -p "$PERSISTENT_WP_CONTENT/mu-plugins"
  rsync -a "$WORDPRESS_SOURCE_DIR/wp-content/mu-plugins/sqlite-database-integration" "$PERSISTENT_WP_CONTENT/mu-plugins/"
fi

# Replace wp-content with persistent symlink.
rm -rf "$WORDPRESS_TARGET_DIR/wp-content"
ln -sfn "$PERSISTENT_WP_CONTENT" "$WORDPRESS_TARGET_DIR/wp-content"

# Persist wp-config.php.
# Important: this prevents WordPress salts from changing every redeploy.
if [ -f "$PERSISTENT_WP_CONFIG" ]; then
  echo "Using persistent wp-config.php from /data/wp-config.php..."
  rm -f "$WORDPRESS_TARGET_DIR/wp-config.php"
  ln -sfn "$PERSISTENT_WP_CONFIG" "$WORDPRESS_TARGET_DIR/wp-config.php"
else
  echo "No persistent wp-config.php found yet."

  if [ ! -f "$WORDPRESS_TARGET_DIR/wp-config.php" ]; then
    echo "Generating wp-config.php with official WordPress entrypoint..."
    /usr/local/bin/docker-entrypoint.sh true
  fi

  if [ -f "$WORDPRESS_TARGET_DIR/wp-config.php" ]; then
    echo "Saving generated wp-config.php to /data/wp-config.php..."
    cp -a "$WORDPRESS_TARGET_DIR/wp-config.php" "$PERSISTENT_WP_CONFIG"
    rm -f "$WORDPRESS_TARGET_DIR/wp-config.php"
    ln -sfn "$PERSISTENT_WP_CONFIG" "$WORDPRESS_TARGET_DIR/wp-config.php"
  else
    echo "ERROR: failed to create wp-config.php"
    exit 1
  fi
fi

# Patch persistent wp-config.php for Railway HTTPS/proxy and dynamic public URL.
if [ -f "$PERSISTENT_WP_CONFIG" ]; then
  echo "Patching persistent wp-config.php..."

  sed -i '/\/\* RAILWAY_HTTPS_FIX_START \*\//,/\/\* RAILWAY_HTTPS_FIX_END \*\//d' "$PERSISTENT_WP_CONFIG"

  if [ -n "$PUBLIC_URL" ]; then
    sed -i "s#<?php#<?php\n\
/* RAILWAY_HTTPS_FIX_START */\n\
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {\n\
    \$_SERVER['HTTPS'] = 'on';\n\
}\n\
define( 'WP_HOME', '${PUBLIC_URL}' );\n\
define( 'WP_SITEURL', '${PUBLIC_URL}' );\n\
/* RAILWAY_HTTPS_FIX_END */\n#" "$PERSISTENT_WP_CONFIG"
  else
    sed -i "s#<?php#<?php\n\
/* RAILWAY_HTTPS_FIX_START */\n\
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {\n\
    \$_SERVER['HTTPS'] = 'on';\n\
}\n\
/* RAILWAY_HTTPS_FIX_END */\n#" "$PERSISTENT_WP_CONFIG"
  fi
fi

chown -R www-data:www-data /data
chown -R www-data:www-data "$WORDPRESS_TARGET_DIR"
chown -h www-data:www-data "$WORDPRESS_TARGET_DIR/wp-content" "$WORDPRESS_TARGET_DIR/wp-config.php"

echo "WordPress ready."
echo "PUBLIC_URL=${PUBLIC_URL}"
echo "Persistent wp-content: /data/wp-content"
echo "Persistent wp-config: /data/wp-config.php"
ls -la "$WORDPRESS_TARGET_DIR"
ls -la /data

exec /usr/local/bin/docker-entrypoint.sh "$@"

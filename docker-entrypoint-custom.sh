#!/usr/bin/env bash
set -e

WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
WORDPRESS_TARGET_DIR="/var/www/html"
PERSISTENT_WP_CONTENT="/data/wp-content"

echo "Custom entrypoint is running..."

mkdir -p /data
mkdir -p "$WORDPRESS_TARGET_DIR"

# Build dynamic public URL.
# Priority:
# 1. WORDPRESS_SITE_URL, for custom domain
# 2. RAILWAY_PUBLIC_DOMAIN, Railway public domain
# 3. RAILWAY_STATIC_URL, fallback
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

# If WordPress core is missing, copy it from the image source.
if [ ! -f "$WORDPRESS_TARGET_DIR/index.php" ]; then
  echo "WordPress index.php missing. Rebuilding /var/www/html..."

  find "$WORDPRESS_TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  rsync -a "$WORDPRESS_SOURCE_DIR"/ "$WORDPRESS_TARGET_DIR"/
fi

# Seed the whole wp-content into persistent storage once.
# This copies everything: db.php, mu-plugins, plugins, themes, uploads, languages,
# cache folders, backup folders, TTS folders, and future custom plugin folders.
if [ ! -d "$PERSISTENT_WP_CONTENT" ] || [ -z "$(ls -A "$PERSISTENT_WP_CONTENT" 2>/dev/null)" ]; then
  echo "Seeding full wp-content to /data/wp-content..."
  mkdir -p "$PERSISTENT_WP_CONTENT"
  rsync -a "$WORDPRESS_TARGET_DIR/wp-content"/ "$PERSISTENT_WP_CONTENT"/
fi

# Safety repair:
# If persistent wp-content already exists but SQLite integration is missing,
# restore db.php and SQLite mu-plugin from the Docker image.
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

chown -R www-data:www-data /data
chown -R www-data:www-data "$WORDPRESS_TARGET_DIR"

# The official WordPress entrypoint creates wp-config.php if it does not exist.
if [ ! -f "$WORDPRESS_TARGET_DIR/wp-config.php" ]; then
  echo "wp-config.php missing. Running official WordPress entrypoint once to generate it..."
  /usr/local/bin/docker-entrypoint.sh true
fi

# Patch active wp-config.php for Railway HTTPS/proxy and dynamic public URL.
if [ -f "$WORDPRESS_TARGET_DIR/wp-config.php" ]; then
  echo "Patching wp-config.php for Railway HTTPS..."

  sed -i '/\/\* RAILWAY_HTTPS_FIX_START \*\//,/\/\* RAILWAY_HTTPS_FIX_END \*\//d' "$WORDPRESS_TARGET_DIR/wp-config.php"

  if [ -n "$PUBLIC_URL" ]; then
    sed -i "s#<?php#<?php\n\
/* RAILWAY_HTTPS_FIX_START */\n\
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {\n\
    \$_SERVER['HTTPS'] = 'on';\n\
}\n\
define( 'WP_HOME', '${PUBLIC_URL}' );\n\
define( 'WP_SITEURL', '${PUBLIC_URL}' );\n\
/* RAILWAY_HTTPS_FIX_END */\n#" "$WORDPRESS_TARGET_DIR/wp-config.php"
  else
    sed -i "s#<?php#<?php\n\
/* RAILWAY_HTTPS_FIX_START */\n\
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {\n\
    \$_SERVER['HTTPS'] = 'on';\n\
}\n\
/* RAILWAY_HTTPS_FIX_END */\n#" "$WORDPRESS_TARGET_DIR/wp-config.php"
  fi
fi

echo "WordPress ready."
echo "PUBLIC_URL=${PUBLIC_URL}"
echo "Persistent wp-content: /data/wp-content"
ls -la "$WORDPRESS_TARGET_DIR"
ls -la /data
ls -la "$PERSISTENT_WP_CONTENT"

exec /usr/local/bin/docker-entrypoint.sh "$@"

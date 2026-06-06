#!/usr/bin/env bash
set -e

WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
WORDPRESS_TARGET_DIR="/var/www/html"

echo "Custom entrypoint is running..."

mkdir -p /data/uploads
mkdir -p /data/database
mkdir -p "$WORDPRESS_TARGET_DIR"

# Build dynamic public URL.
# Priority:
# 1. WORDPRESS_SITE_URL, for custom domain
# 2. RAILWAY_PUBLIC_DOMAIN, Railway public domain
# 3. RAILWAY_STATIC_URL, fallback
#
# Example Railway variable:
# WORDPRESS_SITE_URL=https://blog.reinventwp.com
if [ -n "${WORDPRESS_SITE_URL:-}" ]; then
  PUBLIC_URL="${WORDPRESS_SITE_URL}"
elif [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
elif [ -n "${RAILWAY_STATIC_URL:-}" ]; then
  PUBLIC_URL="${RAILWAY_STATIC_URL}"
else
  PUBLIC_URL=""
fi

# Remove trailing slash from PUBLIC_URL if present.
PUBLIC_URL="${PUBLIC_URL%/}"

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

# The official WordPress entrypoint creates wp-config.php if it does not exist.
if [ ! -f "$WORDPRESS_TARGET_DIR/wp-config.php" ]; then
  echo "wp-config.php missing. Running official WordPress entrypoint once to generate it..."
  /usr/local/bin/docker-entrypoint.sh true
fi

# Patch active wp-config.php for Railway HTTPS/proxy and dynamic public URL.
if [ -f "$WORDPRESS_TARGET_DIR/wp-config.php" ]; then
  echo "Patching wp-config.php for Railway HTTPS..."

  # Remove old patch if it exists.
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
ls -la "$WORDPRESS_TARGET_DIR"

exec /usr/local/bin/docker-entrypoint.sh "$@"

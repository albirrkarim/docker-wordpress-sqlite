#!/usr/bin/env bash
set -e

WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
WORDPRESS_TARGET_DIR="/var/www/html"

echo "Custom entrypoint is running..."

mkdir -p /data/uploads
mkdir -p /data/database
mkdir -p /data/plugins
mkdir -p /data/themes
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

# Seed persistent plugins from image/current WordPress if /data/plugins is empty.
# This keeps default plugins and migrated plugins persistent.
if [ -d "$WORDPRESS_TARGET_DIR/wp-content/plugins" ] && [ -z "$(ls -A /data/plugins 2>/dev/null)" ]; then
  echo "Seeding /data/plugins..."
  rsync -a "$WORDPRESS_TARGET_DIR/wp-content/plugins"/ /data/plugins/ || true
fi

# Seed persistent themes from image/current WordPress if /data/themes is empty.
if [ -d "$WORDPRESS_TARGET_DIR/wp-content/themes" ] && [ -z "$(ls -A /data/themes 2>/dev/null)" ]; then
  echo "Seeding /data/themes..."
  rsync -a "$WORDPRESS_TARGET_DIR/wp-content/themes"/ /data/themes/ || true
fi

# Seed persistent uploads from image/current WordPress if /data/uploads is empty.
if [ -d "$WORDPRESS_TARGET_DIR/wp-content/uploads" ] && [ -z "$(ls -A /data/uploads 2>/dev/null)" ]; then
  echo "Seeding /data/uploads..."
  rsync -a "$WORDPRESS_TARGET_DIR/wp-content/uploads"/ /data/uploads/ || true
fi

# Recovery: if WPvivid accidentally restored plugin/theme folders into uploads,
# move obvious plugin/theme folders to the correct persistent folders.
# A theme usually has style.css at its root.
# A plugin usually has PHP files near its root.
echo "Checking for misplaced plugins/themes inside /data/uploads..."

for item in /data/uploads/*; do
  [ -d "$item" ] || continue

  name="$(basename "$item")"

  # Skip normal WordPress media year folders like 2024, 2025, 2026.
  if [[ "$name" =~ ^[0-9]{4}$ ]]; then
    continue
  fi

  # Theme detection.
  if [ -f "$item/style.css" ]; then
    echo "Moving misplaced theme: $name"
    rm -rf "/data/themes/$name"
    mv "$item" "/data/themes/$name"
    continue
  fi

  # Plugin detection.
  if find "$item" -maxdepth 2 -type f -name "*.php" | grep -q .; then
    echo "Moving misplaced plugin: $name"
    rm -rf "/data/plugins/$name"
    mv "$item" "/data/plugins/$name"
    continue
  fi
done

# Replace WordPress folders with persistent Railway volume paths.
rm -rf "$WORDPRESS_TARGET_DIR/wp-content/uploads"
ln -sfn /data/uploads "$WORDPRESS_TARGET_DIR/wp-content/uploads"

rm -rf "$WORDPRESS_TARGET_DIR/wp-content/plugins"
ln -sfn /data/plugins "$WORDPRESS_TARGET_DIR/wp-content/plugins"

rm -rf "$WORDPRESS_TARGET_DIR/wp-content/themes"
ln -sfn /data/themes "$WORDPRESS_TARGET_DIR/wp-content/themes"

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
echo "Persistent folders:"
echo "  uploads  -> /data/uploads"
echo "  plugins  -> /data/plugins"
echo "  themes   -> /data/themes"
echo "  database -> /data/database"

ls -la "$WORDPRESS_TARGET_DIR"
ls -la /data

exec /usr/local/bin/docker-entrypoint.sh "$@"

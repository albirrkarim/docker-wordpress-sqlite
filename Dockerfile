ARG TAG=apache
FROM wordpress:${TAG}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV WORDPRESS_SOURCE_DIR="/usr/src/wordpress"
ENV WORDPRESS_TARGET_DIR="/var/www/html"
ENV SQLITE_DIR="${WORDPRESS_SOURCE_DIR}/wp-content/mu-plugins/sqlite-database-integration"

# Install sqlite-database-integration
RUN if command -v apk >/dev/null 2>&1; then \
        apk add --no-cache unzip rsync; \
    else \
        apt-get update && apt-get install -y --no-install-recommends unzip rsync && rm -rf /var/lib/apt/lists/*; \
    fi && \
    VERSION=$(curl -sI "https://github.com/WordPress/sqlite-database-integration/releases/latest" | grep -i '^location' | awk -F'/' '{print $NF}' | tr -d '\r\n') && \
    curl -sL "https://github.com/WordPress/sqlite-database-integration/releases/download/${VERSION}/plugin-sqlite-database-integration.zip" -o /tmp/sq.zip && \
    unzip -o /tmp/sq.zip -d "${WORDPRESS_SOURCE_DIR}/wp-content/mu-plugins" && \
    mv "${WORDPRESS_SOURCE_DIR}/wp-content/mu-plugins/plugin-sqlite-database-integration" "${SQLITE_DIR}" && \
    rm -f /tmp/sq.zip

# Configure sqlite-database-integration
RUN mv "${SQLITE_DIR}/db.copy" "${WORDPRESS_SOURCE_DIR}/wp-content/db.php" && \
    sed -i "s#{SQLITE_IMPLEMENTATION_FOLDER_PATH}#${WORDPRESS_TARGET_DIR}/wp-content/mu-plugins/sqlite-database-integration#" "${WORDPRESS_SOURCE_DIR}/wp-content/db.php" && \
    sed -i "s#{SQLITE_PLUGIN}#${WORDPRESS_TARGET_DIR}/wp-content/mu-plugins/sqlite-database-integration/load.php#" "${WORDPRESS_SOURCE_DIR}/wp-content/db.php" && \
    sed -i "s#<?php#<?php\ndefine( 'WP_SQLITE_AST_DRIVER', true );#" "${WORDPRESS_SOURCE_DIR}/wp-content/db.php"

# Trust Railway HTTPS proxy and force HTTPS URLs in WordPress
RUN sed -i "s#<?php#<?php\n\
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {\n\
    \$_SERVER['HTTPS'] = 'on';\n\
}\n\
define( 'WP_HOME', 'https://docker-wordpress-sqlite-production.up.railway.app' );\n\
define( 'WP_SITEURL', 'https://docker-wordpress-sqlite-production.up.railway.app' );\n#" "${WORDPRESS_SOURCE_DIR}/wp-config-docker.php"

# PHP upload limits
COPY uploads.ini /usr/local/etc/php/conf.d/uploads.ini

COPY docker-entrypoint-custom.sh /usr/local/bin/docker-entrypoint-custom.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-custom.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-custom.sh"]
CMD ["apache2-foreground"]

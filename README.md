# WordPress minimum memory railway.com

Stack: Wordpress + SQL Lite

On railway start command
```
/bin/bash -c "echo 'ServerName 0.0.0.0' >> /etc/apache2/apache2.conf && echo 'DirectoryIndex index.php index.html' >> /etc/apache2/apache2.conf && echo 'upload_max_filesize = 50M' >> /usr/local/etc/php/php.ini && echo 'post_max_size = 50M' >> /usr/local/etc/php/php.ini && a2dismod mpm_event || true && a2dismod mpm_worker || true && a2enmod mpm_prefork || true && /usr/local/bin/docker-entrypoint-custom.sh apache2-foreground"
```

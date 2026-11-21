#!/bin/bash
set -euo pipefail

DIR="/vagrant/scripts"
RAIZ_REPO="/vagrant"

set -a
source "$DIR/.env"
[[ -f "$DIR/.env.local" ]] && source "$DIR/.env.local"
set +a

for var in DB_PASS PMA_APP_PASS; do
  if [[ "${!var}" == CAMBIAR* ]]; then
    echo "ERROR: define ${var} en scripts/.env.local" >&2
    exit 1
  fi
done

export DEBIAN_FRONTEND=noninteractive

echo "[1/7] Instalando Apache 2, MariaDB, PHP 8.2, extensiones recomendadas y UFW..."
apt-get update -y
apt-get install -y apache2 mariadb-server php libapache2-mod-php php-cli \
  php-mysql php-curl php-gd php-intl php-mbstring php-xml php-zip php-bcmath \
  php-imagick php-memcached unzip curl openssl ca-certificates ufw

echo "[2/7] Configurando directivas de PHP para PrestaShop..."
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
for sapi in apache2 cli; do
  cat > "/etc/php/${PHP_VER}/${sapi}/conf.d/99-prestashop.ini" <<EOF
memory_limit = ${PHP_MEMORY_LIMIT}
max_input_vars = ${PHP_MAX_INPUT_VARS}
post_max_size = ${PHP_POST_MAX_SIZE}
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}
date.timezone = ${PS_ZONA_HORARIA}
EOF
done

echo "[3/7] Creando base de datos y usuario dedicado en MariaDB..."
mariadb -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mariadb -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';"
mariadb -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mariadb -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
mariadb -e "FLUSH PRIVILEGES;"

echo "[4/7] Instalando phpMyAdmin de forma desatendida..."
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password ${PMA_APP_PASS}" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password ${PMA_APP_PASS}" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt-get install -y phpmyadmin

echo "[5/7] Configurando módulos y VirtualHost HTTP en Apache 2..."
a2enmod rewrite ssl headers >/dev/null
echo "ServerName ${DOMINIO}" > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null
sed "s/__DOMINIO__/${DOMINIO}/g" "$RAIZ_REPO/conf/000-default.conf" > /etc/apache2/sites-available/000-default.conf
apache2ctl configtest
systemctl restart apache2

echo "[6/7] Configurando cortafuegos UFW (SSH en NAT, HTTP 80 y HTTPS 443)..."
IF_NAT=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow in on "$IF_NAT" to any port 22 proto tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "[7/7] Pila LAMP, phpMyAdmin y UFW operativos."
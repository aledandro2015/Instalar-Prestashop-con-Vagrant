#!/bin/bash
set -euo pipefail

MODO="${1:-todo}"
DIR="/vagrant/scripts"
RAIZ_WEB="/var/www/html"

set -a
source "$DIR/.env"
[[ -f "$DIR/.env.local" ]] && source "$DIR/.env.local"
set +a

for var in DB_PASS PS_ADMIN_EMAIL PS_ADMIN_PASS; do
  if [[ "${!var}" == CAMBIAR* ]]; then
    echo "ERROR: define ${var} en scripts/.env.local" >&2
    exit 1
  fi
done

if [[ "$MODO" == "preparar" || "$MODO" == "todo" ]]; then
  TEMPORAL="$(mktemp -d)"

  echo "[1/3] Descargando PrestaShop ${PS_VERSION}..."
  curl -fL -o "$TEMPORAL/prestashop.zip" \
    "https://assets.prestashop3.com/dst/edition/corporate/${PS_VERSION}/prestashop_edition_classic_version_${PS_VERSION}.zip?source=vagrant"

  echo "[2/3] Descomprimiendo archivos en ${RAIZ_WEB}..."
  unzip -oq "$TEMPORAL/prestashop.zip" -d "$TEMPORAL/paquete"
  rm -rf "${RAIZ_WEB:?}"/*
  unzip -oq "$TEMPORAL/paquete/prestashop.zip" -d "$RAIZ_WEB"
  rm -rf "$TEMPORAL"

  echo "[3/3] Desplegando PhpPsInfo con credenciales personalizadas..."
  curl -fsSL -o "$RAIZ_WEB/phppsinfo.php" \
    "https://raw.githubusercontent.com/PrestaShop/php-ps-info/master/phppsinfo.php"
  sed -i "s/const DEFAULT_LOGIN = '[^']*';/const DEFAULT_LOGIN = 'psinfo';/" "$RAIZ_WEB/phppsinfo.php"
  sed -i "s/const DEFAULT_PASSWORD = '[^']*';/const DEFAULT_PASSWORD = '${PS_ADMIN_PASS}';/" "$RAIZ_WEB/phppsinfo.php"

  chown -R www-data:www-data "$RAIZ_WEB"
  echo "Auditoría lista en: https://${DOMINIO}/phppsinfo.php (usuario: psinfo)"
fi

if [[ "$MODO" == "instalar" || "$MODO" == "todo" ]]; then
  echo "[1/2] Ejecutando instalación CLI de PrestaShop..."
  cd "$RAIZ_WEB/install"
  runuser -u www-data -- php index_cli.php \
    --domain="${DOMINIO}" \
    --ssl=1 \
    --db_server="localhost" \
    --db_name="${DB_NAME}" \
    --db_user="${DB_USER}" \
    --db_password="${DB_PASS}" \
    --prefix="ad_" \
    --name="${PS_NOMBRE_TIENDA}" \
    --firstname="${PS_NOMBRE_ADMIN}" \
    --lastname="${PS_APELLIDOS_ADMIN}" \
    --email="${PS_ADMIN_EMAIL}" \
    --password="${PS_ADMIN_PASS}" \
    --country="${PS_PAIS}" \
    --language="${PS_IDIOMA}" \
    --timezone="${PS_ZONA_HORARIA}"
  cd /

  echo "[2/2] Limpieza de seguridad (install/, phppsinfo.php y directorio admin)..."
  rm -rf "$RAIZ_WEB/install" "$RAIZ_WEB/phppsinfo.php"
  if [[ -d "$RAIZ_WEB/admin" ]]; then
    mv "$RAIZ_WEB/admin" "$RAIZ_WEB/admin_alejandro"
  fi
  chown -R www-data:www-data "$RAIZ_WEB"
  systemctl reload apache2

  DIR_ADMIN=$(find "$RAIZ_WEB" -maxdepth 1 -type d -name "admin*" -printf "%f\n" | head -n1)
  echo "PrestaShop instalado correctamente."
  echo "Front-Office: https://${DOMINIO}"
  echo "Back-Office:  https://${DOMINIO}/${DIR_ADMIN}/"
fi
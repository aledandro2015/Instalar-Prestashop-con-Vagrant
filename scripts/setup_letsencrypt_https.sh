#!/bin/bash
set -euo pipefail

DIR="/vagrant/scripts"
RAIZ_REPO="/vagrant"

set -a
source "$DIR/.env"
[[ -f "$DIR/.env.local" ]] && source "$DIR/.env.local"
set +a

: "${DUCKDNS_TOKEN:?ERROR: exporta DUCKDNS_TOKEN en el equipo anfitrión}"
if [[ "${LE_EMAIL}" == CAMBIAR* ]]; then
  echo "ERROR: define LE_EMAIL en scripts/.env.local" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
DIR_HOOKS="/etc/letsencrypt/duckdns"

echo "[1/4] Instalando Certbot..."
apt-get update -y
apt-get install -y certbot curl

echo "[2/4] Configurando hooks de validación DNS-01 con DuckDNS..."
install -d -m 700 "$DIR_HOOKS"
printf 'DUCKDNS_TOKEN=%s\n' "$DUCKDNS_TOKEN" > "$DIR_HOOKS/duckdns.env"
chmod 600 "$DIR_HOOKS/duckdns.env"

cat > "$DIR_HOOKS/auth-hook.sh" <<'EOF'
#!/bin/bash
set -e
source /etc/letsencrypt/duckdns/duckdns.env
SUB="${CERTBOT_DOMAIN%.duckdns.org}"
[[ "$(curl -s "https://www.duckdns.org/update?domains=${SUB}&token=${DUCKDNS_TOKEN}&txt=${CERTBOT_VALIDATION}")" = "OK" ]]
sleep 30
EOF

cat > "$DIR_HOOKS/cleanup-hook.sh" <<'EOF'
#!/bin/bash
source /etc/letsencrypt/duckdns/duckdns.env
SUB="${CERTBOT_DOMAIN%.duckdns.org}"
curl -s "https://www.duckdns.org/update?domains=${SUB}&token=${DUCKDNS_TOKEN}&txt=clear&clear=true" > /dev/null
EOF

install -d /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-apache.sh <<'EOF'
#!/bin/bash
systemctl reload apache2 || true
EOF

chmod 700 "$DIR_HOOKS/auth-hook.sh" "$DIR_HOOKS/cleanup-hook.sh"
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-apache.sh

echo "[3/4] Solicitando certificado Let's Encrypt para ${DOMINIO}..."
OPCION_STAGING=()
if [[ "${LE_STAGING}" == "true" ]]; then
  OPCION_STAGING=(--staging)
fi

RENOVACION="/etc/letsencrypt/renewal/${DOMINIO}.conf"
if [[ "${LE_STAGING}" != "true" && -f "$RENOVACION" ]] && grep -q "staging" "$RENOVACION"; then
  certbot delete --cert-name "$DOMINIO" --non-interactive
fi

certbot certonly --manual --preferred-challenges dns \
  --manual-auth-hook "$DIR_HOOKS/auth-hook.sh" \
  --manual-cleanup-hook "$DIR_HOOKS/cleanup-hook.sh" \
  -d "$DOMINIO" --cert-name "$DOMINIO" \
  --email "$LE_EMAIL" --agree-tos --no-eff-email \
  --non-interactive --keep-until-expiring \
  "${OPCION_STAGING[@]}"

echo "[4/4] Activando VirtualHost HTTPS y redirección permanente HTTP -> HTTPS..."
sed -e "s/__DOMINIO__/${DOMINIO}/g" \
    -e "/ServerName/a \    Redirect permanent / https://${DOMINIO}/" \
    "$RAIZ_REPO/conf/000-default.conf" > /etc/apache2/sites-available/000-default.conf

sed "s/__DOMINIO__/${DOMINIO}/g" "$RAIZ_REPO/conf/default-ssl.conf" > /etc/apache2/sites-available/default-ssl.conf
a2ensite default-ssl.conf >/dev/null
apache2ctl configtest
systemctl reload apache2

echo "HTTPS activo en https://${DOMINIO}"
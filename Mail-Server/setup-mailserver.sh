#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAIL_DIR="$SCRIPT_DIR"
ZAPAUTH_DIR="$ROOT_DIR/ZapAuth"
ZAPFOOD_DIR="$ROOT_DIR/ZapFood"
CONFIG_DIR="$MAIL_DIR/docker-data/dms/config"
SECRETS_FILE="$MAIL_DIR/.setup-secrets.env"
MAIL_ENV_FILE="$MAIL_DIR/.env"
ZAPAUTH_ENV_FILE="$ZAPAUTH_DIR/.env"
IMAGE="ghcr.io/docker-mailserver/docker-mailserver:latest"

DEFAULT_DOMAIN="zapcode.ch"
DEFAULT_HOSTNAME="mail.zapcode.ch"
DEFAULT_POSTMASTER="admin@zapcode.ch"
DEFAULT_MAILBOX="noreply@zapcode.ch"
DEFAULT_KEYCLOAK_REALM="zapfood"
DEFAULT_KEYCLOAK_ADMIN_USERNAME="admin"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but was not found." >&2
  exit 1
fi

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr -d '\n'
    return
  fi

  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

read_env_value() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return
  fi

  grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2-
}

ensure_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"

  touch "$file"

  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

compose_up() {
  local dir="$1"
  (
    cd "$dir"
    docker compose up -d
  )
}

compose_exec() {
  local dir="$1"
  shift
  (
    cd "$dir"
    docker compose exec -T "$@"
  )
}

detect_realm() {
  local match

  if [[ -f "$ZAPFOOD_DIR/docker-compose.yml" ]]; then
    match="$(grep -o 'realms/[A-Za-z0-9._-]*' "$ZAPFOOD_DIR/docker-compose.yml" | head -n 1 | cut -d/ -f2 || true)"
    if [[ -n "$match" ]]; then
      printf '%s\n' "$match"
      return
    fi
  fi

  printf '%s\n' "$DEFAULT_KEYCLOAK_REALM"
}

mkdir -p "$CONFIG_DIR"

touch "$SECRETS_FILE"

if [[ -s "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi

DOMAIN="${MAIL_DOMAIN:-${MAIL_DOMAIN_VALUE:-$DEFAULT_DOMAIN}}"
HOSTNAME_FQDN="${MAIL_HOSTNAME:-${MAIL_HOSTNAME_VALUE:-$DEFAULT_HOSTNAME}}"
POSTMASTER="${POSTMASTER_ADDRESS:-${POSTMASTER_ADDRESS_VALUE:-$DEFAULT_POSTMASTER}}"
MAILBOX="${MAILBOX_ADDRESS:-${MAILBOX_ADDRESS_VALUE:-$DEFAULT_MAILBOX}}"
MAILBOX_PASSWORD="${MAILBOX_PASSWORD:-${MAILBOX_PASSWORD_VALUE:-}}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-${KEYCLOAK_REALM_VALUE:-$(detect_realm)}}"
EXISTING_KEYCLOAK_ADMIN_USERNAME="$(read_env_value "$ZAPAUTH_ENV_FILE" "KC_BOOTSTRAP_ADMIN_USERNAME")"
EXISTING_KEYCLOAK_ADMIN_PASSWORD="$(read_env_value "$ZAPAUTH_ENV_FILE" "KC_BOOTSTRAP_ADMIN_PASSWORD")"
KEYCLOAK_ADMIN_USERNAME="${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN_USERNAME_VALUE:-${EXISTING_KEYCLOAK_ADMIN_USERNAME:-$DEFAULT_KEYCLOAK_ADMIN_USERNAME}}}"
KEYCLOAK_ADMIN_PASSWORD="${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD_VALUE:-${EXISTING_KEYCLOAK_ADMIN_PASSWORD:-}}}"

if [[ -z "$MAILBOX_PASSWORD" ]]; then
  MAILBOX_PASSWORD="$(generate_password)"
fi

if [[ -z "$KEYCLOAK_ADMIN_PASSWORD" ]]; then
  KEYCLOAK_ADMIN_PASSWORD="$(generate_password)"
fi

cat >"$SECRETS_FILE" <<EOF
MAIL_DOMAIN_VALUE=$DOMAIN
MAIL_HOSTNAME_VALUE=$HOSTNAME_FQDN
POSTMASTER_ADDRESS_VALUE=$POSTMASTER
MAILBOX_ADDRESS_VALUE=$MAILBOX
MAILBOX_PASSWORD_VALUE=$MAILBOX_PASSWORD
KEYCLOAK_REALM_VALUE=$KEYCLOAK_REALM
KEYCLOAK_ADMIN_USERNAME_VALUE=$KEYCLOAK_ADMIN_USERNAME
KEYCLOAK_ADMIN_PASSWORD_VALUE=$KEYCLOAK_ADMIN_PASSWORD
EOF

chmod 600 "$SECRETS_FILE"

ensure_env_value "$MAIL_ENV_FILE" "OVERRIDE_HOSTNAME" "$HOSTNAME_FQDN"
ensure_env_value "$MAIL_ENV_FILE" "POSTMASTER_ADDRESS" "$POSTMASTER"
ensure_env_value "$ZAPAUTH_ENV_FILE" "KC_BOOTSTRAP_ADMIN_USERNAME" "$KEYCLOAK_ADMIN_USERNAME"
ensure_env_value "$ZAPAUTH_ENV_FILE" "KC_BOOTSTRAP_ADMIN_PASSWORD" "$KEYCLOAK_ADMIN_PASSWORD"

echo "Mailserver setup"
echo "Domain: $DOMAIN"
echo "Host: $HOSTNAME_FQDN"
echo "Mailbox: $MAILBOX"
echo "Realm: $KEYCLOAK_REALM"
echo "Secrets file: $SECRETS_FILE"

echo "Creating mailbox account..."
if ! docker run --rm \
  -v "$CONFIG_DIR:/tmp/docker-mailserver" \
  "$IMAGE" \
  setup email add "$MAILBOX" "$MAILBOX_PASSWORD"; then
  docker run --rm \
    -v "$CONFIG_DIR:/tmp/docker-mailserver" \
    "$IMAGE" \
    setup email update "$MAILBOX" "$MAILBOX_PASSWORD"
fi

echo "Generating DKIM keys..."
docker run --rm \
  -v "$CONFIG_DIR:/tmp/docker-mailserver" \
  "$IMAGE" \
  setup config dkim

echo "Starting mail server..."
compose_up "$MAIL_DIR"

echo "Starting Keycloak..."
compose_up "$ZAPAUTH_DIR"

echo "Waiting for Keycloak admin API..."
for _ in $(seq 1 60); do
  if compose_exec "$ZAPAUTH_DIR" keycloak /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user "$KEYCLOAK_ADMIN_USERNAME" \
    --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1; then
    break
  fi

  sleep 5
done

if ! compose_exec "$ZAPAUTH_DIR" keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USERNAME" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1; then
  echo "Keycloak admin login failed." >&2
  echo "If Keycloak was already initialized with different admin credentials, update $ZAPAUTH_ENV_FILE and rerun the script." >&2
  exit 1
fi

echo "Ensuring Keycloak realm exists..."
if ! compose_exec "$ZAPAUTH_DIR" keycloak /opt/keycloak/bin/kcadm.sh get "realms/$KEYCLOAK_REALM" >/dev/null 2>&1; then
  compose_exec "$ZAPAUTH_DIR" keycloak /opt/keycloak/bin/kcadm.sh create realms \
    -s "realm=$KEYCLOAK_REALM" \
    -s "enabled=true" >/dev/null
fi

echo "Configuring Keycloak SMTP..."
compose_exec "$ZAPAUTH_DIR" keycloak /opt/keycloak/bin/kcadm.sh update "realms/$KEYCLOAK_REALM" \
  -s "smtpServer.host=mailserver" \
  -s "smtpServer.port=587" \
  -s "smtpServer.from=$MAILBOX" \
  -s "smtpServer.auth=true" \
  -s "smtpServer.user=$MAILBOX" \
  -s "smtpServer.password=$MAILBOX_PASSWORD" \
  -s "smtpServer.starttls=true" \
  -s "smtpServer.ssl=false" >/dev/null

echo
echo "Setup complete."
echo
echo "Created mailbox credentials for Keycloak and applied SMTP settings to realm $KEYCLOAK_REALM."
echo "Stored generated secrets in: $SECRETS_FILE"
echo
echo "External DNS that still must exist for reliable delivery:"
echo "MX    $DOMAIN -> $HOSTNAME_FQDN"
echo "A     $HOSTNAME_FQDN -> <server-ip>"
echo "SPF   $DOMAIN -> \"v=spf1 mx -all\""
echo "DMARC _dmarc.$DOMAIN -> \"v=DMARC1; p=quarantine; rua=mailto:$POSTMASTER\""
echo "DKIM  publish the record from $CONFIG_DIR/opendkim/keys/$DOMAIN/mail.txt"

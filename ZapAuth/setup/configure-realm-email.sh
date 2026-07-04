#!/bin/sh

set -eu

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-zapfood}"
KEYCLOAK_CREATE_REALM_IF_MISSING="${KEYCLOAK_CREATE_REALM_IF_MISSING:-true}"
BOOTSTRAP_ADMIN_USERNAME="${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}"
BOOTSTRAP_ADMIN_PASSWORD="${KC_BOOTSTRAP_ADMIN_PASSWORD:-replace-me}"
BOOTSTRAP_ADMIN_EMAIL="${KC_BOOTSTRAP_ADMIN_EMAIL:-admin@zapcode.ch}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-zapfood-web}"
KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"
KEYCLOAK_CLIENT_ROOT_URL="${KEYCLOAK_CLIENT_ROOT_URL:-https://zapcode.ch}"
KEYCLOAK_CLIENT_REDIRECT_URIS="${KEYCLOAK_CLIENT_REDIRECT_URIS:-[\"https://zapcode.ch/*\"]}"
KEYCLOAK_CLIENT_WEB_ORIGINS="${KEYCLOAK_CLIENT_WEB_ORIGINS:-[\"https://zapcode.ch\"]}"
KEYCLOAK_REGISTRATION_ALLOWED="${KEYCLOAK_REGISTRATION_ALLOWED:-true}"
KEYCLOAK_SSL_REQUIRED="${KEYCLOAK_SSL_REQUIRED:-none}"
KEYCLOAK_TOTP_ENABLED="${KEYCLOAK_TOTP_ENABLED:-false}"
KEYCLOAK_TOTP_ENFORCE_FOR_USERS="${KEYCLOAK_TOTP_ENFORCE_FOR_USERS:-false}"
KEYCLOAK_TOTP_ISSUER="${KEYCLOAK_TOTP_ISSUER:-ZapAuth}"
KEYCLOAK_TOTP_TYPE="${KEYCLOAK_TOTP_TYPE:-totp}"
KEYCLOAK_TOTP_ALGORITHM="${KEYCLOAK_TOTP_ALGORITHM:-HmacSHA1}"
KEYCLOAK_TOTP_DIGITS="${KEYCLOAK_TOTP_DIGITS:-6}"
KEYCLOAK_TOTP_PERIOD="${KEYCLOAK_TOTP_PERIOD:-30}"
KEYCLOAK_TOTP_LOOK_AHEAD_WINDOW="${KEYCLOAK_TOTP_LOOK_AHEAD_WINDOW:-1}"
KEYCLOAK_TOTP_REUSABLE_CODE="${KEYCLOAK_TOTP_REUSABLE_CODE:-false}"

echo "Waiting for Keycloak admin login at ${KEYCLOAK_URL}..."
attempts=0
until /opt/keycloak/bin/kcadm.sh config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm master \
  --user "${BOOTSTRAP_ADMIN_USERNAME}" \
  --password "${BOOTSTRAP_ADMIN_PASSWORD}" >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  if [ "${attempts}" -ge 60 ]; then
    echo "Keycloak did not become ready in time" >&2
    exit 1
  fi
  sleep 5
done

if /opt/keycloak/bin/kcadm.sh get "realms/${KEYCLOAK_REALM}" >/dev/null 2>&1; then
  echo "Realm ${KEYCLOAK_REALM} found."
elif [ "${KEYCLOAK_CREATE_REALM_IF_MISSING}" = "true" ]; then
  echo "Realm ${KEYCLOAK_REALM} not found. Creating it..."
  /opt/keycloak/bin/kcadm.sh create realms \
    -s "realm=${KEYCLOAK_REALM}" \
    -s "enabled=true" >/dev/null
else
  echo "Realm ${KEYCLOAK_REALM} was not found and auto-creation is disabled." >&2
  exit 1
fi

ADMIN_USER_ID=$(
  /opt/keycloak/bin/kcadm.sh get users \
    -r master \
    -q "username=${BOOTSTRAP_ADMIN_USERNAME}" \
    | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
)

if [ -n "${ADMIN_USER_ID}" ]; then
  echo "Setting email for bootstrap admin ${BOOTSTRAP_ADMIN_USERNAME}..."
  /opt/keycloak/bin/kcadm.sh update "users/${ADMIN_USER_ID}" \
    -r master \
    -s "email=${BOOTSTRAP_ADMIN_EMAIL}" \
    -s "emailVerified=true" >/dev/null
else
  echo "Bootstrap admin user ${BOOTSTRAP_ADMIN_USERNAME} was not found in realm master." >&2
  exit 1
fi

echo "Configuring realm settings for ${KEYCLOAK_REALM}..."
/opt/keycloak/bin/kcadm.sh update "realms/${KEYCLOAK_REALM}" \
  -s "registrationAllowed=${KEYCLOAK_REGISTRATION_ALLOWED}" \
  -s "sslRequired=${KEYCLOAK_SSL_REQUIRED}" \
  -s "smtpServer.host=${KC_SMTP_HOST:-mail.zapcode.ch}" \
  -s "smtpServer.port=${KC_SMTP_PORT:-587}" \
  -s "smtpServer.from=${KC_SMTP_FROM:-no-reply@zapcode.ch}" \
  -s "smtpServer.fromDisplayName=${KC_SMTP_FROM_DISPLAY_NAME:-ZapAuth}" \
  -s "smtpServer.replyTo=${KC_SMTP_REPLY_TO:-no-reply@zapcode.ch}" \
  -s "smtpServer.auth=${KC_SMTP_AUTH:-true}" \
  -s "smtpServer.starttls=${KC_SMTP_STARTTLS:-true}" \
  -s "smtpServer.ssl=${KC_SMTP_SSL:-false}" \
  -s "smtpServer.user=${KC_SMTP_USER:-no-reply@zapcode.ch}" \
  -s "smtpServer.password=${KC_SMTP_PASSWORD:-replace-me}"

echo "Realm settings applied to ${KEYCLOAK_REALM}."

if [ "${KEYCLOAK_TOTP_ENABLED}" = "true" ]; then
  echo "Enabling TOTP policy for realm ${KEYCLOAK_REALM}..."
  /opt/keycloak/bin/kcadm.sh update "realms/${KEYCLOAK_REALM}" \
    -s "otpPolicyType=${KEYCLOAK_TOTP_TYPE}" \
    -s "otpPolicyAlgorithm=${KEYCLOAK_TOTP_ALGORITHM}" \
    -s "otpPolicyDigits=${KEYCLOAK_TOTP_DIGITS}" \
    -s "otpPolicyPeriod=${KEYCLOAK_TOTP_PERIOD}" \
    -s "otpPolicyLookAheadWindow=${KEYCLOAK_TOTP_LOOK_AHEAD_WINDOW}" \
    -s "otpPolicyCodeReusable=${KEYCLOAK_TOTP_REUSABLE_CODE}" \
    -s "otpPolicyIssuer=${KEYCLOAK_TOTP_ISSUER}" >/dev/null

  REQUIRED_ACTION_DEFAULT="false"
  if [ "${KEYCLOAK_TOTP_ENFORCE_FOR_USERS}" = "true" ]; then
    REQUIRED_ACTION_DEFAULT="true"
  fi

  REQUIRED_ACTION_ALIAS=""
  for alias in CONFIGURE_TOTP CONFIGURE_OTP; do
    if /opt/keycloak/bin/kcadm.sh get "authentication/required-actions/${alias}" -r "${KEYCLOAK_REALM}" >/dev/null 2>&1; then
      REQUIRED_ACTION_ALIAS="${alias}"
      break
    fi
  done

  if [ -n "${REQUIRED_ACTION_ALIAS}" ]; then
    echo "Updating required action ${REQUIRED_ACTION_ALIAS}..."
    /opt/keycloak/bin/kcadm.sh update "authentication/required-actions/${REQUIRED_ACTION_ALIAS}" \
      -r "${KEYCLOAK_REALM}" \
      -s "enabled=true" \
      -s "defaultAction=${REQUIRED_ACTION_DEFAULT}" \
      -s "priority=10" >/dev/null
  else
    echo "Warning: could not find Keycloak required action alias for TOTP configuration." >&2
  fi
fi

CLIENT_ID=$(
  /opt/keycloak/bin/kcadm.sh get clients \
    -r "${KEYCLOAK_REALM}" \
    -q "clientId=${KEYCLOAK_CLIENT_ID}" \
    | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
)

if [ -n "${CLIENT_ID}" ]; then
  echo "Client ${KEYCLOAK_CLIENT_ID} found. Updating configuration..."
  /opt/keycloak/bin/kcadm.sh update "clients/${CLIENT_ID}" \
    -r "${KEYCLOAK_REALM}" \
    -s "clientId=${KEYCLOAK_CLIENT_ID}" \
    -s "name=${KEYCLOAK_CLIENT_ID}" \
    -s "enabled=true" \
    -s "protocol=openid-connect" \
    -s "publicClient=false" \
    -s "secret=${KEYCLOAK_CLIENT_SECRET}" \
    -s "standardFlowEnabled=true" \
    -s "directAccessGrantsEnabled=false" \
    -s "serviceAccountsEnabled=false" \
    -s "frontchannelLogout=true" \
    -s "rootUrl=${KEYCLOAK_CLIENT_ROOT_URL}" \
    -s "baseUrl=${KEYCLOAK_CLIENT_ROOT_URL}" \
    -s "redirectUris=${KEYCLOAK_CLIENT_REDIRECT_URIS}" \
    -s "webOrigins=${KEYCLOAK_CLIENT_WEB_ORIGINS}" >/dev/null
else
  echo "Client ${KEYCLOAK_CLIENT_ID} not found. Creating it..."
  /opt/keycloak/bin/kcadm.sh create clients \
    -r "${KEYCLOAK_REALM}" \
    -s "clientId=${KEYCLOAK_CLIENT_ID}" \
    -s "name=${KEYCLOAK_CLIENT_ID}" \
    -s "enabled=true" \
    -s "protocol=openid-connect" \
    -s "publicClient=false" \
    -s "secret=${KEYCLOAK_CLIENT_SECRET}" \
    -s "standardFlowEnabled=true" \
    -s "directAccessGrantsEnabled=false" \
    -s "serviceAccountsEnabled=false" \
    -s "frontchannelLogout=true" \
    -s "rootUrl=${KEYCLOAK_CLIENT_ROOT_URL}" \
    -s "baseUrl=${KEYCLOAK_CLIENT_ROOT_URL}" \
    -s "redirectUris=${KEYCLOAK_CLIENT_REDIRECT_URIS}" \
    -s "webOrigins=${KEYCLOAK_CLIENT_WEB_ORIGINS}" >/dev/null
fi

echo "OIDC client ${KEYCLOAK_CLIENT_ID} is configured in realm ${KEYCLOAK_REALM}."

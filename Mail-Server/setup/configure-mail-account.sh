#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${PROJECT_DIR}/.env"

if [ -f "${ENV_FILE}" ]; then
  # Load default values for the mail account from the project env file.
  set -a
  . "${ENV_FILE}"
  set +a
fi

MAILSERVER_SERVICE="${MAILSERVER_SERVICE:-mailserver}"
MAIL_ACCOUNT="${MAIL_ACCOUNT:-no-reply@zapcode.ch}"
MAIL_ACCOUNT_PASSWORD="${MAIL_ACCOUNT_PASSWORD:-replace-me}"

if [ "${MAIL_ACCOUNT_PASSWORD}" = "replace-me" ]; then
  echo "MAIL_ACCOUNT_PASSWORD is still set to the placeholder value. Update Mail-Server/.env first." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not installed." >&2
  exit 1
fi

if ! docker compose ps --status running "${MAILSERVER_SERVICE}" >/dev/null 2>&1; then
  echo "Mailserver service '${MAILSERVER_SERVICE}' is not running. Start it with 'docker compose up -d ${MAILSERVER_SERVICE}'." >&2
  exit 1
fi

echo "Checking whether mailbox ${MAIL_ACCOUNT} already exists..."
if docker compose exec -T "${MAILSERVER_SERVICE}" setup email list 2>/dev/null | grep -Fx "${MAIL_ACCOUNT}" >/dev/null 2>&1; then
  echo "Updating password for ${MAIL_ACCOUNT}..."
  docker compose exec -T "${MAILSERVER_SERVICE}" setup email update "${MAIL_ACCOUNT}" "${MAIL_ACCOUNT_PASSWORD}"
else
  echo "Creating mailbox ${MAIL_ACCOUNT}..."
  docker compose exec -T "${MAILSERVER_SERVICE}" setup email add "${MAIL_ACCOUNT}" "${MAIL_ACCOUNT_PASSWORD}"
fi

echo "Mailbox ${MAIL_ACCOUNT} is configured."

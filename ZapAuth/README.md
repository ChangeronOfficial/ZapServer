# ZapAuth

`ZapAuth` uses Keycloak behind `auth.zapcode.ch`. Outgoing emails such as password resets,
verification emails, and admin notifications are sent through the SMTP server for
`mail.zapcode.ch` on the shared Docker network.

## SMTP configuration

Set the following values in [`.env`](/workspaces/ZapServer/ZapAuth/.env:1):

- `KEYCLOAK_REALM`: realm whose email settings should be updated, default `zapfood`
- `KEYCLOAK_CREATE_REALM_IF_MISSING`: create the realm automatically if it does not exist, default `true`
- `KEYCLOAK_CLIENT_ID`: OIDC client to create or update, default `zapfood-web`
- `KEYCLOAK_CLIENT_SECRET`: secret assigned to the confidential OIDC client
- `KEYCLOAK_CLIENT_ROOT_URL`: application base URL used for Keycloak client metadata
- `KEYCLOAK_CLIENT_REDIRECT_URIS`: JSON array of allowed redirect URIs
- `KEYCLOAK_CLIENT_WEB_ORIGINS`: JSON array of allowed web origins
- `KEYCLOAK_REGISTRATION_ALLOWED`: enable self-service user registration, default `true`
- `KC_BOOTSTRAP_ADMIN_EMAIL`: email address assigned to the bootstrap admin user, default `admin@zapcode.ch`
- `KC_SMTP_HOST`: SMTP host, default `mail.zapcode.ch`
- `KC_SMTP_PORT`: SMTP port, default `587`
- `KC_SMTP_FROM`: envelope/header sender, default `no-reply@zapcode.ch`
- `KC_SMTP_FROM_DISPLAY_NAME`: display name, default `ZapAuth`
- `KC_SMTP_REPLY_TO`: reply-to address, default `no-reply@zapcode.ch`
- `KC_SMTP_AUTH`: enable SMTP auth, default `true`
- `KC_SMTP_STARTTLS`: enable STARTTLS, default `true`
- `KC_SMTP_SSL`: direct SSL/TLS, default `false`
- `KC_SMTP_USER`: SMTP username
- `KC_SMTP_PASSWORD`: SMTP password

The `configure-realm-email` service uses `kcadm.sh` to write these settings into the target
Keycloak realm. It also ensures the configured OIDC client exists and explicitly sets whether
self-service registration is enabled. This is required because Keycloak stores realm and client
settings internally instead of reading them directly from generic server environment variables.

## Mailserver prerequisites

Before deploying `ZapAuth`, create a dedicated SMTP account on the mailserver:

- Recommended account: `no-reply@zapcode.ch`
- SMTP transport: port `587` with `STARTTLS`
- SMTP hostname for clients: `mail.zapcode.ch`
- Internal Docker alias also available: `mailserver`

Use `mail.zapcode.ch` for `KC_SMTP_HOST` so Keycloak validates the certificate against the
hostname present in the mailserver TLS certificate. Using the Docker alias `mailserver` with
STARTTLS causes certificate hostname verification to fail.

Keep the mailbox dedicated to application email. Do not use it as the human admin mailbox.

## Deploy and verify

Start or refresh `ZapAuth`:

```bash
docker compose up -d keyclock-db keycloak configure-realm-email
```

Then verify in Keycloak:

1. Open `Realm settings -> Email` for the configured realm.
2. Confirm the SMTP values match `.env`.
3. Open `Clients` and confirm the configured `KEYCLOAK_CLIENT_ID` exists.
4. Use `Test connection` to send a test email.
5. Run one password reset and one verification flow.

## Operational notes

- Rotate `KC_BOOTSTRAP_ADMIN_PASSWORD` and `KC_SMTP_PASSWORD` before production use.
- Ensure SPF, DKIM, and DMARC are configured for `zapcode.ch` so Keycloak emails are delivered.
- This setup is for outbound email only; the mailserver is not used as a user authentication backend.

# ZapAuth

`ZapAuth` uses Keycloak behind `auth.zapcode.ch`. Outgoing emails such as password resets,
verification emails, and admin notifications are sent through the SMTP server at
`mail.zapcode.ch`.

## SMTP configuration

Set the following values in [`.env`](/workspaces/ZapServer/ZapAuth/.env:1):

- `KEYCLOAK_REALM`: realm whose email settings should be updated, default `zapfood`
- `KEYCLOAK_CREATE_REALM_IF_MISSING`: create the realm automatically if it does not exist, default `true`
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
Keycloak realm. This is required because Keycloak stores email settings per realm instead of
reading them directly from generic server environment variables.

## Mailserver prerequisites

Before deploying `ZapAuth`, create a dedicated SMTP account on the mailserver:

- Recommended account: `no-reply@zapcode.ch`
- SMTP transport: port `587` with `STARTTLS`
- Hostname: `mail.zapcode.ch`

Keep the mailbox dedicated to application email. Do not use it as the human admin mailbox.

## Deploy and verify

Start or refresh `ZapAuth`:

```bash
docker compose up -d keyclock-db keycloak configure-realm-email
```

Then verify in Keycloak:

1. Open `Realm settings -> Email` for the configured realm.
2. Confirm the SMTP values match `.env`.
3. Use `Test connection` to send a test email.
4. Run one password reset and one verification flow.

## Operational notes

- Rotate `KC_BOOTSTRAP_ADMIN_PASSWORD` and `KC_SMTP_PASSWORD` before production use.
- Ensure SPF, DKIM, and DMARC are configured for `zapcode.ch` so Keycloak emails are delivered.
- This setup is for outbound email only; the mailserver is not used as a user authentication backend.

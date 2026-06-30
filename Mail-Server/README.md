# Mail-Server

`Mail-Server` runs `docker-mailserver` for `zapcode.ch`.

## SMTP mailbox setup

Set the following values in [`.env`](/workspaces/ZapServer/Mail-Server/.env:1):

- `MAIL_ACCOUNT`: mailbox that applications should use for SMTP, default `no-reply@zapcode.ch`
- `MAIL_ACCOUNT_PASSWORD`: mailbox password used by SMTP clients
- `OVERRIDE_HOSTNAME`: public hostname of the mailserver, default `mail.zapcode.ch`

Then start the mailserver and create or update the mailbox:

```bash
docker compose up -d mailserver
./setup/configure-mail-account.sh
```

The script is idempotent:

- if the mailbox does not exist yet, it is created
- if the mailbox already exists, its password is updated

Use the same mailbox and password in [ZapAuth](../ZapAuth/README.md) as `KC_SMTP_USER` and `KC_SMTP_PASSWORD`.

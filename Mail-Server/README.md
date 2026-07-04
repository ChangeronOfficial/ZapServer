# Mail-Server

`Mail-Server` runs `docker-mailserver` for `zapcode.ch`.

## SMTP mailbox setup

Set the following values in [`.env`](/workspaces/ZapServer/Mail-Server/.env:1):

- `MAIL_ACCOUNT`: mailbox that applications should use for SMTP, default `no-reply@zapcode.ch`
- `MAIL_ACCOUNT_PASSWORD`: mailbox password used by SMTP clients
- `OVERRIDE_HOSTNAME`: public hostname of the mailserver, default `mail.zapcode.ch`
- `SSL_CERT_PATH`: full path to the public certificate inside the mounted Caddy data volume
- `SSL_KEY_PATH`: full path to the matching private key inside the mounted Caddy data volume

This setup keeps DKIM handling on `OpenDKIM`. Leave `ENABLE_RSPAMD=0` to avoid running Rspamd
and OpenDKIM in parallel for DKIM-related functionality.

Start Caddy first so it can issue the certificate for `mail.zapcode.ch`, then start the mailserver and create or update the mailbox:

```bash
cd ../Caddy && docker compose up -d caddy
cd ../Mail-Server
docker compose up -d mailserver
./setup/configure-mail-account.sh
```

If Caddy stores certificates under a different ACME directory than
`acme-v02.api.letsencrypt.org-directory`, update `SSL_CERT_PATH` and `SSL_KEY_PATH` in
[`Mail-Server/.env`](/workspaces/ZapServer/Mail-Server/.env:1) to match the actual paths.

The script is idempotent:

- if the mailbox does not exist yet, it is created
- if the mailbox already exists, its password is updated

Use the same mailbox and password in [ZapAuth](../ZapAuth/README.md) as `KC_SMTP_USER` and `KC_SMTP_PASSWORD`.

## Networking

The mailserver publishes the aliases `mailserver`, `mail`, and `mail.zapcode.ch` on the shared
Docker network `zapserver_proxy`.

This allows other stacks such as `ZapAuth` to reach SMTP internally, but TLS-aware SMTP clients
should connect with host `mail.zapcode.ch:587` so certificate hostname verification matches the
issued certificate.

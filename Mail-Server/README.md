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

## DNS records required for delivery

The mailserver can accept SMTP locally as soon as Docker is running, but external providers such as
Gmail will reject mail until `zapcode.ch` publishes aligned SPF, DKIM, and DMARC records.

Recommended baseline records for this stack:

```dns
$TTL 3600
@       IN MX 10 mail.zapcode.ch.
@       IN TXT "v=spf1 mx a:mail.zapcode.ch ip4:144.2.118.54 ip6:2a02:21b4:a603:5a00:a2b5:49ff:fe3e:6000 ~all"
mail    IN A 144.2.118.54
mail    IN AAAA 2a02:21b4:a603:5a00:417d:8a06:dced:8ad
_dmarc  IN TXT "v=DMARC1; p=quarantine; adkim=s; aspf=s; rua=mailto:dmarc@zapcode.ch"
```

Important details:

- Do not keep SPF at `v=spf1 -all`. That explicitly says no host may send mail for `zapcode.ch`.
- Publish the DKIM public key at `selector._domainkey.zapcode.ch`, not as a TXT record on `mail.zapcode.ch`.
- The DKIM signing domain must be `d=zapcode.ch` so it aligns with `From: no-reply@zapcode.ch`.
- Start DMARC with `p=quarantine` or `p=none` while testing. Switch to `p=reject` only after both SPF or DKIM pass reliably.

Example DKIM record shape:

```dns
mail._domainkey IN TXT "v=DKIM1; k=rsa; p=REPLACE_WITH_YOUR_PUBLIC_KEY"
```

The selector in this example is `mail`, so the resulting DNS name is
`mail._domainkey.zapcode.ch`. If you generate a different selector, publish that exact hostname
instead.

## Delivery checklist

Use this short checklist before testing password reset or verification emails:

1. `mail.zapcode.ch` resolves publicly to the same IPv4/IPv6 addresses the server uses to send mail.
2. Reverse DNS for the sending IP points back to `mail.zapcode.ch`.
3. SPF authorizes this host to send for `zapcode.ch`.
4. OpenDKIM signs outbound mail with `d=zapcode.ch`.
5. The DKIM public key is published at `selector._domainkey.zapcode.ch`.
6. DMARC policy is relaxed during rollout and tightened only after successful verification.

If Gmail returns `550 5.7.26 Unauthenticated email ... due to domain's DMARC policy`, one of the
aligned SPF or DKIM checks is still failing.

## Networking

The mailserver publishes the aliases `mailserver`, `mail`, and `mail.zapcode.ch` on the shared
Docker network `zapserver_proxy`.

This allows other stacks such as `ZapAuth` to reach SMTP internally, but TLS-aware SMTP clients
should connect with host `mail.zapcode.ch:587` so certificate hostname verification matches the
issued certificate.

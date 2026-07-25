# ZapServer

Docker-Compose-Konfiguration für die Dienste auf `zapcode.ch`.

| Verzeichnis | Dienst | Adresse/Zugang |
| --- | --- | --- |
| `Caddy` | Reverse Proxy und TLS | Ports 80/443 |
| `Forgejo` | Git-Hosting im LAN | `http://server:3000`, SSH-Port 2222 |
| `Mail-Server` | SMTP/IMAP | `mail.zapcode.ch` |
| `Portainer` | Docker-Verwaltung | Port 9443 |
| `Registry` | Container Registry | Ports 5000/8080 |
| `ZapAuth` | Keycloak | `https://auth.zapcode.ch` |
| `ZapFood` | Webanwendung | `https://zapcode.ch` |

Beim ersten Aufbau zuerst `Caddy` starten. Dadurch wird das gemeinsam verwendete externe
Docker-Netzwerk `zapserver_proxy` angelegt. Die dienstspezifischen Hinweise stehen jeweils
in der `README.md` des Verzeichnisses.

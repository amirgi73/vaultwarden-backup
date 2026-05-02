# Vaultwarden Backup – Dokumentation

Erstellt: 2026-05-02  
Autor: Amir  

---

## 1. Übersicht

Tägliches verschlüsseltes Backup der Vaultwarden-Instanz auf Backblaze B2.

```
Vaultwarden (Docker, SQLite)
    ↓
tar.gz Archiv (im RAM, nie unverschlüsselt auf Disk)
    ↓
GPG-Verschlüsselung (asymmetrisch, public key)
    ↓
Backblaze B2 – Bucket: lopito / Prefix: vw/
```

---

## 2. Backup-Datei

### Dateiname
```
vw_backup_YYYY-MM-DD_HHMMSS.tar.gz.gpg
```
Beispiel: `vw_backup_2026-05-02_030000.tar.gz.gpg`

### Inhalt des Archivs (nach Entschlüsselung)
```
./
├── db.sqlite3          ← Vaultwarden Datenbank (alle Passwörter, Benutzer)
├── config.json         ← Vaultwarden Konfiguration
├── rsa_key.pem         ← RSA Private Key (Vaultwarden-intern)
├── rsa_key.pub.pem     ← RSA Public Key (Vaultwarden-intern)
├── attachments/        ← Dateianhänge (falls vorhanden)
└── sends/              ← Vaultwarden Send-Objekte (falls vorhanden)
```

---

## 3. Verschlüsselung

| Parameter | Wert                           |
|---|--------------------------------|
| Algorithmus | GPG hybrid (Ed25519 + AES-256) |
| Key-Typ | Ed25519 (Curve25519)           |
| Recipient | amir.gi73@gmail.com            |
| Private Key | Auf USB-Stick (APFS encrypted) |

### GPG Fingerprint
```
EE1A9B8673870A9287E1AE6E404C182F3416A4A8
```

---

## 4. Infrastruktur

| Komponente | Detail |
|---|---|
| Cloud | Backblaze B2 |
| Bucket | lopito |
| Prefix | vw/ |
| Object Lock | 30 Tage (Ransomware-Schutz) |
| Lifecycle | Hiding nach 31 Tagen, Löschen nach 1 weiteren Tag |
| Retention | ~32 Backups maximal |
| B2 API-Key | writeOnly (kein Read/Delete möglich) |
| Upload-Tool | rclone |

### Server
| Komponente | Detail |
|---|---|
| Host | Homeserver (Debian) |
| Vaultwarden | Docker Container |
| Datenbank | SQLite |
| Skript | /opt/vaultwarden-backup.sh |
| Systemd Timer | ~/.config/systemd/user/vw-backup.timer |
| Ausführung | täglich 03:00 Uhr (User-Session, linger aktiviert) |

---

## 5. Restore – Schritt für Schritt

### Voraussetzungen
- GPG installiert (`brew install gnupg` auf macOS, `apt install gnupg` auf Debian)
- Private Key verfügbar (USB-Stick)
- Backup-Datei von B2 heruntergeladen (B2-Webkonsole oder rclone mit Read-Key)

### Schritt 1: Private Key importieren
```bash
gpg --import /pfad/zu/vaultwarden_private_key.asc

# Verifizieren
gpg --list-secret-keys
```

### Schritt 2: Backup entschlüsseln
```bash
gpg --decrypt vw_backup_YYYY-MM-DD_HHMMSS.tar.gz.gpg > vw_backup.tar.gz
```

### Schritt 3: Archiv prüfen
```bash
# Inhalt anzeigen ohne zu entpacken
tar -tzf vw_backup.tar.gz
```

### Schritt 4: Entpacken
```bash
mkdir -p /tmp/vw-restore
tar -xzf vw_backup.tar.gz -C /tmp/vw-restore/
```

### Schritt 5: Datenbank verifizieren
```bash
# sqlite3 installieren falls nötig: apt install sqlite3 / brew install sqlite3
sqlite3 /tmp/vw-restore/db.sqlite3 "SELECT COUNT(*) FROM ciphers;"
# → Anzahl der gespeicherten Passwort-Einträge
```

### Schritt 6: Vaultwarden wiederherstellen
```bash
# Vaultwarden-Container stoppen
docker stop vaultwarden

# Daten ersetzen
cp /tmp/vw-restore/db.sqlite3 /pfad/zu/vaultwarden/data/
cp /tmp/vw-restore/config.json /pfad/zu/vaultwarden/data/
cp -r /tmp/vw-restore/attachments /pfad/zu/vaultwarden/data/

# Container starten
docker start vaultwarden
```

---

## 6. Logs prüfen (auf Server)

```bash
# Letzten Backup-Lauf prüfen
journalctl --user -u vw-backup.service -n 50

# Timer-Status
systemctl --user status vw-backup.timer
```

---

## 7. Wichtige Dateien & Speicherorte

| Was                    | Wo                                                 |
|------------------------|----------------------------------------------------|
| Backup-Skript          | `/opt/vaultwarden-backup.sh`                       |
| Systemd Service        | `~/.config/systemd/user/vw-backup.service`         |
| Systemd Timer          | `~/.config/systemd/user/vw-backup.timer`           |
| rclone Config          | `~/.config/rclone/rclone.conf`                     |
| GPG Keyring            | `~/.gnupg/`                                        |
| GPG Private Key Backup | USB-Stick (APFS encrypted), separater sicherer Ort |
| Vaultwarden Data Pfad  | `~/vaultwarden/vw-data/`                           |

---

## 8. Software-Abhängigkeiten

Alle FOSS:

| Tool | Zweck | Installation |
|---|---|---|
| gpg (GnuPG) | Verschlüsselung/Entschlüsselung | `apt install gnupg` / `brew install gnupg` |
| sqlite3 | DB-Backup und Restore-Verifikation | `apt install sqlite3` / `brew install sqlite3` |

| rclone | Upload zu B2 | https://rclone.org |
| tar | Archivierung | vorinstalliert |
| docker | Vaultwarden-Laufzeitumgebung | https://docs.docker.com |

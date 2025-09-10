Jasne 👍 – poniżej masz gotowy, poprawnie sformatowany plik **README.md** w jednym kawałku, bez zbędnych wstawek typu „markdown”, „text”, „bash” poza blokami kodu.

````markdown
# SystemBackup 🗄️

Zaawansowany system backupu dla środowisk WordPress z obsługą Docker i powiadomieniami email.

## 📦 Zawartość repozytorium

- [`autobackup.sh`](autobackup.sh) - Główny skrypt backupu WordPress
- [`autobackup.service`](autobackup.service) - Usługa systemd do automatycznego backupu
- [`backup.conf.example`](backup.conf.example) - Przykładowy plik konfiguracyjny

## ✨ Funkcje

### 🔐 Backup Bazy Danych
- **MySQL/MariaDB** - wsparcie dla kontenerów Docker i lokalnych instalacji  
- **Autodetekcja** - automatyczne wykrywanie źródła bazy danych  
- **Integralność** - walidacja eksportu bazy  

### 📁 Backup Plików
- **WordPress** - pełny backup plików źródłowych  
- **Inteligentne pomijanie** - automatyczne pominięcie katalogu `uploads`  
- **Konfiguracja Docker** - backup pliku `docker-compose.yml`  

### 📧 Powiadomienia
- **Email alerts** - szczegółowe raporty z logami  
- **Monitorowanie** - powiadomienia o błędach i sukcesach  
- **Customizable** - konfigurowalne adresy email  

### 🛡️ Bezpieczeństwo
- **Weryfikacja** - sprawdzanie integralności archiwum  
- **Sumy kontrolne** - SHA256 dla weryfikacji backupów  
- **Retencja** - automatyczne usuwanie starych backupów (7 dni)  

## ⚡ Szybki start

### 1. Klonowanie repozytorium
```bash
git clone https://github.com/Swagrzyk/SystemBackup.git
cd SystemBackup
````

### 2. Konfiguracja

```bash
# Skopiuj przykładową konfigurację
sudo cp backup.conf.example /etc/backup.conf

# Edytuj konfigurację
sudo nano /etc/backup.conf
```

### 3. Uruchomienie ręczne

```bash
# Nadaj uprawnienia wykonania
chmod +x autobackup.sh

# Uruchom backup
./autobackup.sh
```

## ⚙️ Konfiguracja

Plik `/etc/backup.conf`:

```bash
# Database configuration
DB_USER="root"
DB_PASS="your_mysql_password"
DB_NAME="wordpress"

# Email notifications
BACKUP_EMAIL="your@email.com"
FROM_EMAIL="sender@email.com"

# Optional settings
BACKUP_DIR="/home/user/Backups"
RETENTION_DAYS="7"
```

## 🐳 Wymagania systemowe

* Bash 4.0+
* Docker (opcjonalnie)
* MySQL/MariaDB
* mailutils (do powiadomień email)
* Systemd (dla usługi automatycznej)

## 🔧 Instalacja jako usługa

### 1. Instalacja usługi systemd

```bash
sudo cp autobackup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable autobackup.service
sudo systemctl start autobackup.service
```

### 2. Status usługi

```bash
sudo systemctl status autobackup.service
```

### 3. Logi usługi

```bash
journalctl -u autobackup.service -f
```

## 📊 Struktura backupów

```
Backups/
├── urny_backup_20251231_235959.tar.gz      # Archiwum backupu
├── urny_backup_20251231_235959.sha256      # Suma kontrolna
└── backup.log                              # Pełne logi
```

## 🚀 Przykładowe użycie

**Backup ręczny**

```bash
./autobackup.sh
```

**Podgląd logów**

```bash
tail -f /home/ezri/Backups/backup.log
```

**Lista backupów**

```bash
ls -la /home/ezri/Backups/urny_backup_*
```

## 🐛 Rozwiązywanie problemów

**Błąd: Brak konfiguracji**

```bash
sudo cp backup.conf.example /etc/backup.conf
sudo nano /etc/backup.conf
```

**Błąd: Brak uprawnień**

```bash
chmod +x autobackup.sh
sudo chmod 644 /etc/backup.conf
```

**Błąd: Problem z email**

```bash
sudo apt install mailutils
sudo dpkg-reconfigure postfix
```

## 📝 Logi

* Główne logi: `/home/ezri/Backups/backup.log`
* Logi systemd: `journalctl -u autobackup.service`
* Tymczasowe logi: pliki w `/tmp/backup-log-*`

## 🔄 Retencja

Backupy są automatycznie usuwane po 7 dniach:

```bash
find "/home/ezri/Backups" -name "urny_backup_*.tar.gz" -mtime +7 -delete
```

## 📞 Wsparcie

Jeśli napotkasz problemy:

* Sprawdź logi w `/home/ezri/Backups/backup.log`
* Sprawdź status usługi: `sudo systemctl status autobackup.service`
* Sprawdź konfigurację w `/etc/backup.conf`

## 📜 Licencja

MIT License - szczegóły w pliku LICENSE.

```

Chcesz, żebym Ci od razu przygotował plik **README.md** i wysłał gotowy do pobrania, czy wystarczy Ci ta treść do samodzielnego zapisania?
```

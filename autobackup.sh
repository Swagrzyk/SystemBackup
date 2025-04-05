#!/bin/bash

# Konfiguracja
BACKUP_DIR="/home/ezri/Backups"
EMAIL="twojadres"
LOG_FILE="$BACKUP_DIR/backup.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_DIR=$(mktemp -d -p /tmp "backup-${TIMESTAMP}-XXXXXX")

# Funkcja do wysyłania e-mail
send_email() {
    local subject=$1
    local body=$2
    echo "$body" | mail -a "From: zjakiego emaila" -s "$subject" "$EMAIL"
}

# Inicjalizacja logów i folderów
mkdir -p "$BACKUP_DIR"
echo "$(date) - Rozpoczęcie backupu" >> "$LOG_FILE"

# Sprawdzenie czy folder tymczasowy został utworzony
if [ ! -d "$TEMP_DIR" ]; then
    echo "$(date) - Błąd: Nie udało się utworzyć folderu tymczasowego!" >> "$LOG_FILE"
    send_email "Backup URNY - BŁĄD" "Nie udało się utworzyć folderu tymczasowego!"
    exit 1
fi

echo "$(date) - Folder tymczasowy: $TEMP_DIR" >> "$LOG_FILE"

# 1. Backup bazy danych
echo "$(date) - Rozpoczęcie backupu bazy danych" >> "$LOG_FILE"
if ! docker-compose -f ~/urny/docker-compose.yml exec -T db mysqldump --no-tablespaces -u wp_user -pwp_pass wordpress > "$TEMP_DIR/db_backup.sql" 2>> "$LOG_FILE"; then
    echo "$(date) - Błąd backupu bazy danych!" >> "$LOG_FILE"
    send_email "Backup URNY - BŁĄD" "Backup bazy danych nie powiódł się!"
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "$(date) - Backup bazy danych zakończony sukcesem" >> "$LOG_FILE"

# 2. Backup plików WordPressa
echo "$(date) - Rozpoczęcie backupu plików WordPressa" >> "$LOG_FILE"
if ! cp -r ~/urny/src "$TEMP_DIR/wordpress" 2>> "$LOG_FILE"; then
    echo "$(date) - Błąd kopiowania plików WordPressa!" >> "$LOG_FILE"
    send_email "Backup URNY - BŁĄD" "Backup plików WordPressa nie powiódł się!"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Usuń katalog uploads, aby nie backupować plików mediów
if [ -d "$TEMP_DIR/wordpress/wp-content/uploads" ]; then
    rm -rf "$TEMP_DIR/wordpress/wp-content/uploads"
    echo "$(date) - Pominięto katalog uploads" >> "$LOG_FILE"
fi
echo "$(date) - Backup plików WordPressa zakończony sukcesem" >> "$LOG_FILE"

# 3. Backup docker-compose.yml
if ! cp ~/urny/docker-compose.yml "$TEMP_DIR/" 2>> "$LOG_FILE"; then
    echo "$(date) - Błąd kopiowania docker-compose.yml!" >> "$LOG_FILE"
    send_email "Backup URNY - BŁĄD" "Backup docker-compose.yml nie powiódł się!"
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "$(date) - Backup docker-compose.yml zakończony sukcesem" >> "$LOG_FILE"

# 4. Spakuj wszystko
ARCHIVE_NAME="urny_backup_${TIMESTAMP}.tar.gz"
echo "$(date) - Rozpoczęcie tworzenia archiwum $ARCHIVE_NAME" >> "$LOG_FILE"
if ! tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR" . >> "$LOG_FILE" 2>&1; then
    echo "$(date) - Błąd tworzenia archiwum!" >> "$LOG_FILE"
    send_email "Backup URNY - BŁĄD" "Tworzenie archiwum backupu nie powiodło się!"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 5. Wyślij potwierdzenie
SIZE=$(du -h "$BACKUP_DIR/$ARCHIVE_NAME" | cut -f1)
MESSAGE="Backup zakończony sukcesem!
Ścieżka: $BACKUP_DIR/$ARCHIVE_NAME
Rozmiar: $SIZE
Data: $(date)"

echo "$(date) - Backup wykonany: $ARCHIVE_NAME ($SIZE)" >> "$LOG_FILE"
send_email "Backup URNY - Sukces" "$MESSAGE"

# 6. Posprzątaj
rm -rf "$TEMP_DIR"
echo "$(date) - Usunięto folder tymczasowy" >> "$LOG_FILE"

# 7. Usuń stare backupy (starsze niż 7 dni)
echo "$(date) - Usuwanie starych backupów (starszych niż 7 dni)" >> "$LOG_FILE"
find "$BACKUP_DIR" -name "urny_backup_*.tar.gz" -mtime +7 -exec rm -v {} \; >> "$LOG_FILE" 2>&1

echo "$(date) - Backup zakończony pomyślnie" >> "$LOG_FILE"

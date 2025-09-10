#!/bin/bash
set -euo pipefail

### [1] Konfiguracja ###
BACKUP_DIR="/home/ezri/Backups"
LOG_FILE="$BACKUP_DIR/backup.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_DIR=$(mktemp -d -p /tmp "backup-${TIMESTAMP}-XXXXXX")
TEMP_LOG=$(mktemp -p /tmp "backup-log-${TIMESTAMP}-XXXXXX") 
DB_BACKUP_METHOD="" # będzie ustawione: container lub local

### [1.1] Ładowanie konfiguracji ###
CONFIG_FILE="/etc/backup.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "$(date) - BŁĄD: Brak pliku konfiguracyjnego $CONFIG_FILE" >> "$LOG_FILE"
    exit 1
fi
source "$CONFIG_FILE"

### [2] Funkcje ###
log() { 
    local message="$(date) - $1"
    echo "$message" >> "$LOG_FILE"
    echo "$message" >> "$TEMP_LOG"
}
send_alert() {
    local subject="$1"
    local message="$2"
    echo -e "$message" | mail -s "$subject" "$BACKUP_EMAIL"
}

### [3] Inicjalizacja ###
mkdir -p "$BACKUP_DIR"
exec >> "$LOG_FILE" 2>&1
log "=== Rozpoczęcie backupu v2 ==="

### [4] Sprawdzenie dostępności bazy danych ###
log "Sprawdzanie dostępności bazy danych..."

# Najpierw sprawdź kontener Docker używając bezpośrednio docker (szybsze)
DB_CONTAINER=""
log "Sprawdzanie kontenera bazy danych..."

# Sprawdź wszystkie uruchomione kontenery i poszukaj tych które mogą być bazami
DB_CONTAINER=$(docker ps --filter "name=db" --format "{{.ID}}" 2>/dev/null)
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=database" --format "{{.ID}}" 2>/dev/null)
fi
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=mysql" --format "{{.ID}}" 2>/dev/null)
fi
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --filter "name=mariadb" --format "{{.ID}}" 2>/dev/null)
fi

# Dodatkowo sprawdź czy któryś z kontenerów ma port 3306 (standard MySQL)
if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --format "{{.ID}}" | while read id; do
        if docker port "$id" | grep -q "3306"; then
            echo "$id"
            break
        fi
    done)
fi

# Sprawdź czy kontener istnieje i jest uruchomiony
if [ -n "$DB_CONTAINER" ]; then
    CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "not-found")
    if [ "$CONTAINER_STATUS" = "running" ]; then
        log "Znaleziono uruchomiony kontener bazy: $DB_CONTAINER"
        DB_BACKUP_METHOD="container"
    else
        log "Kontener bazy istnieje ale nie jest uruchomiony (status: $CONTAINER_STATUS)"
        DB_CONTAINER=""
    fi
fi

# Jeśli nie ma kontenera, sprawdź lokalną bazę
if [ -z "$DB_CONTAINER" ]; then
    log "Sprawdzanie lokalnej bazy danych..."
    
    # Sprawdź czy MySQL/MariaDB jest uruchomiony
    if systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb; then
        log "Serwer MySQL/MariaDB jest uruchomiony lokalnie"
        
        # Sprawdź połączenie z bazą
        if mysql -h localhost -u root -p"root_pass" -e "USE wordpress;" 2>/dev/null; then
            DB_BACKUP_METHOD="local"
            log "Lokalna baza danych jest dostępna"
        else
            log "Ostrzeżenie: Nie można połączyć się z lokalną bazą wordpress"
        fi
    else
        log "Serwer MySQL/MariaDB nie jest uruchomiony lokalnie"
    fi
fi

# Jeśli żadna metoda nie jest dostępna, zakończ z błędem
if [ -z "$DB_BACKUP_METHOD" ]; then
    log "BŁĄD: Nie znaleziono dostępnej bazy danych (ani w kontenerze, ani lokalnie)"
    log "Lista kontenerów:"
    docker ps -a >> "$LOG_FILE"
    log "Status usług bazodanowych:"
    systemctl status mysql 2>> "$LOG_FILE" | head -10 >> "$LOG_FILE"
    systemctl status mariadb 2>> "$LOG_FILE" | head -10 >> "$LOG_FILE"
    send_alert "Backup URNY - BŁĄD" "Nie znaleziono dostępnej bazy danych (ani w kontenerze, ani lokalnie)"
    exit 1
fi

### [5] Backup bazy danych ###
log "Rozpoczęcie backupu bazy (metoda: $DB_BACKUP_METHOD)..."

if [ "$DB_BACKUP_METHOD" = "container" ]; then
    # Backup z kontenera Docker
    if ! docker exec "$DB_CONTAINER" \
       bash -c 'mysqldump --no-tablespaces -u root -p"root_pass" wordpress' > "$TEMP_DIR/db_backup.sql"; then
        log "BŁĄD: Backup bazy z kontenera nie powiódł się (status: $?)"
        docker logs "$DB_CONTAINER" --tail 50 >> "$LOG_FILE"
        send_alert "Backup URNY - BŁĄD" "Backup bazy z kontenera nie powiódł się"
        exit 1
    fi
else
    # Backup z lokalnej bazy
    if ! mysqldump --no-tablespaces -h localhost -u root -p"root_pass" wordpress > "$TEMP_DIR/db_backup.sql" 2>> "$LOG_FILE"; then
        log "BŁĄD: Backup lokalnej bazy nie powiódł się"
        send_alert "Backup URNY - BŁĄD" "Backup lokalnej bazy nie powiódł się"
        exit 1
    fi
fi

log "Backup bazy udany. Rozmiar: $(du -h "$TEMP_DIR/db_backup.sql" | cut -f1)"

### [6] Backup plików WordPress ###
log "Backup plików WordPress..."
if [ -d ~/urny/src ]; then
    if ! cp -r ~/urny/src "$TEMP_DIR/wordpress"; then
        log "BŁĄD: Kopiowanie plików WordPress nie powiodło się"
        send_alert "Backup URNY - BŁĄD" "Kopiowanie plików WordPress nie powiodło się"
        exit 1
    fi
    log "Backup plików udany. Rozmiar: $(du -sh "$TEMP_DIR/wordpress" | cut -f1)"
else
    log "Ostrzeżenie: Katalog ~/urny/src nie istnieje, pominięto backup plików"
fi

# Pominięcie katalogu uploads
if [ -d "$TEMP_DIR/wordpress/wp-content/uploads" ]; then
    rm -rf "$TEMP_DIR/wordpress/wp-content/uploads"
    log "Pominięto katalog uploads"
fi

### [7] Backup docker-compose.yml ###
log "Backup docker-compose.yml"
if [ -f ~/urny/docker-compose.yml ]; then
    if ! cp ~/urny/docker-compose.yml "$TEMP_DIR/"; then
        log "BŁĄD: Kopiowanie docker-compose.yml nie powiodło się"
        send_alert "Backup URNY - BŁĄD" "Backup docker-compose.yml nie powiódł się!"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
else
    log "Ostrzeżenie: Plik docker-compose.yml nie istniee, pominięto"
fi

### [8] Tworzenie archiwum ###
ARCHIVE_NAME="urny_backup_${TIMESTAMP}.tar.gz"
log "Tworzenie archiwum: $ARCHIVE_NAME"
if ! tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR" .; then
    log "BŁĄD: Tworzenie archiwum nie powiodło się"
    send_alert "Backup URNY - BŁĄD" "Tworzenie archiwum backupu nie powiodło się!"
    rm -rf "$TEMP_DIR"
    exit 1
fi

### [8.1] MONITORING: Sprawdź czy archiwum nie jest puste ###
if [ ! -s "$BACKUP_DIR/$ARCHIVE_NAME" ]; then
    log "BŁĄD: Utworzony backup jest pusty (0 bajtów)"
    send_alert "Backup URNY - KRYTYCZNY BŁĄD" "Utworzony backup jest pusty (0 bajtów)!"
    rm -rf "$TEMP_DIR" "$BACKUP_DIR/$ARCHIVE_NAME"
    exit 1
fi

### [8.2] MONITORING: Sprawdź minimalny rozmiar backupu ###
MIN_SIZE=102400  # 100KB jako minimalna oczekiwana wielkość
actual_size=$(stat -c%s "$BACKUP_DIR/$ARCHIVE_NAME")
if [ "$actual_size" -lt "$MIN_SIZE" ]; then
    log "BŁĄD: Backup jest zbyt mały (tylko ${actual_size} bajtów)"
    send_alert "Backup URNY - PODEJRZENIE BŁĘDU" "Backup jest anomalnie mały (${actual_size} bajtów)!"
    # Nie przerywamy działania, tylko ostrzegamy
fi

### [8.3] MONITORING: Sprawdź integralność archiwum ###
if ! tar -tzf "$BACKUP_DIR/$ARCHIVE_NAME" >/dev/null; then
    log "BŁĄD: Backup jest uszkodzony (błąd archiwum)"
    send_alert "Backup URNY - USZKODZONY BACKUP" "Archiwum backupu jest uszkodzone!"
    rm -f "$BACKUP_DIR/$ARCHIVE_NAME"
    exit 1
fi

### [8.4] MONITORING: Oblicz sumę kontrolną ###
sha256sum "$BACKUP_DIR/$ARCHIVE_NAME" > "$BACKUP_DIR/$ARCHIVE_NAME.sha256"

### [10] Finalizacja ###
SIZE=$(du -h "$BACKUP_DIR/$ARCHIVE_NAME" | cut -f1)
MESSAGE="Backup zakończony sukcesem!
Metoda: $DB_BACKUP_METHOD
Ścieżka: $BACKUP_DIR/$ARCHIVE_NAME
Rozmiar: $SIZE
Czas wykonania: $(($SECONDS / 60))m $(($SECONDS % 60))s"

log "$MESSAGE"

# Wyślij podsumowanie + logi tylko z bieżącego uruchomienia
CURRENT_LOGS=$(cat "$TEMP_LOG")
FULL_MESSAGE="$MESSAGE

=== LOGI Z TEGO BACKUPU ===
$CURRENT_LOGS"

send_alert "Backup URNY - Sukces" "$FULL_MESSAGE"

### [11] Sprzątanie ###
rm -rf "$TEMP_DIR"
rm -f "$TEMP_LOG" 
find "$BACKUP_DIR" -name "urny_backup_*.tar.gz" -mtime +7 -delete
log "Usunięto stare backupy (starsze niż 7 dni)"
log "=== Backup zakończony pomyślnie ==="
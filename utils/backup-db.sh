#!/bin/bash

# Скрипт для створення резервної копії бази даних PostgreSQL

set -e

# Отримуємо директорію скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Переходимо в директорію проекту
cd "${PROJECT_DIR}"

# Завантажуємо змінні з .env файлу, якщо він існує
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Параметри за замовчуванням
DB_USER=${DB_USER:-odoo}
DB_PASSWORD=${DB_PASSWORD:-odoo}
DB_HOST=${DB_HOST:-db}
BACKUP_DIR="${PROJECT_DIR}/backups"

# Створюємо папку для backup, якщо не існує
mkdir -p "${BACKUP_DIR}"

# Перевіряємо, чи запущені контейнери
if ! docker compose ps | grep -q "db.*Up"; then
    echo "❌ Помилка: Контейнер бази даних не запущений!"
    echo "   Запустіть контейнери: docker compose up -d"
    exit 1
fi

# Якщо назва БД передана як параметр, використовуємо її
if [ -n "$1" ]; then
    DB_NAME="$1"
else
    # Отримуємо список доступних баз даних (виключаємо системні)
    AVAILABLE_DBS=$(docker compose exec -T db psql -U "${DB_USER}" -lqt 2>/dev/null | \
        cut -d \| -f 1 | \
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | \
        grep -vE '^(template[0-9]|postgres)$' | \
        grep -v '^$' | \
        sort)
    
    if [ -z "$AVAILABLE_DBS" ]; then
        echo "❌ Помилка: Не знайдено баз даних Odoo!"
        echo "   Створіть базу даних через веб-інтерфейс Odoo"
        exit 1
    fi
    
    # Якщо тільки одна БД, використовуємо її
    DB_COUNT=$(echo "$AVAILABLE_DBS" | grep -v '^$' | wc -l)
    if [ "$DB_COUNT" -eq 1 ]; then
        DB_NAME=$(echo "$AVAILABLE_DBS" | grep -v '^$' | head -1)
        echo "📦 Використовую базу даних: ${DB_NAME}"
    else
        # Показуємо список і питаємо
        echo "📋 Доступні бази даних Odoo:"
        echo ""
        echo "$AVAILABLE_DBS" | grep -v '^$' | nl -w2 -s'. '
        echo ""
        
        # Якщо є дефолтна з .env, пропонуємо її
        DEFAULT_DB=${DB_NAME:-postgres}
        if echo "$AVAILABLE_DBS" | grep -qw "$DEFAULT_DB"; then
            read -p "Виберіть базу даних для backup [Enter для '${DEFAULT_DB}']: " DB_NAME
            DB_NAME=${DB_NAME:-$DEFAULT_DB}
        else
            read -p "Введіть назву бази даних для backup: " DB_NAME
        fi
        
        # Перевіряємо, чи існує вибрана БД
        if ! echo "$AVAILABLE_DBS" | grep -qw "$DB_NAME"; then
            echo "❌ Помилка: База даних '${DB_NAME}' не знайдена!"
            echo "   Доступні бази: $(echo "$AVAILABLE_DBS" | grep -v '^$' | tr '\n' ' ')"
            exit 1
        fi
    fi
    echo ""
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/odoo_backup_${DB_NAME}_${TIMESTAMP}.sql.gz"

echo "📦 Створення резервної копії бази даних..."
echo "   База даних: ${DB_NAME}"
echo "   Файл: ${BACKUP_FILE}"
echo ""

# Створюємо резервну копію
docker compose exec -T db pg_dump -U "${DB_USER}" -d "${DB_NAME}" | gzip > "${BACKUP_FILE}"

if [ $? -eq 0 ]; then
    FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    echo "✅ Резервна копія успішно створена!"
    echo "   Розмір: ${FILE_SIZE}"
    echo "   Розташування: ${BACKUP_FILE}"
    echo ""
    echo "💡 Для відновлення використайте:"
    echo "   ./utils/restore-db.sh ${BACKUP_FILE} [назва_бази_даних]"
else
    echo "❌ Помилка при створенні резервної копії!"
    exit 1
fi

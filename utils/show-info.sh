#!/bin/bash

# Скрипт для виведення інформації про систему, версії, порти, статуси

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
ODOO_PORT=${ODOO_PORT:-8069}
DB_NAME=${DB_NAME:-postgres}
DB_USER=${DB_USER:-odoo}

echo "═══════════════════════════════════════════════════════════"
echo "📊 Інформація про Odoo Sample Setup"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Статус контейнерів
echo "🐳 Статус Docker контейнерів:"
echo "───────────────────────────────────────────────────────────"
if command -v docker &> /dev/null; then
    docker compose ps 2>/dev/null || docker-compose ps 2>/dev/null || echo "  Контейнери не запущені"
else
    echo "  ❌ Docker не встановлено"
fi
echo ""

# Версії
echo "📦 Версії:"
echo "───────────────────────────────────────────────────────────"
if command -v docker &> /dev/null; then
    echo "  Docker: $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')"
    echo "  Docker Compose: $(docker compose version 2>/dev/null | cut -d' ' -f4 || docker-compose --version 2>/dev/null | cut -d' ' -f4 | tr -d ',')"
    
    if docker compose ps | grep -q "web.*Up"; then
        echo "  Odoo: $(docker compose exec -T web odoo --version 2>/dev/null | head -1 || echo 'невідомо')"
    fi
    
    if docker compose ps | grep -q "db.*Up"; then
        echo "  PostgreSQL: $(docker compose exec -T db psql --version 2>/dev/null | cut -d' ' -f3 || echo 'невідомо')"
    fi
else
    echo "  Docker не встановлено"
fi
echo ""

# Порти та URL
echo "🌐 Доступ:"
echo "───────────────────────────────────────────────────────────"
echo "  Odoo URL: http://localhost:${ODOO_PORT}"
echo "  Odoo Port: ${ODOO_PORT}"
echo "  PostgreSQL Port: 5432 (внутрішній)"
echo ""

# База даних
echo "💾 База даних:"
echo "───────────────────────────────────────────────────────────"
echo "  Ім'я: ${DB_NAME}"
echo "  Користувач: ${DB_USER}"
if docker compose ps | grep -q "db.*Up"; then
    DB_SIZE=$(docker compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT pg_size_pretty(pg_database_size('${DB_NAME}'));" 2>/dev/null | xargs)
    if [ ! -z "$DB_SIZE" ]; then
        echo "  Розмір: ${DB_SIZE}"
    fi
fi
echo ""

# Папки та volumes
echo "📁 Структура:"
echo "───────────────────────────────────────────────────────────"
echo "  Addons: ./addons"
echo "  Config: ./config"
echo "  Logs: ./logs"
echo "  Backups: ./backups"
echo "  Output: ./output"
echo ""

# Розміри папок
if [ -d "logs" ]; then
    LOG_SIZE=$(du -sh logs 2>/dev/null | cut -f1 || echo "0")
    echo "  Розмір логів: ${LOG_SIZE}"
fi

if [ -d "backups" ]; then
    BACKUP_COUNT=$(ls -1 backups/*.sql.gz 2>/dev/null | wc -l)
    if [ $BACKUP_COUNT -gt 0 ]; then
        BACKUP_SIZE=$(du -sh backups 2>/dev/null | cut -f1 || echo "0")
        echo "  Резервних копій: ${BACKUP_COUNT} (${BACKUP_SIZE})"
    fi
fi
echo ""

# Статус сервісів
echo "🔍 Статус сервісів:"
echo "───────────────────────────────────────────────────────────"
if docker compose ps | grep -q "web.*Up"; then
    echo "  ✅ Odoo: запущений"
    # Перевірка доступності
    if curl -s -f "http://localhost:${ODOO_PORT}/web/health" > /dev/null 2>&1; then
        echo "     Веб-інтерфейс доступний"
    else
        echo "     ⚠️  Веб-інтерфейс не відповідає"
    fi
else
    echo "  ❌ Odoo: не запущений"
fi

if docker compose ps | grep -q "db.*Up"; then
    echo "  ✅ PostgreSQL: запущений"
    if docker compose exec -T db pg_isready -U "${DB_USER}" > /dev/null 2>&1; then
        echo "     База даних доступна"
    else
        echo "     ⚠️  База даних не відповідає"
    fi
else
    echo "  ❌ PostgreSQL: не запущений"
fi
echo ""

# Модулі (якщо Odoo запущений)
if docker compose ps | grep -q "web.*Up"; then
    echo "📦 Модулі Odoo:"
    echo "───────────────────────────────────────────────────────────"
    echo "  Використайте ./utils/list-modules.sh для детальної інформації"
    echo ""
fi

echo "═══════════════════════════════════════════════════════════"
echo "💡 Корисні команди:"
echo "   ./utils/backup-db.sh          - Створити резервну копію"
echo "   ./utils/list-modules.sh       - Список модулів"
echo "   ./utils/shell-web.sh          - Вхід в контейнер Odoo"
echo "   ./utils/shell-db.sh           - Вхід в контейнер PostgreSQL"
echo "═══════════════════════════════════════════════════════════"

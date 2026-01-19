#!/bin/bash

# Скрипт для виведення списку всіх модулів Odoo (активних, неактивних, встановлених)

# Отримуємо директорію скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Переходимо в директорію проекту
cd "${PROJECT_DIR}"

# Завантажуємо змінні з .env файлу, якщо він існує
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Перевіряємо, чи запущений контейнер
if ! docker compose ps | grep -q "web.*Up"; then
    echo "❌ Помилка: Контейнер Odoo не запущений!"
    echo "   Запустіть контейнери: docker compose up -d"
    exit 1
fi

# Якщо назва БД передана як параметр, використовуємо її
if [ -n "$1" ]; then
    DB_NAME="$1"
else
    # Отримуємо список доступних баз даних (виключаємо системні)
    AVAILABLE_DBS=$(docker compose exec -T db psql -U "${DB_USER:-odoo}" -lqt 2>/dev/null | \
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
    DB_COUNT=$(echo "$AVAILABLE_DBS" | wc -l)
    if [ "$DB_COUNT" -eq 1 ]; then
        DB_NAME=$(echo "$AVAILABLE_DBS" | head -1)
        echo "📦 Використовую базу даних: ${DB_NAME}"
    else
        # Показуємо список і питаємо
        echo "📋 Доступні бази даних Odoo:"
        echo ""
        echo "$AVAILABLE_DBS" | nl -w2 -s'. '
        echo ""
        
        # Якщо є дефолтна з .env, пропонуємо її
        DEFAULT_DB=${DB_NAME:-postgres}
        if echo "$AVAILABLE_DBS" | grep -qw "$DEFAULT_DB"; then
            read -p "Виберіть базу даних [Enter для '${DEFAULT_DB}']: " DB_NAME
            DB_NAME=${DB_NAME:-$DEFAULT_DB}
        else
            read -p "Введіть назву бази даних: " DB_NAME
        fi
        
        # Перевіряємо, чи існує вибрана БД
        if ! echo "$AVAILABLE_DBS" | grep -qw "$DB_NAME"; then
            echo "❌ Помилка: База даних '${DB_NAME}' не знайдена!"
            echo "   Доступні бази: $(echo "$AVAILABLE_DBS" | tr '\n' ' ')"
            exit 1
        fi
    fi
    echo ""
fi

OUTPUT_DIR="${PROJECT_DIR}/output"
OUTPUT_FILE="${OUTPUT_DIR}/modules_list_${DB_NAME}_$(date +%Y%m%d_%H%M%S).txt"

# Створюємо папку для результатів
mkdir -p "${OUTPUT_DIR}"

echo "📦 Отримання списку модулів Odoo..."
echo "   База даних: ${DB_NAME}"
echo ""

# Перевіряємо, чи існує база даних
if ! docker compose exec -T db psql -U "${DB_USER:-odoo}" -lqt | cut -d \| -f 1 | grep -qw "${DB_NAME}"; then
    echo "❌ Помилка: База даних '${DB_NAME}' не існує!"
    echo "   Створіть базу даних через веб-інтерфейс Odoo"
    exit 1
fi

echo "═══════════════════════════════════════════════════════════"
echo "📋 СПИСОК МОДУЛІВ ODOO"
echo "═══════════════════════════════════════════════════════════"
echo ""

# SQL запит для отримання модулів з залежностями
SQL_QUERY="
SELECT 
    CASE m.state
        WHEN 'installed' THEN '✅ Встановлені'
        WHEN 'to install' THEN '📥 До встановлення'
        WHEN 'to upgrade' THEN '⬆️  До оновлення'
        WHEN 'to remove' THEN '🗑️  До видалення'
        WHEN 'uninstalled' THEN '❌ Не встановлені'
        ELSE '❓ ' || m.state
    END as status,
    m.name as module_name,
    m.summary as description,
    m.author,
    CASE 
        WHEN m.application = true THEN '📱 Додаток'
        ELSE '🔧 Модуль'
    END as type,
    COALESCE(
        string_agg(d.name, ', ' ORDER BY d.name),
        'none'
    ) as dependencies
FROM ir_module_module m
LEFT JOIN ir_module_module_dependency d ON d.module_id = m.id
GROUP BY m.id, m.state, m.name, m.summary, m.author, m.application
ORDER BY 
    CASE m.state
        WHEN 'installed' THEN 1
        WHEN 'to install' THEN 2
        WHEN 'to upgrade' THEN 3
        WHEN 'to remove' THEN 4
        ELSE 5
    END,
    m.name;
"

# Виконуємо запит і зберігаємо результат
docker compose exec -T db psql -U "${DB_USER:-odoo}" -d "${DB_NAME}" -c "${SQL_QUERY}" > "${OUTPUT_FILE}" 2>&1

if [ $? -eq 0 ]; then
    # Виводимо результат на екран з форматуванням
    echo "Результат запиту:"
    cat "${OUTPUT_FILE}"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    
    # Підрахунок статистики
    INSTALLED=$(docker compose exec -T db psql -U "${DB_USER:-odoo}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM ir_module_module WHERE state = 'installed';" 2>/dev/null | xargs)
    UNINSTALLED=$(docker compose exec -T db psql -U "${DB_USER:-odoo}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM ir_module_module WHERE state = 'uninstalled';" 2>/dev/null | xargs)
    TO_INSTALL=$(docker compose exec -T db psql -U "${DB_USER:-odoo}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM ir_module_module WHERE state = 'to install';" 2>/dev/null | xargs)
    TO_UPGRADE=$(docker compose exec -T db psql -U "${DB_USER:-odoo}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM ir_module_module WHERE state = 'to upgrade';" 2>/dev/null | xargs)
    
    echo "📊 Статистика:"
    echo "   ✅ Встановлені: ${INSTALLED:-0}"
    echo "   ❌ Не встановлені: ${UNINSTALLED:-0}"
    echo "   📥 До встановлення: ${TO_INSTALL:-0}"
    echo "   ⬆️  До оновлення: ${TO_UPGRADE:-0}"
    echo ""
    echo "💾 Повний список збережено в: ${OUTPUT_FILE}"
else
    echo "❌ Помилка при отриманні списку модулів!"
    echo "   Можливо, база даних ще не ініціалізована"
    exit 1
fi

echo ""
echo "💡 Для фільтрації використайте:"
echo "   grep '✅ Встановлені' ${OUTPUT_FILE}"
echo "   grep '❌ Не встановлені' ${OUTPUT_FILE}"
echo ""
echo "💡 Використання:"
echo "   ./utils/list-modules.sh [назва_бази_даних]"
echo "   Приклад: ./utils/list-modules.sh my_odoo_db"
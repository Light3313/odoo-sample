#!/bin/bash

# Скрипт для видалення даних з бази даних (контакти, продажі, товари тощо)
# Залишає структуру таблиць та системні дані (модулі, налаштування)

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
            read -p "Виберіть базу даних для очищення [Enter для '${DEFAULT_DB}']: " DB_NAME
            DB_NAME=${DB_NAME:-$DEFAULT_DB}
        else
            read -p "Введіть назву бази даних для очищення: " DB_NAME
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

# Перевіряємо, чи існує база даних
if ! docker compose exec -T db psql -U "${DB_USER}" -lqt | cut -d \| -f 1 | grep -qw "${DB_NAME}"; then
    echo "❌ Помилка: База даних '${DB_NAME}' не існує!"
    exit 1
fi

echo "⚠️  УВАГА: Цей скрипт видалить всі дані з бази даних!"
echo "   База даних: ${DB_NAME}"
echo ""
echo "Буде видалено:"
echo "  - Контакти (res.partner)"
echo "  - Товари (product.product, product.template)"
echo "  - Продажі (sale.order, sale.order.line)"
echo "  - Закупівлі (purchase.order, purchase.order.line)"
echo "  - Склад (stock.picking, stock.move)"
echo "  - Рахунки (account.move, account.payment)"
echo "  - Інші бізнес-дані"
echo ""
echo "ЗАЛИШИТЬСЯ:"
echo "  - Структура таблиць"
echo "  - Модулі та їх налаштування"
echo "  - Системні записи (ir.*)"
echo "  - Конфігурація Odoo"
echo ""
echo "Це операція НЕЗВОРОТНА!"
read -p "Ви впевнені? Введіть 'CLEAR' для підтвердження: " confirm

if [ "$confirm" != "CLEAR" ]; then
    echo "❌ Операцію скасовано."
    exit 0
fi

# Зупиняємо Odoo контейнер
echo ""
echo "🛑 Зупиняю контейнер Odoo..."
docker compose stop web

echo "🗑️  Видалення даних..."

# SQL скрипт для видалення даних з основних таблиць
# Використовуємо TRUNCATE CASCADE для видалення залежних записів
SQL_CLEAR="
-- Вимкнути перевірки зовнішніх ключів тимчасово
SET session_replication_role = 'replica';

-- Видалення бізнес-даних (в порядку залежностей)
TRUNCATE TABLE account_payment CASCADE;
TRUNCATE TABLE account_move_line CASCADE;
TRUNCATE TABLE account_move CASCADE;
TRUNCATE TABLE account_analytic_line CASCADE;
TRUNCATE TABLE account_analytic_account CASCADE;

TRUNCATE TABLE sale_order_line CASCADE;
TRUNCATE TABLE sale_order CASCADE;

TRUNCATE TABLE purchase_order_line CASCADE;
TRUNCATE TABLE purchase_order CASCADE;

TRUNCATE TABLE stock_move_line CASCADE;
TRUNCATE TABLE stock_move CASCADE;
TRUNCATE TABLE stock_quant CASCADE;
TRUNCATE TABLE stock_picking CASCADE;
TRUNCATE TABLE stock_inventory CASCADE;

TRUNCATE TABLE product_product CASCADE;
TRUNCATE TABLE product_template CASCADE;
TRUNCATE TABLE product_category CASCADE;

TRUNCATE TABLE res_partner CASCADE;

TRUNCATE TABLE mail_message CASCADE;
TRUNCATE TABLE mail_followers CASCADE;
TRUNCATE TABLE mail_activity CASCADE;

TRUNCATE TABLE crm_lead CASCADE;
TRUNCATE TABLE project_task CASCADE;
TRUNCATE TABLE project_project CASCADE;

TRUNCATE TABLE hr_employee CASCADE;
TRUNCATE TABLE hr_department CASCADE;

-- Видалення даних з інших популярних модулів (якщо вони встановлені)
DO \$\$
BEGIN
    -- Спробувати видалити дані з інших таблиць, якщо вони існують
    EXECUTE 'TRUNCATE TABLE IF EXISTS mrp_production CASCADE';
    EXECUTE 'TRUNCATE TABLE IF EXISTS mrp_bom CASCADE';
    EXECUTE 'TRUNCATE TABLE IF EXISTS maintenance_request CASCADE';
    EXECUTE 'TRUNCATE TABLE IF EXISTS helpdesk_ticket CASCADE';
    EXECUTE 'TRUNCATE TABLE IF EXISTS fleet_vehicle CASCADE';
    EXECUTE 'TRUNCATE TABLE IF EXISTS calendar_event CASCADE';
EXCEPTION
    WHEN undefined_table THEN NULL;
END \$\$;

-- Увімкнути перевірки зовнішніх ключів
SET session_replication_role = 'origin';

-- Очистити послідовності (для нових ID)
ALTER SEQUENCE IF EXISTS res_partner_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS product_product_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS product_template_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS sale_order_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS purchase_order_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS account_move_id_seq RESTART WITH 1;
"

# Виконуємо SQL
docker compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
${SQL_CLEAR}
EOF

if [ $? -eq 0 ]; then
    echo "✅ Дані успішно видалено!"
    echo ""
    echo "🚀 Запускаю контейнер Odoo..."
    docker compose start web
    echo ""
    echo "✅ Готово! База даних очищена, структура та модулі залишилися."
    echo ""
    echo "💡 Тепер ви можете:"
    echo "   1. Відкрити Odoo: http://localhost:${ODOO_PORT:-8069}"
    echo "   2. Створити нові контакти, товари, продажі"
    echo "   3. Всі модулі та налаштування залишилися без змін"
else
    echo "❌ Помилка при видаленні даних!"
    echo "🚀 Запускаю контейнер Odoo..."
    docker compose start web
    exit 1
fi

#!/bin/bash

# Скрипт для встановлення та оновлення модулів Odoo

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

# Перевіряємо, чи запущений контейнер
if ! docker compose ps | grep -q "web.*Up"; then
    echo "❌ Помилка: Контейнер Odoo не запущений!"
    echo "   Запустіть контейнери: docker compose up -d"
    exit 1
fi

# Перевірка аргументів
if [ -z "$1" ]; then
    echo "❌ Помилка: Не вказано модулі для встановлення!"
    echo ""
    echo "Використання:"
    echo "  ./utils/install-module.sh <modules> [options]"
    echo ""
    echo "Параметри:"
    echo "  <modules>              - Модулі для встановлення (через кому, наприклад: o1c_cron,base)"
    echo "  -d, --database <name>  - Назва бази даних (опціонально, буде вибір якщо не вказано)"
    echo "  -u, --update <modules> - Модулі для оновлення перед встановленням (через кому)"
    echo "  --no-stop              - Не зупиняти після встановлення (за замовчуванням зупиняє)"
    echo ""
    echo "Приклади:"
    echo "  ./utils/install-module.sh o1c_cron"
    echo "  ./utils/install-module.sh o1c_cron -d my_odoo_db"
    echo "  ./utils/install-module.sh o1c_cron -u o1c,o1c_import,base_automation"
    echo "  ./utils/install-module.sh o1c_cron -d my_odoo_db -u o1c,o1c_import --no-stop"
    exit 1
fi

MODULES_TO_INSTALL="$1"
shift

# Парсимо аргументи
DB_NAME=""
MODULES_TO_UPDATE=""
STOP_AFTER_INIT="--stop-after-init"

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--database)
            DB_NAME="$2"
            shift 2
            ;;
        -u|--update)
            MODULES_TO_UPDATE="$2"
            shift 2
            ;;
        --no-stop)
            STOP_AFTER_INIT=""
            shift
            ;;
        *)
            echo "❌ Невідомий параметр: $1"
            exit 1
            ;;
    esac
done

# Визначаємо назву БД
if [ -z "$DB_NAME" ]; then
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
            read -p "Виберіть базу даних [Enter для '${DEFAULT_DB}']: " DB_NAME
            DB_NAME=${DB_NAME:-$DEFAULT_DB}
        else
            read -p "Введіть назву бази даних: " DB_NAME
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
    echo "   Створіть базу даних через веб-інтерфейс Odoo"
    exit 1
fi

# Формуємо команду Odoo
ODOO_CMD="odoo -d ${DB_NAME}"

# Додаємо оновлення модулів, якщо вказано
if [ -n "$MODULES_TO_UPDATE" ]; then
    ODOO_CMD="${ODOO_CMD} -u ${MODULES_TO_UPDATE}"
fi

# Додаємо встановлення модулів
ODOO_CMD="${ODOO_CMD} -i ${MODULES_TO_INSTALL}"

# Додаємо stop-after-init, якщо потрібно
if [ -n "$STOP_AFTER_INIT" ]; then
    ODOO_CMD="${ODOO_CMD} ${STOP_AFTER_INIT}"
fi

echo "🚀 Встановлення модулів Odoo..."
echo "   База даних: ${DB_NAME}"
echo "   Модулі для встановлення: ${MODULES_TO_INSTALL}"
if [ -n "$MODULES_TO_UPDATE" ]; then
    echo "   Модулі для оновлення: ${MODULES_TO_UPDATE}"
fi
echo ""
echo "Виконується команда: ${ODOO_CMD}"
echo ""

# Виконуємо команду
docker compose exec -T web bash -c "${ODOO_CMD}"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Модулі успішно встановлено!"
    echo ""
    echo "💡 Перевірте статус модулів:"
    echo "   ./utils/list-modules.sh ${DB_NAME}"
else
    echo ""
    echo "❌ Помилка при встановленні модулів!"
    exit 1
fi

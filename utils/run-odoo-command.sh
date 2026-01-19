#!/bin/bash

# Скрипт для виконання Odoo CLI команд

# Отримуємо директорію скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Переходимо в директорію проекту
cd "${PROJECT_DIR}"

# Перевіряємо, чи запущений контейнер
if ! docker compose ps | grep -q "web.*Up"; then
    echo "❌ Помилка: Контейнер Odoo не запущений!"
    echo "   Запустіть контейнери: docker compose up -d"
    exit 1
fi

# Перевірка аргументів
if [ -z "$1" ]; then
    echo "❌ Помилка: Не вказано команду Odoo!"
    echo ""
    echo "Використання:"
    echo "  ./utils/run-odoo-command.sh <odoo_command> [arguments...]"
    echo ""
    echo "Приклади:"
    echo "  ./utils/run-odoo-command.sh -d mydb -u base --stop-after-init"
    echo "  ./utils/run-odoo-command.sh -d mydb shell"
    echo "  ./utils/run-odoo-command.sh -d mydb -c /etc/odoo/odoo.conf"
    echo ""
    echo "Доступні команди Odoo:"
    echo "  -d, --database    - Ім'я бази даних"
    echo "  -u, --update      - Оновити модулі"
    echo "  -i, --init        - Встановити модулі"
    echo "  --stop-after-init - Зупинити після ініціалізації"
    echo "  shell             - Запустити Python shell"
    echo "  -c, --config      - Шлях до конфігурації"
    exit 1
fi

echo "🚀 Виконання команди Odoo: odoo $@"
echo ""

# Виконуємо команду Odoo
docker compose exec web odoo "$@"

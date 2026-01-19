#!/bin/bash

# Скрипт швидкого старту Odoo Sample

echo "🚀 Odoo Sample - Швидкий старт"
echo ""

# Перевірка наявності .env файлу
if [ ! -f .env ]; then
    echo "📝 Створюю .env файл з env.example..."
    cp env.example .env
    echo "✅ Файл .env створено. Відредагуйте його за потреби."
    echo ""
fi

# Завантажуємо змінні з .env файлу
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)
fi

# Перевірка наявності Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Помилка: Docker не встановлено!"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Помилка: Docker Compose не встановлено!"
    exit 1
fi

# Створення папки для логів
if [ ! -d "logs" ]; then
    echo "📁 Створюю папку для логів..."
    mkdir -p logs
fi

# Встановлення прав доступу для Odoo
if [ -f "utils/fix-permissions.sh" ]; then
    echo "🔧 Встановлення прав доступу..."
    ./utils/fix-permissions.sh
    echo ""
fi

# Перевірка наявності enterprise папки
if [ ! -d "${ENTERPRISE_PATH:-../check-files/enterprise}" ]; then
    echo "⚠️  УВАГА: Папка з Enterprise модулями не знайдена!"
    echo "   Вкажіть правильний шлях в .env файлі (ENTERPRISE_PATH)"
    echo ""
fi

echo "🐳 Запускаю Docker Compose..."
echo ""

# Використовуємо docker compose (нова версія) або docker-compose (стара версія)
if docker compose version &> /dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Odoo запущено успішно!"
    echo ""
    echo "📋 Наступні кроки:"
    echo "   1. Відкрийте браузер: http://localhost:${ODOO_PORT:-8069}"
    echo "   2. Створіть базу даних через веб-інтерфейс"
    echo "   3. Встановіть необхідні модулі через меню 'Додатки'"
    echo ""
    echo "📊 Переглянути логи контейнерів: docker compose logs -f"
    echo "📄 Переглянути логи Odoo: tail -f logs/odoo.log"
    echo "🛑 Зупинити: docker compose down"
else
    echo ""
    echo "❌ Помилка при запуску!"
    exit 1
fi

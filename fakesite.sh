#!/bin/bash

# Проверка системы
if ! grep -E -q "^(ID=debian|ID=ubuntu)" /etc/os-release; then
    echo "Скрипт поддерживает только Debian или Ubuntu. Завершаю работу."
    exit 1
fi

# Запрос доменного имени
read -p "Введите доменное имя: " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo "Доменное имя не может быть пустым. Завершаю работу."
    exit 1
fi

read -p "Введите внутренний SNI Self порт (Enter для порта по умолчанию - 9000): " SPORT
SPORT=${SPORT:-9000}

# Получение внешнего IP сервера
external_ip=$(curl -s --max-time 3 https://api.ipify.org)

# Проверка, что curl успешно получил IP
if [[ -z "$external_ip" ]]; then
  echo "Не удалось определить внешний IP сервера. Проверьте подключение к интернету."
  exit 1
fi

echo "Внешний IP сервера: $external_ip"

# Получение A-записи домена
domain_ip=$(dig +short A "$DOMAIN")

# Проверка, что A-запись существует
if [[ -z "$domain_ip" ]]; then
  echo "Не удалось получить A-запись для домена $DOMAIN. Убедитесь, что домен существует!
  exit 1
fi

echo "A-запись домена $DOMAIN указывает на: $domain_ip"

# Сравнение IP адресов
if [[ "$domain_ip" == "$external_ip" ]]; then
  echo "A-запись домена $DOMAIN соответствует внешнему IP сервера."
else
  echo "A-запись домена $DOMAIN не соответствует внешнему IP сервера!
  exit 1
fi

# Проверка, занят ли порт
if ss -tuln | grep -q ":443 "; then
    echo "Порт 443 занят, пожалуйста освободите порт!
    exit 1
else
    echo "Порт 443 свободен."
fi

if ss -tuln | grep -q ":80 "; then
    echo "Порт 80 занят, пожалуйста освободите порт!
    exit 1
else
    echo "Порт 80 свободен."
fi

# Установка nginx и certbot
apt update && apt install -y nginx certbot python3-certbot-nginx git

# Скачивание репозитория
TEMP_DIR=$(mktemp -d)
git clone https://github.com/learning-zone/website-templates.git "$TEMP_DIR"

# Выбор случайного сайта
SITE_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | shuf -n 1)
cp -r "$SITE_DIR"/* /var/www/html/

# Выпуск сертификата
certbot --nginx -d "$DOMAIN" --agree-tos -m "admin@$DOMAIN" --non-interactive

# Настройка конфигурации Nginx
cat > /etc/nginx/sites-enabled/sni.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    }

    return 404;
}

server {
    listen 127.0.0.1:$SPORT ssl http2;

    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";

    ssl_stapling on;
    ssl_stapling_verify on;

    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Настройки Proxy Protocol
    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

rm /etc/nginx/sites-enabled/default

# Перезапуск Nginx
nginx -t && systemctl reload nginx

# Показ путей сертификатов
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
echo ""
echo ""
echo ""
echo ""
echo "Сертификат и ключ расположены в следующих путях:"
echo "Сертификат: $CERT_PATH"
echo "Ключ: $KEY_PATH"
echo ""
echo "В качестве Dest укажите: 127.0.0.1:$SPORT"
echo "В качестве SNI укажите: $DOMAIN"

# Удаление временной директории
rm -rf "$TEMP_DIR"

echo "Скрипт завершён."

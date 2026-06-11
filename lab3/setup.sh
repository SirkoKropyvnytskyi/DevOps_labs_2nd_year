#!/bin/bash

# Зупиняти скрипт у разі будь-якої помилки
set -e

# Перевірка на запуск від імені root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script with root privileges (using sudo)"
  exit 1
fi

echo "=== 1. Updating system and installing packages ==="
apt-get update
apt-get install -y postgresql postgresql-contrib nginx python3-venv python3-pip git curl sudo

echo "=== 2. Creating users ==="

# Користувач student (з адміністративними правами)
if ! id "student" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo student
    echo "student:12345678" | chpasswd
    chage -d 0 student # Вимагає змінити пароль при першому вході
    echo "Created user: student"
fi

# Користувач teacher (з адміністративними правами та паролем за замовчуванням)
if ! id "teacher" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo teacher
    echo "teacher:12345678" | chpasswd
    chage -d 0 teacher # Вимагає змінити пароль при першому вході
    echo "Created user: teacher"
fi

# Користувач app (системний користувач для запуску застосунку, мінімальні права)
if ! id "app" &>/dev/null; then
    useradd -r -s /bin/false app
    echo "Created system user: app"
fi

# Користувач operator (для керування сервісами)
if ! id "operator" &>/dev/null; then
    useradd -m -s /bin/bash -g operator operator
    echo "operator:12345678" | chpasswd
    chage -d 0 operator # Вимагає змінити пароль при першому вході
    echo "Created user: operator"
fi

echo "=== 3. Setting up specific rights for operator ==="
# Вимоги: тільки запуск/зупинка/рестарт/статус mywebapp та reload nginx
cat <<EOF > /etc/sudoers.d/operator
operator ALL=(ALL) NOPASSWD: /usr/bin/systemctl start mywebapp.service, /usr/bin/systemctl stop mywebapp.service, /usr/bin/systemctl restart mywebapp.service, /usr/bin/systemctl status mywebapp.service, /usr/bin/systemctl reload nginx
EOF
chmod 0440 /etc/sudoers.d/operator
echo "Rights for operator configured."

echo "=== 4. Setup DB PostgreSQL ==="
# Використовуємо || true, щоб скрипт не впав, якщо база/користувач вже існують
sudo -u postgres psql -c "CREATE DATABASE notes_db;" || true
sudo -u postgres psql -c "CREATE USER notes_user WITH PASSWORD '123';" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE notes_db TO notes_user;"
sudo -u postgres psql -c "ALTER DATABASE notes_db OWNER TO notes_user;"
echo "DB has been configured."

echo "=== 5. Copying files and setting up environment ==="
# Створюємо конфігурацію
mkdir -p /etc/mywebapp
cat <<EOF > /etc/mywebapp/config.json
{
    "db_host": "127.0.0.1",
    "db_port": 5432,
    "db_name": "notes_db",
    "db_user": "notes_user",
    "db_password": "123",
    "app_port": 5000
}
EOF
chown -R app:app /etc/mywebapp
chmod 600 /etc/mywebapp/config.json

# Переносимо код застосунку в робочу директорію
mkdir -p /opt/mywebapp
# Скрипт очікує, що він запускається з тієї ж папки, де лежать файли коду
cp app.py migration_script_db.py requirements.txt /opt/mywebapp/
chown -R app:app /opt/mywebapp

# Створюємо ізольоване середовище для користувача app
sudo -u app python3 -m venv /opt/mywebapp/venv
sudo -u app /opt/mywebapp/venv/bin/pip install -r /opt/mywebapp/requirements.txt gunicorn
echo "Application environment configured."

echo "=== 6. Systemd configuration (Socket Activation) ==="

# Створюємо файл сокета
cat <<EOF > /etc/systemd/system/mywebapp.socket
[Unit]
Description=mywebapp socket

[Socket]
ListenStream=127.0.0.1:5000

[Install]
WantedBy=sockets.target
EOF

# Створюємо оновлений файл сервісу
cat <<EOF > /etc/systemd/system/mywebapp.service
[Unit]
Description=My Web App (Notes Service)
Requires=mywebapp.socket postgresql.service
After=network.target mywebapp.socket postgresql.service

[Service]
User=app
Group=app
WorkingDirectory=/opt/mywebapp
Environment="HOME=/opt/mywebapp"
# Обов'язкова вимога: запуск міграції ПЕРЕД стартом сервісу
ExecStartPre=/opt/mywebapp/venv/bin/python /opt/mywebapp/migration_script_db.py
# Запуск через gunicorn (systemd сам передасть йому сокет)
ExecStart=/opt/mywebapp/venv/bin/gunicorn app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mywebapp.socket
systemctl start mywebapp.socket
echo "Systemd socket activation configured."

echo "=== 7. Nginx configuration (Reverse Proxy) ==="
cat <<EOF > /etc/nginx/sites-available/mywebapp
server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/mywebapp_access.log;
    
    # Назовні Nginx віддає лише корінь та бізнес-логіку
    location = / {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host \$host;
    }

    location /notes {
        proxy_pass http://127.0.0.1:5000/notes;
        proxy_set_header Host \$host;
    }

    # All other requests (including health) are blocked from outside (return 404)
    location / {
        return 404;
    }
}
EOF

# Вимикаємо дефолтний сайт Nginx і вмикаємо наш
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/
systemctl restart nginx
echo "Nginx configured."

echo "=== 8. Final requirements of the laboratory work (gradebook and default user blocking) ==="
# Створення файлу gradebook
echo "9" > /home/student/gradebook
chown student:student /home/student/gradebook

# Блокування дефолтного користувача (того, з-під якого ми зараз викликали sudo)
DEFAULT_USER=${SUDO_USER:-root}
if [ "$DEFAULT_USER" != "root" ] && [ "$DEFAULT_USER" != "student" ] && [ "$DEFAULT_USER" != "teacher" ] && [ "$DEFAULT_USER" != "operator" ]; then
    echo "Blocking default user: $DEFAULT_USER"
    usermod -L "$DEFAULT_USER"
fi

echo "============================================="
echo "Deployment completed successfully!"
echo "System is ready for use."
echo "============================================="
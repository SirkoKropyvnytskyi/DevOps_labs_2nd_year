#!/bin/bash

# Зупиняти скрипт у разі будь-якої помилки
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script with root privileges (using sudo)"
  exit 1
fi

echo "=== 1. Updating system and installing packages ==="
apt-get update
# Встановлюємо Docker замість python-venv
apt-get install -y postgresql postgresql-contrib nginx docker-ce docker-ce-cli containerd.io docker-compose-plugin git curl sudo

echo "=== 2. Creating users ==="
if ! id "student" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo student
    echo "student:12345678" | chpasswd
    chage -d 0 student
fi

if ! id "teacher" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo teacher
    echo "teacher:12345678" | chpasswd
    chage -d 0 teacher
fi

if ! id "operator" &>/dev/null; then
    useradd -m -s /bin/bash -g operator operator
    echo "operator:12345678" | chpasswd
    chage -d 0 operator
fi

echo "=== 3. Setting up specific rights for operator ==="
cat <<EOF > /etc/sudoers.d/operator
operator ALL=(ALL) NOPASSWD: /usr/bin/systemctl start mywebapp.service, /usr/bin/systemctl stop mywebapp.service, /usr/bin/systemctl restart mywebapp.service, /usr/bin/systemctl status mywebapp.service, /usr/bin/systemctl reload nginx
EOF
chmod 0440 /etc/sudoers.d/operator

echo "=== 4. Setup DB PostgreSQL ==="
sudo -u postgres psql -c "CREATE DATABASE notes_db;" || true
sudo -u postgres psql -c "CREATE USER notes_user WITH PASSWORD '123';" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE notes_db TO notes_user;"
sudo -u postgres psql -c "ALTER DATABASE notes_db OWNER TO notes_user;"

# Налаштування Postgres для прийому з'єднань з Docker-контейнерів
PG_CONF=$(find /etc/postgresql -name postgresql.conf | head -n 1)
PG_HBA=$(find /etc/postgresql -name pg_hba.conf | head -n 1)

sed -i "s/^.*listen_addresses.*/listen_addresses = '*'/g" "$PG_CONF"

if ! grep -F -q "172.16.0.0/12" "$PG_HBA"; then
    echo "host    all             all             172.16.0.0/12           md5" >> "$PG_HBA"
fi
systemctl restart postgresql

echo "=== 5. Systemd configuration (Docker Container) ==="
mkdir -p /home/ubuntu/mywebapp
chown -R ubuntu:ubuntu /home/ubuntu/mywebapp

#systemd-unit для управління контейнером
cat <<EOF > /etc/systemd/system/mywebapp.service
[Unit]
Description=My Web App Docker Service
Requires=docker.service postgresql.service
After=docker.service postgresql.service network.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/ubuntu/mywebapp

# Виконуємо міграцію БД перед стартом самого застосунку
ExecStartPre=/usr/bin/docker compose run --rm web python migration_script_db.py

# Запуск і зупинка через docker compose
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mywebapp.service

echo "=== 6. Nginx configuration (Reverse Proxy) ==="
cat <<EOF > /etc/nginx/sites-available/mywebapp
server {
    listen 80;
    server_name _;

    location = / {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host \$host;
    }

    location /notes {
        proxy_pass http://127.0.0.1:5000/notes;
        proxy_set_header Host \$host;
    }

    location / {
        return 404;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/
systemctl restart nginx

echo "=== 7. Final requirements ==="
echo "9" > /home/student/gradebook
chown student:student /home/student/gradebook

DEFAULT_USER=${SUDO_USER:-root}
if [ "$DEFAULT_USER" != "root" ] && [ "$DEFAULT_USER" != "student" ] && [ "$DEFAULT_USER" != "teacher" ] && [ "$DEFAULT_USER" != "operator" ]; then
    usermod -L "$DEFAULT_USER"
fi

echo "============================================="
echo "Target node deployment completed successfully!"
echo "============================================="
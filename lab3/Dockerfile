# Базовий образ з Python
FROM python:3.11-slim

# Встановлюємо робочу директорію всередині контейнера
WORKDIR /app

# Копіюємо файл залежностей та встановлюємо їх
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt || true

# Копіюємо весь код застосунку в контейнер
COPY . .

# Застосунок працюватиме на порті 5000
EXPOSE 5000

# Команда для запуску застосунку
CMD ["python", "app.py"]
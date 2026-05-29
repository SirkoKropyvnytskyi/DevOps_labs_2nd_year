FROM python:3.13-alpine

WORKDIR /app

# Копіюємо тільки файли із залежностями
COPY requirements/ requirements/

# Встановлюємо залежності
RUN pip install -r requirements/backend.in

# Тепер копіюємо весь інший код
COPY . .

# Запускаємо застосунок
CMD ["python", "spaceship/app.py"]
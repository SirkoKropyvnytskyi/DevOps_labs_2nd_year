FROM python:3.13-bookworm

WORKDIR /app

# Погана практика: копіюємо весь проєкт одразу
COPY . .

# Вказуємо правильний шлях до файлу в папці requirements
RUN pip install -r requirements/backend.in

# Запускаємо застосунок
CMD ["python", "spaceship/app.py"]
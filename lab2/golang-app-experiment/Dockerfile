FROM golang:1.22

WORKDIR /app

# Копіюємо файли із залежностями та завантажуємо їх
COPY go.mod go.sum ./
RUN go mod download

# Копіюємо весь інший вихідний код
COPY . .

# Компілюємо застосунок у бінарний файл з назвою fizzbuzz
RUN go build -o /fizzbuzz

# Запускаємо скомпільований файл (аргумент serve потрібен для запуску веб-сервера)
CMD [ "/fizzbuzz", "serve" ]
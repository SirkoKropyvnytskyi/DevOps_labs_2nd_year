# Збірка 
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /fizzbuzz

# Фінальний образ
FROM scratch
# Копіюємо скомпільований файл
COPY --from=builder /fizzbuzz /fizzbuzz
# Копіюємо папку з шаблонами
COPY --from=builder /app/templates /templates

CMD [ "/fizzbuzz", "serve" ]
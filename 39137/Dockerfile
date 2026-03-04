FROM rust:1.90-slim

WORKDIR /tests
COPY . .
RUN chmod +x test.sh
CMD ["./test.sh"]

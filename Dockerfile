FROM rust:1.90-slim
WORKDIR /tests
COPY . .
RUN chmod +x run_tests.sh repro_bug.sh

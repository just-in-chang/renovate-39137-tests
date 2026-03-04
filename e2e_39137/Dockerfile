ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY fixtures/ ./fixtures/
COPY test.sh ./test.sh
RUN chmod +x /tests/test.sh
CMD ["./test.sh"]

ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY workspace/ ./workspace/
COPY test.sh ./test.sh
RUN chmod +x /tests/test.sh
CMD ["./test.sh"]

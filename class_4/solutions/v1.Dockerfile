FROM ubuntu:18.04
RUN mkdir /app && \
    echo "/sbin/nologin" >> /etc/shells && \
    useradd --no-create-home --system --shell /sbin/nologin app && \
    chown app /app
USER app
WORKDIR /app
COPY . /app
CMD ["./gowiki"]

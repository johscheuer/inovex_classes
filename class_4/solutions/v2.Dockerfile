FROM golang:1.11.1-stretch as builder
RUN go get -d github.com/prometheus/client_golang || true
WORKDIR /go/src/github.com/johscheuer/gowiki/
COPY ./main.go .
RUN GOOS=linux go build -o gowiki .

### Application container image
FROM ubuntu:18.04
RUN mkdir /app && \
    echo "/sbin/nologin" >> /etc/shells && \
    useradd --no-create-home --system --shell /sbin/nologin app && \
    chown app /app
USER app
WORKDIR /app
COPY --from=builder /go/src/github.com/johscheuer/gowiki/gowiki .
COPY ./edit.html /view.html /app/
CMD ["./gowiki"]

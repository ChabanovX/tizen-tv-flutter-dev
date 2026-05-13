FROM --platform=linux/amd64 alpine:3.20
RUN apk add --no-cache musl-dev gcc linux-headers
COPY fb0test.c /tmp/fb0test.c
RUN gcc -static -O2 -o /tmp/fb0test /tmp/fb0test.c

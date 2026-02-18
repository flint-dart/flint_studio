FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates bash \
    && rm -rf /var/lib/apt/lists/*

# Copy prebuilt app bundle from this build directory.
COPY . /app

RUN chmod +x /app/start.sh \
    && find /app -maxdepth 1 -type f -perm -u=x -exec chmod +x {} +

ENV FLINT_HOT=0
ENV PORT=3000
EXPOSE 3000

CMD ["./start.sh"]

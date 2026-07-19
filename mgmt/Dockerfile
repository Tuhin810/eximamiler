FROM node:20-slim
# exim-daemon-heavy is present in the exim image; here we only need the
# exim CLI for `-bpc`. Install the light client for queue introspection.
RUN apt-get update && apt-get install -y --no-install-recommends exim4-base \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY server.js .
EXPOSE 8443
CMD ["node", "server.js"]

FROM debian:bookworm-slim

# exim4-daemon-heavy gives us DKIM + dnslookup + auth support.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      exim4-daemon-heavy openssl gettext-base ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY conf/exim4.conf.template /opt/exim/exim4.conf.template
COPY scripts/entrypoint.sh    /opt/exim/entrypoint.sh
COPY scripts/gen-dkim.sh      /opt/exim/gen-dkim.sh
COPY scripts/add-domain.sh    /opt/exim/add-domain.sh
RUN chmod +x /opt/exim/entrypoint.sh /opt/exim/gen-dkim.sh /opt/exim/add-domain.sh

EXPOSE 587
ENTRYPOINT ["/opt/exim/entrypoint.sh"]

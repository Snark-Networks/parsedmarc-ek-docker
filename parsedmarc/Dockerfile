FROM python:3.13-slim

# envsubst is provided by gettext-base; used in entrypoint to inject env vars.
RUN apt-get update && \
    apt-get install -y --no-install-recommends gettext-base && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir parsedmarc

COPY entrypoint.sh /entrypoint.sh
COPY parsedmarc.ini.template /etc/parsedmarc.ini.template

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

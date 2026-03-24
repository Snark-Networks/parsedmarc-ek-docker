FROM alpine:latest

RUN apk add --no-cache curl

COPY setup.sh /setup/setup.sh
COPY ilm-policy.json /setup/ilm-policy.json

RUN chmod +x /setup/setup.sh

CMD ["sh", "/setup/setup.sh"]

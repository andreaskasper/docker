FROM debian:latest
LABEL maintainer="Andreas.Kasper@goo1.de"

RUN apt-get update \
    && apt-get install -y rsnapshot \
    && apt-get clean

ADD entrypoint.sh /entrypoint

RUN chmod 0777 /entrypoint

CMD ["rsnapshot","daily"]
ENTRYPOINT ["/entrypoint"]

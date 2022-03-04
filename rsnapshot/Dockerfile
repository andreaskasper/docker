FROM debian:latest
LABEL maintainer="Andreas.Kasper@goo1.de"

CMD["rsnapshot","daily"]
ENTRYPOINT ["/entrypoint"]

RUN apt-get update \
    && apt-get install -y rsnapshot \
    && apt-get clean

ADD entrypoint.sh /entrypoint

RUN chmod 0777 /entrypoint

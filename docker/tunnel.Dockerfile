FROM alpine:latest

ARG PUID=1000
ARG PGID=1000

RUN apk add --no-cache openssh-client

# Create a group and user with the specified IDs
RUN addgroup -g ${PGID} tunnel && \
    adduser -u ${PUID} -G tunnel -D tunnel

# SSH needs a writable home directory for some operations
RUN mkdir -p /home/tunnel && chown tunnel:tunnel /home/tunnel
ENV HOME=/home/tunnel

# Set the default user for the image, although docker-compose might override it
USER tunnel

ENTRYPOINT ["ssh"]

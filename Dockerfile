FROM n8nio/n8n:1.93.0

USER root
RUN apk add --no-cache ffmpeg
USER node

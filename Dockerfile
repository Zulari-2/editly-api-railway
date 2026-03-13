# Use official n8n image
FROM n8nio/n8n:1.93.0

# Switch to root to install packages
USER root

# Install ffmpeg and curl
RUN apk add --no-cache ffmpeg curl

# Switch back to n8n user
USER node

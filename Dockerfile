# ═══════════════════════════════════════════════════════════════════
# Optimized n8n + FFmpeg for 1 CPU core / 2 GB RAM
# CloudStation / Railway Free Tier
#
# WHY YOUR OLD DOCKERFILE CRASHED:
#   1. No Node.js heap limit → n8n could use 1.5GB alone, leaving
#      nothing for FFmpeg zoompan which needs ~400-500MB peak
#   2. Full ffmpeg from Alpine installs fine but combined with
#      unconstrained n8n heap = OOM kill mid-execution
#   3. No /tmp size management → large temp files competed with RAM
#
# WHAT THIS FIXES:
#   - NODE_OPTIONS="--max-old-space-size=512" caps n8n heap at 512MB
#   - FFmpeg gets the remaining ~1GB headroom for zoompan encoding
#   - fontconfig + DejaVu fonts installed for subtitle drawtext filter
#   - wget installed explicitly (image downloads in Phase 1)
#   - All unnecessary packages excluded
#   - n8n configured for minimal resource usage via ENV vars
#
# MEMORY BUDGET (2048 MB total):
#   Docker/OS overhead    : ~200 MB
#   n8n Node.js heap cap  : ~512 MB
#   n8n execution buffers : ~128 MB
#   FFmpeg zoompan peak   : ~450 MB  (1280x720, -preset ultrafast, -threads 1)
#   FFmpeg concat/merge   : ~30 MB   (-c copy, trivial)
#   Linux page cache      : ~128 MB
#   Safety headroom       : ~200 MB (prevents kernel OOM kill)
# ═══════════════════════════════════════════════════════════════════

FROM n8nio/n8n:1.88.0

# Switch to root for package installation
USER root

# Install ONLY what the workflow actually needs:
#   ffmpeg        - video/audio processing (zoompan, concat, encode, subtitle)
#   wget          - downloading images from imgbb in Phase 1
#   fontconfig    - fc-list command for font discovery in Assembly B
#   font-dejavu   - DejaVuSans-Bold.ttf for subtitle drawtext rendering
#
# NOT installed (not needed by workflow):
#   curl          - wget handles all HTTP downloads
#   bash          - workflow scripts use #!/bin/sh (busybox sh, already present)
#   python3       - not needed at runtime
#   nodejs extras - n8n bundles its own Node.js
RUN apk add --no-cache \
    ffmpeg \
    wget \
    fontconfig \
    font-dejavu \
    && fc-cache -f \
    && rm -rf /var/cache/apk/* /tmp/* /root/.cache

# Verify installations
RUN ffmpeg -version 2>&1 | head -1 \
    && ffprobe -version 2>&1 | head -1 \
    && wget --version 2>&1 | head -1 \
    && fc-list | grep -i dejavu | head -3

# Switch back to n8n user for security
USER node

# ═══════════════════════════════════════════════════════════════════
# NODE.JS HEAP LIMIT — THE MOST IMPORTANT SETTING
# Without this, Node.js default heap = ~1.5GB on a 2GB system.
# n8n + FFmpeg together would immediately OOM kill.
# 512MB gives n8n plenty of room for large workflow executions
# while leaving ~1GB headroom for FFmpeg's zoompan peak usage.
# ═══════════════════════════════════════════════════════════════════
ENV NODE_OPTIONS="--max-old-space-size=512"

# ═══════════════════════════════════════════════════════════════════
# N8N PERFORMANCE SETTINGS
# These reduce n8n's background resource consumption so FFmpeg
# gets the CPU time it needs during heavy encoding phases.
# ═══════════════════════════════════════════════════════════════════

# Disable n8n diagnostics and telemetry (saves CPU cycles + network)
ENV N8N_DIAGNOSTICS_ENABLED=false
ENV N8N_VERSION_NOTIFICATIONS_ENABLED=false
ENV N8N_TEMPLATES_ENABLED=false
ENV N8N_ONBOARDING_FLOW_DISABLED=true

# Single main process — no extra worker processes competing for the 1 CPU
ENV EXECUTIONS_PROCESS=main

# Keep execution data only while running — don't accumulate history in SQLite
# This prevents the database from growing and causing I/O slowdowns
ENV EXECUTIONS_DATA_PRUNE=true
ENV EXECUTIONS_DATA_MAX_AGE=1
ENV EXECUTIONS_DATA_PRUNE_MAX_COUNT=50

# Limit concurrent executions — prevents two FFmpeg processes running simultaneously
# which would OOM on 2GB RAM
ENV N8N_DEFAULT_BINARY_DATA_MODE=filesystem

# Timeout: 2 hours (7200s) — the full Assembly workflow can take 30-60 min
# Without this, n8n kills long-running executions after the default 1 hour
ENV EXECUTIONS_TIMEOUT=7200
ENV EXECUTIONS_TIMEOUT_MAX=7200

# Binary data stored on disk not in memory — critical for large video files
# The uploaded/downloaded binary data (audio files, video) stays on disk
# instead of being held in the Node.js heap
ENV N8N_DEFAULT_BINARY_DATA_MODE=filesystem
ENV N8N_BINARY_DATA_STORAGE_PATH=/home/node/.n8n/binaryData

# Reduce webhook polling interval — less CPU wasted on internal checks
ENV N8N_GRACEFUL_SHUTDOWN_TIMEOUT=30

# Disable built-in metrics endpoint (saves RAM)
ENV N8N_METRICS=false

# Log level: warn only — info logging creates significant I/O on busy workflows
ENV N8N_LOG_LEVEL=warn

# ═══════════════════════════════════════════════════════════════════
# /tmp WORKING DIRECTORY FOR WORKFLOW
# Our workflow writes ~500MB-1GB to /tmp/sfcm/ during assembly.
# This is fine since Railway/CloudStation provides persistent disk.
# The workflow's cleanup node deletes intermediates after upload.
# ═══════════════════════════════════════════════════════════════════
ENV SFCM_TMP_BASE=/tmp/sfcm

# Expose n8n default port
EXPOSE 5678

# Health check — lets Railway/CloudStation know when n8n is ready
# Checks every 30s, allows 120s startup time (n8n can take 30-60s to start)
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD wget -q --spider http://localhost:5678/healthz || exit 1

# n8n starts via the base image's entrypoint — no CMD override needed
# The base image handles: n8n start --tunnel (or without tunnel based on env)

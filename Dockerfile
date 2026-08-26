# ============================================================
# Wisecow Application Dockerfile
# A cow wisdom web server serving fortune cookies via cowsay
# ============================================================

# Use Debian slim as base for minimal image size
FROM debian:bullseye-slim

# Install runtime dependencies and add /usr/games to PATH
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fortune-mod \
        fortunes-min \
        cowsay \
        netcat-openbsd \
        bash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/games:/usr/local/bin:${PATH}"

# Copy application script
WORKDIR /app
COPY wisecow.sh .

# Make script executable
RUN chmod +x wisecow.sh

# Expose the application port
EXPOSE 4499

# Run the application
CMD ["bash", "wisecow.sh"]

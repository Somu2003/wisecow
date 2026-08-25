# ============================================================
# Wisecow Application Dockerfile
# A cow wisdom web server serving fortune cookies via cowsay
# ============================================================

# Use Debian slim as base for minimal image size
FROM debian:bullseye-slim AS builder

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fortune-mod \
        cowsay \
        netcat-openbsd \
        bash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ============================================================
# Production stage
# ============================================================
FROM debian:bullseye-slim

# Copy installed packages from builder
COPY --from=builder /usr/games/cowsay /usr/games/cowsay
COPY --from=builder /usr/games/fortune /usr/games/fortune
COPY --from=builder /usr/bin/nc.openbsd /usr/bin/nc.openbsd
COPY --from=builder /usr/bin/bash /usr/bin/bash

# Copy fortune data files
COPY --from=builder /usr/share/games/ /usr/share/games/

# Create symlinks for cowsay and fortune in PATH
RUN ln -s /usr/games/cowsay /usr/local/bin/cowsay && \
    ln -s /usr/games/fortune /usr/local/bin/fortune && \
    ln -s /usr/bin/nc.openbsd /usr/local/bin/nc

# Copy application script
WORKDIR /app
COPY wisecow.sh .

# Make script executable
RUN chmod +x wisecow.sh

# Expose the application port
EXPOSE 4499

# Run the application
CMD ["bash", "wisecow.sh"]

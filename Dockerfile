# Use Ubuntu 22.04 as the base image with multi-arch support
FROM ubuntu:22.04

# Buildx arguments for multi‑arch support
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Ensure TARGETPLATFORM is always set (default to amd64)
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}

# ---------------------------------------------------------------------------
# 1. Install system dependencies (the setup‑dependencies.sh script should take
#    care of installing sudo, python3, pip, git, etc.).  We just copy it in
#    and run it.
# ---------------------------------------------------------------------------
COPY cloud/setup-dependencies.sh /tmp/setup-dependencies.sh
RUN chmod +x /tmp/setup-dependencies.sh && \
    /tmp/setup-dependencies.sh && \
    rm /tmp/setup-dependencies.sh

# ---------------------------------------------------------------------------
# 2. Copy the VSIX extension (used later by the entrypoint)
# ---------------------------------------------------------------------------
COPY pythagora-vs-code.vsix /var/init_data/pythagora-vs-code.vsix

# ---------------------------------------------------------------------------
# 3. Application layout
# ---------------------------------------------------------------------------
ENV PYTH_INSTALL_DIR=/pythagora
WORKDIR ${PYTH_INSTALL_DIR}/pythagora-core

# Install Python requirements in a virtual environment
COPY requirements.txt .
RUN python3 -m venv venv && \
    . venv/bin/activate && \
    pip install --no-cache-dir -r requirements.txt

# Copy source files
COPY main.py .
COPY core/ core/
COPY pyproject.toml .
COPY cloud/config-docker.json config.json

# Activate the virtual environment for every subsequent RUN/ CMD
ENV VIRTUAL_ENV=${PYTH_INSTALL_DIR}/pythagora-core/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# ---------------------------------------------------------------------------
# 4. Runtime configuration
# ---------------------------------------------------------------------------
ENV PYTHAGORA_DATA_DIR=${PYTH_INSTALL_DIR}/pythagora-core/data/
RUN mkdir -p "${PYTHAGORA_DATA_DIR}"

# Expose the ports used by the application and by code‑server
EXPOSE 27017 8000 8080 5173 3000

# ---------------------------------------------------------------------------
# 5. Create a non‑root user (devuser) with sudo privileges
# ---------------------------------------------------------------------------
RUN groupadd -g 1000 devusergroup && \
    useradd -m -u 1000 -g devusergroup -s /bin/bash devuser && \
    echo "devuser:devuser" | chpasswd && \
    apt-get update && apt-get install -y sudo && \
    adduser devuser sudo && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ---------------------------------------------------------------------------
# 6. Code‑server related files and permissions
# ---------------------------------------------------------------------------
COPY cloud/entrypoint.sh /entrypoint.sh
COPY cloud/on-event-extension-install.sh /var/init_data/on-event-extension-install.sh
COPY cloud/favicon.svg /favicon.svg
COPY cloud/favicon.ico /favicon.ico
COPY cloud/settings.json /usr/local/share/code-server/data/Machine/settings.json
COPY cloud/posthog.html /tmp/posthog.html

RUN mkdir -p /usr/local/share/code-server/data/User/globalStorage \
             /usr/local/share/code-server/data/User/History \
             /usr/local/share/code-server/data/Machine \
             /usr/local/share/code-server/data/logs && \
    chown -R devuser:devusergroup /usr/local/share/code-server && \
    chmod -R 755 /usr/local/share/code-server && \
    cp -f /favicon.ico /usr/local/lib/code-server/src/browser/media/favicon.ico && \
    cp -f /favicon.svg /usr/local/lib/code-server/src/browser/media/favicon-dark-support.svg && \
    cp -f /favicon.svg /usr/local/lib/code-server/src/browser/media/favicon.svg && \
    # Inject PostHog analytics
    sed -i "s|'sha256-/r7rqQ+yrxt57sxLuQ6AMYcy/lUpvAIzHjIJt/OeLWU=' ;|'sha256-/r7rqQ+yrxt57sxLuQ6AMYcy/lUpvAIzHjIJt/OeLWU=' https://us-assets.i.posthog.com ;|g" \
           /usr/local/lib/code-server/lib/vscode/out/server-main.js && \
    # Insert PostHog snippet into workbench HTML
    sed -i '/<head>/r /tmp/posthog.html' \
           /usr/local/lib/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.html && \
    rm /tmp/posthog.html && \
    chmod +x /entrypoint.sh /var/init_data/on-event-extension-install.sh && \
    chown -R devuser:devusergroup ${PYTH_INSTALL_DIR} && \
    chown -R devuser: /var/init_data/

# ---------------------------------------------------------------------------
# 7. Workspace directory
# ---------------------------------------------------------------------------
RUN mkdir -p ${PYTH_INSTALL_DIR}/pythagora-core/workspace && \
    chown -R devuser:devusergroup ${PYTH_INSTALL_DIR}/pythagora-core/workspace

# ---------------------------------------------------------------------------
# 8. Git configuration for the non‑root user
# ---------------------------------------------------------------------------
USER devuser
RUN git config --global user.email "devuser@pythagora.ai" && \
    git config --global user.name "pythagora"
USER root

# ---------------------------------------------------------------------------
# 9. Final entrypoint
# ---------------------------------------------------------------------------
RUN touch /var/log/app.log && \
    chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
# --- Auto-Injected Smart Entrypoint ---
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
RUN touch /var/log/app.log
EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]

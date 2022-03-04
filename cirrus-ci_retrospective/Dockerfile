FROM registry.fedoraproject.org/fedora-minimal:latest
RUN microdnf update -y && \
    microdnf install -y findutils jq git curl python3 && \
    microdnf clean all && \
    rm -rf /var/cache/dnf
# Assume build is for development/manual testing purposes by default (automation should override with fixed version)
ARG INSTALL_AUTOMATION_VERSION=latest
ARG INSTALL_AUTOMATION_URI=https://github.com/containers/automation/releases/latest/download/install_automation.sh
ADD / /usr/src/automation
RUN if [[ "$INSTALL_AUTOMATION_VERSION" == "0.0.0" ]]; then \
        env INSTALL_PREFIX=/usr/share \
        /usr/src/automation/bin/install_automation.sh 0.0.0 github cirrus-ci_retrospective; \
    else \
        curl --silent --show-error --location \
        --url "$INSTALL_AUTOMATION_URI" | env INSTALL_PREFIX=/usr/share \
            /bin/bash -s - "$INSTALL_AUTOMATION_VERSION" github cirrus-ci_retrospective; \
    fi
# Required environment variables
ENV AUTOMATION_LIB_PATH="" \
    GITHUB_ACTIONS="false" \
    ACTIONS_STEP_DEBUG="false" \
    GITHUB_EVENT_NAME="" \
    GITHUB_EVENT_PATH="" \
    GITHUB_TOKEN=""
# Optional (recommended) environment variables
ENV OUTPUT_JSON_FILE=""
WORKDIR /root
ENTRYPOINT ["/bin/bash", "-c", "source /etc/automation_environment && exec /usr/share/automation/bin/cirrus-ci_retrospective.sh"]

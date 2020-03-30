FROM registry.fedoraproject.org/fedora-minimal:latest
RUN microdnf update -y && \
    microdnf install -y findutils jq git curl && \
    microdnf clean all && \
    rm -rf /var/cache/dnf

ARG INSTALL_AUTOMATION_VERSION=latest
ARG INSTALL_AUTOMATION_URI=https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh
ADD / /usr/src/automation
RUN if [[ "$INSTALL_AUTOMATION_VERSION" == "0.0.0" ]]; then \
        env INSTALL_PREFIX=/usr/share \
        /usr/src/automation/bin/install_automation.sh 0.0.0 cirrus-ci_retrospective; \
    else \
        curl --silent --show-error --location \
        --url "$INSTALL_AUTOMATION_URI" | env INSTALL_PREFIX=/usr/share \
            /bin/bash -s - "$INSTALL_AUTOMATION_VERSION" cirrus-ci_retrospective; \
    fi
# Required environment variables
ENV AUTOMATION_LIB_PATH="" \
    GITHUB_ACTIONS="false" \
    GITHUB_EVENT_NAME="" \
    GITHUB_EVENT_PATH="" \
    GITHUB_TOKEN=""
# Optional (recommended) environment variables
ENV OUTPUT_JSON_FILE=""
WORKDIR /root
ENTRYPOINT ["/bin/bash", "-c", "source /etc/profile && exec /usr/share/automation/bin/cirrus-ci_retrospective.sh"]

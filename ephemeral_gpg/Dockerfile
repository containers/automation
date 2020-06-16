FROM registry.fedoraproject.org/fedora-minimal:latest
RUN microdnf update -y && \
    microdnf install -y coreutils curl gnupg2 git jq && \
    microdnf clean all && \
    rm -rf /var/cache/dnf
# Assume build is for development/manual testing purposes by default (automation should override with fixed version)
ARG INSTALL_AUTOMATION_VERSION=latest
ARG INSTALL_AUTOMATION_URI=https://github.com/containers/automation/releases/latest/download/install_automation.sh
ADD / /usr/src/automation
RUN if [[ "$INSTALL_AUTOMATION_VERSION" == "0.0.0" ]]; then \
        env INSTALL_PREFIX=/usr/share \
        /usr/src/automation/bin/install_automation.sh 0.0.0 ephemeral_gpg; \
    else \
        curl --silent --show-error --location \
        --url "$INSTALL_AUTOMATION_URI" | env INSTALL_PREFIX=/usr/share \
            /bin/bash -s - "$INSTALL_AUTOMATION_VERSION" ephemeral_gpg; \
    fi
# Required environment variables
# TODO: use EPHEMERAL_CONTAINER value for something useful?
ENV GITHUB_ACTIONS="false" \
    ACTIONS_STEP_DEBUG="false" \
    PRIVATE_KEY_FILEPATH="" \
    PRIVATE_PASSPHRASE_FILEPATH="" \
    EPHEMERAL_CONTAINER=="1"
WORKDIR /root
ENTRYPOINT ["/bin/bash", "-c", "source /etc/profile && exec /usr/share/automation/bin/ephemeral_gpg.sh"]

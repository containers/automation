FROM registry.fedoraproject.org/fedora-minimal:latest
RUN microdnf update -y && \
    microdnf install -y \
        findutils jq git curl python3-pyyaml \
        perl-YAML perl-interpreter perl-open perl-Data-TreeDumper \
            perl-Test perl-Test-Simple perl-Test-Differences \
            perl-YAML-LibYAML perl-FindBin \
        python3 python3-virtualenv python3-pip gcc python3-devel \
        python3-flake8 python3-pep8-naming python3-flake8-docstrings python3-flake8-import-order python3-flake8-polyfill python3-mccabe python3-pep8-naming && \
    microdnf clean all && \
    rm -rf /var/cache/dnf
# Required by perl
ENV LC_ALL="C" \
    LANG="en_US.UTF-8"

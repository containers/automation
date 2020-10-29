FROM registry.fedoraproject.org/fedora-minimal:latest
RUN microdnf update -y && \
    microdnf install -y \
        findutils jq git curl \
        perl-YAML perl-interpreter perl-open perl-Data-TreeDumper \
            perl-Test perl-Test-Simple perl-Test-Differences \
            perl-YAML-LibYAML perl-FindBin \
        python3 python3-pip gcc python3-devel && \
    microdnf clean all && \
    rm -rf /var/cache/dnf
# Required by perl
ENV LC_ALL="C" \
    LANG="en_US.UTF-8"

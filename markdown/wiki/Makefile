UID := $(shell id -u)
.SUFFIXES: .template.md

%.md : %.template.md
	podman run --userns keep-id --user ${UID} --rm -v ${HOME}/Projects/Diagrams:/data:z ghcr.io/mermaid-js/mermaid-cli/mermaid-cli -i "$<" -o "$@" -e png

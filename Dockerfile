FROM --platform=$BUILDPLATFORM registry.access.redhat.com/ubi9/ubi:9.5@sha256:a1804302f6f53e04cc1c6b20bc2204d5c9ae6e5a664174b38fbeeb30f7983d4e AS builder
ARG OCT_REPO=github.com/test-network-function/oct.git
ARG TOKEN
ENV OCT_FOLDER=/usr/oct
ENV OCT_DB_FOLDER=${OCT_FOLDER}/cmd/tnf/fetch/data

# Install dependencies
RUN yum install -y gcc git jq make wget

# Install Go binary and set the PATH
ENV \
	GO_DL_URL=https://golang.org/dl \
	GOPATH=/root/go
ENV GO_BIN_URL_x86_64=${GO_DL_URL}/go1.24.1.linux-amd64.tar.gz
ENV GO_BIN_URL_aarch64=${GO_DL_URL}/go1.24.1.linux-arm64.tar.gz

# Determine the CPU architecture and download the appropriate Go binary
RUN \
	if [ "$(uname -m)" = x86_64 ]; then \
		wget --directory-prefix=${TEMP_DIR} ${GO_BIN_URL_x86_64} --quiet \
		&& rm -rf /usr/local/go \
		&& tar -C /usr/local -xzf ${TEMP_DIR}/go1.24.1.linux-amd64.tar.gz; \
	elif [ "$(uname -m)" = aarch64 ]; then \
		wget --directory-prefix=${TEMP_DIR} ${GO_BIN_URL_aarch64} --quiet \
		&& rm -rf /usr/local/go \
		&& tar -C /usr/local -xzf ${TEMP_DIR}/go1.24.1.linux-arm64.tar.gz; \
	else \
		echo "CPU architecture is not supported." && exit 1; \
	fi

# Add go binary directory to $PATH
ENV PATH=${PATH}:"/usr/local/go/bin":${GOPATH}/"bin"

WORKDIR /root
RUN git clone https://${TOKEN}@$OCT_REPO
WORKDIR /root/oct

RUN make build-oct && \
    mkdir -p ${OCT_FOLDER} && \
	mkdir -p ${OCT_DB_FOLDER} && \
    cp oct ${OCT_FOLDER}

RUN ./oct fetch --operator --container --helm && \
	cp -a cmd/tnf/fetch/data/* ${OCT_DB_FOLDER} && \
	cp scripts/run.sh ${OCT_FOLDER} && \
    chmod -R 777 ${OCT_DB_FOLDER}

# Copy the oct folder to a new minimal flattened image to reduce size.
# It should also hide the pull token.
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest@sha256:ac61c96b93894b9169221e87718733354dd3765dd4a62b275893c7ff0d876869
ENV OCT_FOLDER=/usr/oct

COPY --from=builder ${OCT_FOLDER} ${OCT_FOLDER}

WORKDIR ${OCT_FOLDER}

ENV SHELL=/bin/bash
CMD ["./run.sh"]

#
# SPDX-License-Identifier: Apache-2.0
#
FROM registry.access.redhat.com/ubi8/ubi-minimal AS base
RUN microdnf install findutils gcc gcc-c++ git gzip make python3 shadow-utils tar unzip xz \
    && groupadd -g 7051 ibp-user \
    && useradd -u 7051 -g ibp-user -s /bin/bash ibp-user \
    && microdnf remove shadow-utils \
    && microdnf clean all
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
ADD https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 /usr/local/bin/jq
RUN chmod +x /tini /usr/local/bin/jq
RUN mkdir -p /opt/go /opt/node /opt/java \
    && curl -sSL https://dl.google.com/go/go1.14.3.linux-amd64.tar.gz | tar xzf - -C /opt/go --strip-components=1 \
    && curl -sSL https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.7%2B10/OpenJDK11U-jdk_x64_linux_hotspot_11.0.7_10.tar.gz | tar xzf - -C /opt/java --strip-components=1 \
    && curl -sSL https://nodejs.org/download/release/v12.17.0/node-v12.17.0-linux-x64.tar.xz | tar xJf - -C /opt/node --strip-components=1
ENV GOROOT=/opt/go
ENV GOCACHE=/tmp/gocache
ENV GOENV=/tmp/goenv
ENV GOPATH=/tmp/go
ENV JAVA_HOME=/opt/java
ENV MAVEN_OPTS="-Dmaven.repo.local=/tmp/maven"
ENV npm_config_cache=/tmp/npm-cache
ENV npm_config_devdir=/tmp/npm-devdir
ENV PATH=/opt/go/bin:/opt/node/bin:/opt/java/bin:${PATH}
RUN curl -sSL -o /tmp/gradle.zip https://services.gradle.org/distributions/gradle-5.6.4-bin.zip \
    && unzip -qq /tmp/gradle.zip -d /opt \
    && mv /opt/gradle-5.6.4 /opt/gradle \
    && rm -f /tmp/gradle.zip \
    && curl -sSL https://downloads.apache.org/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz | tar xzf - -C /opt \
    && mv /opt/apache-maven-3.6.3 /opt/maven
ENV PATH=/opt/gradle/bin:/opt/maven/bin:${PATH}
ADD builders/java/pom.xml /opt/fabric-chaincode-java/
RUN mkdir -p /opt/fabric \
    && curl -sSL https://github.com/hyperledger/fabric/releases/download/v2.1.1/hyperledger-fabric-linux-amd64-2.1.1.tar.gz | tar xzf - -C /opt/fabric  \
    && cd /opt/fabric-chaincode-java \
    && mvn -q dependency:copy-dependencies -DoutputDirectory=/opt/fabric-chaincode-java/lib \
    && npm install --unsafe-perm -g fabric-shim@2.1.2 \
    && rm -rf /tmp/gocache /tmp/goenv /tmp/go /tmp/maven /tmp/npm-cache /tmp/npm-devdir
ENV FABRIC_CFG_PATH=/opt/fabric/config
ENV PATH=/opt/fabric/bin:${PATH}

FROM base AS builder
ADD . /tmp/microfab
RUN cd /tmp/microfab \
    && mkdir -p /opt/microfab/bin /opt/microfab/data \
    && chown ibp-user:ibp-user /opt/microfab/data \
    && go build -o /opt/microfab/bin/microfabd cmd/microfabd/main.go \
    && cp -rf builders /opt/microfab/builders

FROM base
COPY --from=builder /opt/microfab /opt/microfab
ENV MICROFAB_HOME=/opt/microfab
ENV PATH=/opt/microfab/bin:${PATH}
EXPOSE 8080
USER ibp-user
VOLUME /opt/microfab/data
ENTRYPOINT [ "/tini", "--" ]
CMD [ "/opt/microfab/bin/microfabd" ]
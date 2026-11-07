# Test image: bats-core (+ bats-support/assert/file) with git and gitleaks.
FROM bats/bats:1.14.0
ARG GITLEAKS_VERSION=8.30.1
ARG TARGETARCH=amd64
RUN apk add --no-cache git coreutils findutils diffutils grep curl \
 && arch=$([ "$TARGETARCH" = arm64 ] && echo arm64 || echo x64) \
 && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${arch}.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks \
 && gitleaks version

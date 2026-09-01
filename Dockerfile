# poddock-mcp image (official swift:6.1 base, multi-stage: build then run).
# Build from the repo root: docker build -t poddock-mcp .
FROM swift:6.1-jammy AS build
WORKDIR /build/DNSPodKit

# Manifest + lock + tests first so dependency resolution caches across source changes
# (Tests/ must exist or SPM mis-infers the test target path as overlapping Sources/)
COPY DNSPodKit/Package.swift DNSPodKit/Package.resolved ./
COPY DNSPodKit/Tests ./Tests
RUN swift package resolve

# Sources change most — last layer
COPY DNSPodKit/Sources ./Sources
RUN swift build -c release --product poddock-mcp

FROM swift:6.1-jammy
WORKDIR /app
COPY --from=build /build/DNSPodKit/.build/release/poddock-mcp /usr/local/bin/poddock-mcp
# Streamable HTTP port; credentials come via in-session dnspod_login (zero startup credentials)
EXPOSE 28100
ENV PODDOCK_MCP_HOST=0.0.0.0 PODDOCK_MCP_PORT=28100
ENTRYPOINT ["poddock-mcp"]

# poddock-mcp image (official swift:6.1 base, multi-stage: build then run)
FROM swift:6.1-jammy AS build
WORKDIR /build
COPY Package.swift Package.swift
COPY Sources Sources
# Resolve dependencies first to leverage caching (swift package resolve generates one when absent)
RUN swift package resolve || true
RUN swift build -c release --product poddock-mcp

FROM swift:6.1-jammy
WORKDIR /app
COPY --from=build /build/.build/release/poddock-mcp /usr/local/bin/poddock-mcp
# Streamable HTTP port; credentials come via in-session dnspod_login (zero startup credentials)
EXPOSE 28100
ENV PODDOCK_MCP_HOST=0.0.0.0 PODDOCK_MCP_PORT=28100
ENTRYPOINT ["poddock-mcp"]

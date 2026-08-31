# poddock-mcp 镜像(swift:6 官方基础镜像,多阶段:构建 → 运行)
FROM swift:6-jammy AS build
WORKDIR /build
COPY Package.swift Package.swift
COPY Sources Sources
# 先解析依赖以利用缓存(无 lockfile 时 swift package resolve 生成)
RUN swift package resolve || true
RUN swift build -c release --product poddock-mcp

FROM swift:6-jammy
WORKDIR /app
COPY --from=build /build/.build/release/poddock-mcp /usr/local/bin/poddock-mcp
# Streamable HTTP 端口;凭据走会话内 dnspod_login(启动零凭据)
EXPOSE 28100
ENV PODDOCK_MCP_HOST=0.0.0.0 PODDOCK_MCP_PORT=28100
ENTRYPOINT ["poddock-mcp"]

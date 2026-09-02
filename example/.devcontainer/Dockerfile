# 下游專案的 devcontainer image：疊在 devbase 上
FROM ghcr.io/yosimasu/devbox:latest

# 版本鎖定交給 repo 根的 mise.toml，image 只負責把它裝起來
COPY mise.toml .
RUN mise trust && mise install

# alpine-s-ui-light

适用于小内存 Alpine Linux 的 [s-ui](https://github.com/alireza0/s-ui) 面板部署方案。

GitHub Action 每日自动同步 s-ui 最新版本，Alpine 安装脚本一键部署。

## 快速安装

```bash
wget -O install.sh https://raw.githubusercontent.com/samoyed24/alpine-s-ui-light/main/scripts/install-alpine.sh && chmod +x install.sh && ./install.sh
```

## 手动安装

```bash
wget -O install.sh https://raw.githubusercontent.com/samoyed24/alpine-s-ui-light/main/scripts/install-alpine.sh
chmod +x install.sh
./install.sh
```

## 选项

```bash
./install.sh --arch arm64           # 指定架构（默认自动检测）
./install.sh --version v1.4.2       # 指定版本（默认最新）
./install.sh --uninstall            # 卸载
```

## 服务管理

```bash
rc-service s-ui start               # 启动
rc-service s-ui stop                # 停止
rc-service s-ui restart             # 重启
rc-service s-ui status              # 状态
tail -f /var/log/s-ui.log           # 查看日志
```

服务已配置开机自启和崩溃自动重启。

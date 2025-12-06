# Bandwidth Test Tool (iperf3)

这是一个基于 `iperf3` 的高级服务器带宽测试工具，提供中文交互界面，用于精准测量服务器的 TCP/UDP 吞吐量、丢包率和网络抖动。

## 主要功能

- **多模式测试**：支持上传、下载、双向测试。
- **TCP/UDP 支持**：不仅测速，还能测丢包率（UDP模式）。
- **多线程并发**：支持自定义并发流数，跑满大带宽。
- **可视化报告**：实时显示进度，测试结束后生成详细报告。
- **公共服务器**：内置常用公共 iperf3 节点，也支持自定义 IP。

## 快速开始 (一键安装)

直接在终端运行以下命令即可启动：

```bash
bash <(curl -sL https://raw.githubusercontent.com/shakebbq-dot/tools/main/bandwidth_test.sh)
```

> 注意：该指令假设脚本已托管在 `shakebbq-dot/tools` 仓库的 `main` 分支。如果尚未上传，请先上传脚本。

## 手动安装与使用

1.  **下载脚本**：
    将 `bandwidth_test.sh` 保存到本地。

2.  **赋予执行权限**：
    ```bash
    chmod +x bandwidth_test.sh
    ```

3.  **运行 (需要 Root)**：
    ```bash
    sudo ./bandwidth_test.sh
    ```

## 依赖说明

脚本会自动检测并安装以下依赖（支持 CentOS/Debian/Ubuntu/Arch）：
- `iperf3`: 核心测速工具
- `jq`: 处理 JSON 格式结果
- `bc`: 数值计算

# shell 自动化脚本集合

当前仓库用于收集常用服务器自动化脚本。

## 只下载脚本，不克隆整个仓库

如果只想下载 nginx / Docker 菜单脚本，不需要 `git clone` 整个仓库。当前工作区没有配置 Git remote，无法从仓库元数据里自动得出最终公开地址。发布到 GitHub 后，Raw 地址格式如下：

```text
https://raw.githubusercontent.com/<GitHub用户名>/shell/main/scripts/nginx_tools.sh
```

如果默认分支不是 `main`，请把 `main` 改成实际分支名。下面命令用 `RAW_URL` 变量集中保存这个地址：

```bash
RAW_URL="https://raw.githubusercontent.com/<GitHub用户名>/shell/main/scripts/nginx_tools.sh"
curl -fsSL -o nginx_tools.sh "$RAW_URL"
chmod +x nginx_tools.sh
./nginx_tools.sh
```

也可以一行执行：

```bash
RAW_URL="https://raw.githubusercontent.com/<GitHub用户名>/shell/main/scripts/nginx_tools.sh"; curl -fsSL -o nginx_tools.sh "$RAW_URL" && chmod +x nginx_tools.sh && ./nginx_tools.sh
```

如果服务器没有 `curl`，可以使用 `wget`：

```bash
RAW_URL="https://raw.githubusercontent.com/<GitHub用户名>/shell/main/scripts/nginx_tools.sh"
wget -qO nginx_tools.sh "$RAW_URL"
chmod +x nginx_tools.sh
./nginx_tools.sh
```

> 提示：如果脚本是单文件下载的，不在 Git 仓库里，自身升级时需要提供同一个 Raw 地址：
>
> ```bash
> SCRIPT_UPDATE_URL="$RAW_URL" ./nginx_tools.sh
> ```
>
> 然后在菜单里选择“升级本仓库脚本”。如果你使用 Gitee、GitLab 或自建 Git 服务，请复制该平台文件页面里的 Raw/原始文件地址替换 `RAW_URL`。

## Nginx / Docker 菜单脚本

`scripts/nginx_tools.sh` 采用菜单选择方式，不需要在命令行一次性录入所有参数。重复运行脚本可以继续管理已经安装并启动过的容器和镜像。

```bash
bash scripts/nginx_tools.sh
```

如果是按上面的单文件方式下载，则运行：

```bash
./nginx_tools.sh
```

菜单能力：

1. 安装/启动 nginx-ui。
2. 管理已安装 nginx-ui 容器和镜像：查看状态、启动、停止、重启、查看日志、拉取/升级镜像、删除容器、删除本地镜像。
3. 安装/启动 `hotpot/mgx:ssl-ml`。
4. 管理已安装 `hotpot/mgx` 容器和镜像：查看状态、启动、停止、重启、查看日志、拉取/升级镜像、删除容器、删除本地镜像。
5. 为 mgx 按步骤添加域名站点配置：输入域名、选择反向代理或静态站点、自动生成 SSL 配置并重载容器。
6. 升级本仓库脚本：在 Git 仓库内使用 `git fetch --all --prune` 和 `git pull --ff-only`；单文件下载时使用 `SCRIPT_UPDATE_URL` 指向 Raw 地址完成覆盖升级。

默认安装目录为 `/opt/shell-automation`，可通过环境变量 `SHELL_AUTOMATION_HOME` 覆盖。nginx-ui 与 mgx 的目录也可分别通过 `NGINX_UI_DIR`、`MGX_DIR` 覆盖。

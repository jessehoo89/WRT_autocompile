# 编译指南

## 1. 环境准备

首先安装 Linux 系统，推荐 Ubuntu LTS。

## 2. 安装编译依赖

```bash
sudo apt -y update
sudo apt -y full-upgrade
sudo apt install -y dos2unix libfuse-dev
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
```

## 3. 使用步骤

1.  克隆仓库：
    ```bash
    git clone https://github.com/jessehoo89/WRT_autocompile.git
    ```
2.  进入目录：
    ```bash
    cd wrt_release
    ```

## 4. 编译固件

使用 `./build.sh` 脚本进行编译，支持以下设备：

### 京东云

*   **雅典娜(02)、亚瑟(01)、太乙(07)、AX5(JDC版)**:
    ```bash
    ./build.sh jdcloud_ipq60xx_immwrt
    ./build.sh jdcloud_ipq60xx_libwrt
    ./build.sh jdcloud_ipq60xx_libwrt_kmod
    ```
*   **百里**:
    ```bash
    ./build.sh jdcloud_ax6000_immwrt
    ```

### 阿里云

*   **AP8220**:
    ```bash
    ./build.sh aliyun_ap8220_immwrt
    ```

### 领势

*   **MX4200v1、MX4200v2、MX4300**:
    ```bash
    ./build.sh linksys_mx4x00_immwrt
    ```

### 奇虎

*   **360v6**:
    ```bash
    ./build.sh qihoo_360v6_immwrt
    ```

### 红米

*   **AX5**:
    ```bash
    ./build.sh redmi_ax5_immwrt
    ```
*   **AX6**:
    ```bash
    ./build.sh redmi_ax6_immwrt
    ```
*   **AX6000**:
    ```bash
    ./build.sh redmi_ax6000_immwrt21
    ```

### CMCC （中国移动）

*   **RAX3000M**:
    ```bash
    ./build.sh cmcc_rax3000m_immwrt
    ```

### 斐讯

*   **N1**:
    ```bash
    ./build.sh n1_immwrt
    ```

### 兆能

*   **M2**:
    ```bash
    ./build.sh zn_m2_immwrt_nowifi_kmod
    ./build.sh zn_m2_libwrt
    ```

### Gemtek

*   **W1701K**:
    ```bash
    ./build.sh gemtek_w1701k_immwrt
    ```

### 其他

*   **X64**:
    ```bash
    ./build.sh x64_immwrt
    ```

---

## 5. 三方插件

三方插件源自：[https://github.com/kenzok8/small-package.git](https://github.com/kenzok8/small-package.git)

## 6. 项目结构说明

- **wrt_core/**: 核心模块目录，包含所有配置、补丁和脚本。
  - **compilecfg/**: 编译配置文件 (.ini)。
  - **deconfig/**: 默认配置文件 (.config)。
  - **modules/**: 模块化脚本 (general.sh, feeds.sh, packages.sh, system.sh)。
  - **patches/**: 系统和软件包补丁。
  - **scripts/**: 辅助脚本。
  - **update.sh**: 更新逻辑主入口脚本。
  - **pre_clone_action.sh**: 预克隆操作脚本。

- **build.sh**: 主编译脚本，调用 `wrt_core` 中的资源。
- **firmware/**: 编译完成的固件输出目录。

## 7. OAF（应用过滤）功能使用说明

使用 OAF（应用过滤）功能前，需先完成以下操作：

1.  打开系统设置 → 启动项 → 定位到「appfilter」
2.  将「appfilter」当前状态**从已禁用更改为已启用**
3.  完成配置后，点击**启动**按钮激活服务

## 8. kmod包编译（ALL_KMODS 全量编译）

本仓库特色——**编译时设置 `CONFIG_ALL_KMODS=y`，全量编译目标平台的所有内核模块（kmod），并自动生成软件源索引及签名密钥，最终打包为可供用户直接下载的 kmod 软件源。**

### 适用目标

以下两个编译选项在固件构建的同时，会全量编译所有 kmod 并打包发布：

| 目标 | 说明 |
|:-----|:------|
| `jdcloud_ipq60xx_libwrt_kmod` | 京东云 IPQ60xx 系列（libWRT），全量 kmod + kmod 软件源 |
| `zn_m2_immwrt_nowifi_kmod` | 兆能 M2（immwrt，不含 WiFi），全量 kmod + kmod 软件源 |

```bash
./build.sh jdcloud_ipq60xx_libwrt_kmod
./build.sh zn_m2_immwrt_nowifi_kmod
```

### 产物说明

编译完成后，产物目录中包含：

- **固件**（`firmware/`）：设备固件
- **kmod 包集合**（`firmware/kmod_packages/`）：全量编译的 `.ipk` 内核模块包
- **软件源索引**（`Packaging`, `Packages.gz`）：opkg 软件源标准索引
- **签名密钥**：用于 opkg 签名验证

### 使用方法

将 `firmware/kmod_packages/` 目录部署到 HTTP 服务器上，即可作为自定义 kmod 软件源供其他同内核版本的设备使用。

> **💡 自建 kmod 软件源详细教程：** [https://www.right.com.cn/forum/forum.php?mod=viewthread&tid=8456143](https://www.right.com.cn/forum/forum.php?mod=viewthread&tid=8456143)

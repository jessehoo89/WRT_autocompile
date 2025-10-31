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
    git clone https://github.com/ZqinKing/wrt_release.git
    ```
2.  进入目录：
    ```bash
    cd wrt_relese
    ```

## 4. 编译固件

使用 `./build.sh` 脚本进行编译，支持以下设备：

### 京东云

*   **雅典娜(02)、亚瑟(01)、太乙(07)、AX5(JDC版)**:
    ```bash
    ./build.sh jdcloud_ipq60xx_immwrt
    ./build.sh jdcloud_ipq60xx_libwrt
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
    ./build.sh zn_m2_immwrt
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

## 6. OAF（应用过滤）功能使用说明

使用 OAF（应用过滤）功能前，需先完成以下操作：

1.  打开系统设置 → 启动项 → 定位到「appfilter」
2.  将「appfilter」当前状态**从已禁用更改为已启用**
3.  完成配置后，点击**启动**按钮激活服务

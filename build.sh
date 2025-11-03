#!/usr/bin/env bash
#
# Copyright (C) 2025 ZqinKing
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -e

BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1
Build_Mod=$2

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

# 移除 uhttpd 依赖
# 当启用luci-app-quickfile插件时，表示启动nginx，所以移除luci对uhttp(luci-light)的依赖
remove_uhttpd_dependency() {
    local config_path="$BASE_PATH/$BUILD_DIR/.config"
    local luci_makefile_path="$BASE_PATH/$BUILD_DIR/feeds/luci/collections/luci/Makefile"

    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled."
        fi
    fi
}

# 应用配置文件
apply_config() {
    # 复制基础配置文件
    \cp -f "$CONFIG_FILE" "$BASE_PATH/$BUILD_DIR/.config"
    
    # 如果是 ipq60xx 或 ipq807x 平台，则追加 NSS 配置
    if grep -qE "(ipq60xx|ipq807x)" "$BASE_PATH/$BUILD_DIR/.config"; then
        cat "$BASE_PATH/deconfig/nss.config" >> "$BASE_PATH/$BUILD_DIR/.config"
    fi

    # 追加代理配置
    cat "$BASE_PATH/deconfig/proxy.config" >> "$BASE_PATH/$BUILD_DIR/.config"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}

if [[ -d $BASE_PATH/action_build ]]; then
    BUILD_DIR="action_build"
fi

$BASE_PATH/update.sh "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH/$BUILD_DIR" "$COMMIT_HASH"

apply_config
remove_uhttpd_dependency

cd "$BASE_PATH/$BUILD_DIR"
make defconfig

if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    DISTFEEDS_PATH="$BASE_PATH/$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
    fi
fi

if [[ $Build_Mod == "debug" ]]; then
    exit 0
fi

TARGET_DIR="$BASE_PATH/$BUILD_DIR/bin/targets"
if [[ -d $TARGET_DIR ]]; then
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec rm -f {} +
fi

make download -j$(($(nproc) * 2))
make -j$(($(nproc) + 1)) || make -j1 V=s

FIRMWARE_DIR="$BASE_PATH/firmware"
\rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec cp -f {} "$FIRMWARE_DIR/" \;
\rm -f "$BASE_PATH/firmware/Packages.manifest" 2>/dev/null

# 检查是否是 zn_m2_libwrt_nowifi 设备
if [ "$Dev" = "zn_m2_libwrt_nowifi" ]; then
    echo "Building ALL kernel modules and generating repository index..."
    
    cd "$BASE_PATH/$BUILD_DIR"
    
    # 1. 强制准备内核环境
    make target/linux/prepare CONFIG_AUTOREMOVE=0 V=s
    make package/kernel/linux/clean
    make package/kernel/linux/prepare V=s
    make package/kernel/linux/compile V=s
    make package/kernel/linux/install V=s
    
    # 2. 获取所有内核相关包名
    KMOD_PACKAGES=$(find package/ kernel/ -name Makefile | 
                    xargs grep -l '^include \$(TOPDIR)\/package\/kernel' |
                    xargs grep -m1 '^PKG_NAME' |
                    awk -F': ' '{print $NF}'
                   )
    
    KERNEL_PACKAGE=$(ls bin/targets/*/packages/kernel_* | head -n1 | xargs basename | sed 's/_.*//')
    FIRMWARE_PACKAGES=$(find package/ -name Makefile | xargs grep '^include \$(TOPDIR)\/package\/firmware' -l | xargs grep '^PKG_NAME' -m1 | awk -F': ' '{print $NF}')
    
    ALL_PACKAGES="$KERNEL_PACKAGE $KMOD_PACKAGES $FIRMWARE_PACKAGES"
    
    echo "Identified packages:"
    echo "$ALL_PACKAGES"
    
    # 3. 为编译所有 kmod 设置环境
    touch .config
    echo "CONFIG_ALL_KMODS=y" >> .config
    
    # 4. 编译所有内核相关包
    for pkg in $ALL_PACKAGES; do
        # 先清理
        make package/$pkg/clean V=s
        
        # 并行编译 (失败时回退)
        echo "Compiling $pkg..."
        make package/$pkg/compile -j$(($(nproc) + 1)) V=sc || \
        make package/$pkg/compile -j1 V=s
    done
    
    # 5. 收集所有 ipk 文件
    KMOD_DIR="$BASE_PATH/firmware/kmod"
    \rm -rf "$KMOD_DIR" 2>/dev/null
    PKG_DIR="$KMOD_DIR/packages"
    mkdir -p "$PKG_DIR"
    
    find "$BASE_PATH/$BUILD_DIR/bin/targets" -type f \( \
        -name "kmod-*.ipk" \
        -o -name "bpf-*.ipk" \
        -o -name "$KERNEL_PACKAGE-*.ipk" \
        -o -name "firmware-*.ipk" \
        \) ! -name "*host*" \
        -exec cp -fv {} "$PKG_DIR/" \;
    # 6. 生成软件源索引
    echo "Generating repository index in $PKG_DIR ..."
    cd "$PKG_DIR"
    
    # 确定目标架构
    TARGET_ARCH=$(ls . | grep "kmod-" | head -n1 | cut -d_ -f3-)
    echo "Detected target architecture: $TARGET_ARCH"
    
    # 完整索引生成流程
    echo "Creating package manifest..."
    # 创建包清单文件
    find . -maxdepth 1 -name "*.ipk" | while read pkg; do
        file_size=$(stat -c "%s" "$pkg")
        md5sum=$(md5sum "$pkg" | cut -d' ' -f1)
        echo "Package: $(basename "$pkg" | cut -d_ -f1)" >> Packages.manifest
        echo "Version: $(basename "$pkg" | cut -d_ -f2)" >> Packages.manifest
        echo "Depends: " $(ar t "$pkg" | grep ^control.tar | xargs -n1 tar -Ox | grep -Po 'Depends:.*' | cut -d: -f2- || echo "") >> Packages.manifest
        echo "Filename: packages/$pkg" >> Packages.manifest
        echo "Size: $file_size" >> Packages.manifest
        echo "MD5Sum: $md5sum" >> Packages.manifest
        echo "Architecture: $TARGET_ARCH" >> Packages.manifest
        echo "" >> Packages.manifest
    done
    
    # 创建压缩索引
    echo "Creating compressed Packages file..."
    {
        echo "Architecture: $TARGET_ARCH"
        echo
        cat Packages.manifest
    } > Packages
    gzip -9c Packages > Packages.gz
    
    # 清理临时文件
    rm -f Packages.manifest
    
    echo "Kmod repository index generated at $PKG_DIR/Packages.gz"
    
    # 7. 可选：创建 Packages 签名
    if [ -f "$BASE_PATH/$BUILD_DIR/staging_dir/host/bin/usign" ]; then
        echo "Signing repository index..."
        "$BASE_PATH/$BUILD_DIR/staging_dir/host/bin/usign" -S -m Packages -s "$BASE_PATH/sign.key"
    else
        echo "Warning: usign not found, skipping repository signing"
    fi
fi

if [[ -d $BASE_PATH/action_build ]]; then
    make clean
fi

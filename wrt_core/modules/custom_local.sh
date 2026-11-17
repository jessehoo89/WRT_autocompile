#!/usr/bin/env bash
# ==========================================================
# 本仓库独有、上游没有的修正函数集合（merge 上游后单独收纳于此）
# 由 2026-11-17 merge ZqinKing/wrt_release 时从原 system.sh / packages.sh 抽出。
# 这些函数在上游 modules/ 中不存在，因此不会被上游实现覆盖。
# ==========================================================

# gettext-full 1.0（gnulib 版）宿主编译缺 stdcountof.h 时的回退锚点
# 2026-10-10 Merge Official Source 之前的最后一个 0.24.2 版本
GETTEXT_FALLBACK_COMMIT=11152dd84230f07dcc524137c81db15b818093c9

downgrade_gettext_full() {
    local pkg="package/libs/gettext-full"
    [ -f "$BUILD_DIR/$pkg/Makefile" ] || return 0
    grep -q 'PKG_VERSION:=1\.0' "$BUILD_DIR/$pkg/Makefile" 2>/dev/null || return 0

    echo "检测到 gettext-full 1.0，回退到 0.24.2（规避 stdcountof.h 缺失）..."
    if (
        cd "$BUILD_DIR" || exit 1
        git fetch --depth 1 origin "$GETTEXT_FALLBACK_COMMIT" >/dev/null 2>&1 || exit 1
        rm -rf "$pkg"
        git checkout FETCH_HEAD -- "$pkg" >/dev/null 2>&1 || exit 1
    ); then
        echo -n "gettext-full 已回退到: "
        grep -m1 'PKG_VERSION' "$BUILD_DIR/$pkg/Makefile" || true
    else
        echo "警告：gettext-full 回退失败，构建可能仍因 stdcountof.h 失败" >&2
    fi
    return 0
}


fix_qca_ssdk_modinfo() {
    local script_src="$BASE_PATH/patches/patch_modinfo.py"
    local makefile="$BUILD_DIR/package/qca-nss/qca-ssdk/Makefile"

    # 安装 patch_modinfo.py 脚本
    if [ -f "$script_src" ]; then
        cp -f "$script_src" "$BUILD_DIR/scripts/patch_modinfo.py"
        echo "已安装 patch_modinfo.py"
    else
        echo "警告：patch_modinfo.py 未找到 ($script_src)" >&2
        return 0
    fi

    # 在 Build/Compile 的 $(CP) ... 行后追加 modinfo 清理行
    if [ -f "$makefile" ]; then
        python3 /dev/stdin "$makefile" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# 在 $(CP) $(QCA_SSDK_SYMVERS) 行后追加一行
line = '\tpython3 $(TOPDIR)/scripts/patch_modinfo.py $(PKG_BUILD_DIR)/build/bin/qca-ssdk.ko mdio-bitbang mdio-i2c\n'
pattern = re.compile(r'^(\t\$\(CP\) \$\(QCA_SSDK_SYMVERS\).*)$', re.MULTILINE)
replacement = r'\1' + '\n' + line.rstrip('\n')

content = pattern.sub(replacement, content, count=1)

with open(path, 'w') as f:
    f.write(content)
print('已插入 modinfo 修复')
PYEOF
        echo "已插入 modinfo 修复到 $makefile"
    else
        echo "警告：qca-ssdk Makefile 未找到 ($makefile)，跳过该修正（不同源码布局属正常）" >&2
        return 0
    fi
}

fix_qca_ssdk_mido_i2c() {
    local qca_ssdk_dir="$BUILD_DIR/package/qca-nss/qca-ssdk"
    local patch_file="$BASE_PATH/patches/0100-mido-i2c-qcom-compat.patch"
    if [ -d "$qca_ssdk_dir" ] && [ -f "$patch_file" ]; then
        install -Dm644 "$patch_file" "$qca_ssdk_dir/patches/0100-mido-i2c-qcom-compat.patch"
        echo "Patched qca-ssdk for kernel 6.18 MIDO_I2C_QCOM compatibility"
    fi
}

fix_quickstart() {
    local file_path="$(get_custom_feed_worktree_dir)/luci-app-quickstart/luasrc/controller/istore_backend.lua"
    local url="https://gist.githubusercontent.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa/raw/istore_backend.lua"
    if [ -f "$file_path" ]; then
        echo "正在修复 quickstart..."
        if ! curl -fsSL -o "$file_path.tmp" "$url"; then
            echo "警告：从 $url 下载 istore_backend.lua 失败，沿用仓库自带版本" >&2
            rm -f "$file_path.tmp"
        else
            mv -f "$file_path.tmp" "$file_path"
        fi
    fi
}

fix_kernel_video_qcom_iris() {
    local kernel_cfg="$BUILD_DIR/target/linux/qualcommax/config-6.18"
    if [ -f "$kernel_cfg" ] && ! grep -qF "CONFIG_VIDEO_QCOM_IRIS" "$kernel_cfg"; then
        echo "" >> "$kernel_cfg"
        echo "# Disable Qualcomm iris V4L2 decoder driver (kernel 6.18 new symbol)" >> "$kernel_cfg"
        echo "# CONFIG_VIDEO_QCOM_IRIS is not set" >> "$kernel_cfg"
        echo "Patched kernel config for VIDEO_QCOM_IRIS"
    fi
}

apply_passwall_tweaks() {
    local chnlist_path="$(get_custom_feed_worktree_dir)/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then
        >"$chnlist_path"
    fi

    local xray_util_path="$(get_custom_feed_worktree_dir)/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
        sed -i 's/sampling = 3/sampling = 5/g' "$xray_util_path"
    fi
}


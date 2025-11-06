#!/bin/bash

# 设置基础路径（适配 GitHub Action 环境）
set -e

BASE_DIR="$1"  # 传入编译目录，例如 ./action_build/libwrt-k612
if [[ -z "$BASE_DIR" ]]; then
  echo "Usage: $0 <build_dir>"
  exit 1
fi

SRC_DIR="$BASE_DIR/bin/targets/qualcommax/ipq60xx/packages"
DST_DIR="$BASE_DIR/bin/targets/qualcommax/ipq60xx/kmod"

# 创建目标目录
mkdir -p "$DST_DIR"

# 1. 复制所有 kmod-*.ipk 文件
echo "Copying kmod-*.ipk files..."
cp "$SRC_DIR"/kmod-*.ipk "$DST_DIR/" 2>/dev/null || true

# 2. 复制原始元数据文件
echo "Copying metadata files..."
cp "$SRC_DIR"/index.json "$DST_DIR/"
cp "$SRC_DIR"/Packages "$DST_DIR/"
cp "$SRC_DIR"/Packages.manifest "$DST_DIR/"

# 3. 过滤 index.json
echo "Filtering index.json..."
jq '{
  version,
  architecture,
  packages: ( .packages | with_entries(select(.key | startswith("kmod-"))) )
}' "$DST_DIR/index.json" > "$DST_DIR/index.json.tmp" && mv "$DST_DIR/index.json.tmp" "$DST_DIR/index.json"

# 4. 过滤 Packages
echo "Filtering Packages..."
awk 'BEGIN { RS="\n\n"; ORS="\n\n" } /^Package: kmod-/ { print }' "$DST_DIR/Packages" > "$DST_DIR/Packages.tmp" && mv "$DST_DIR/Packages.tmp" "$DST_DIR/Packages"

# 5. 过滤 Packages.manifest
echo "Filtering Packages.manifest..."
awk 'BEGIN { RS="\n\n"; ORS="\n\n" } /^Package: kmod-/ { print }' "$DST_DIR/Packages.manifest" > "$DST_DIR/Packages.manifest.tmp" && mv "$DST_DIR/Packages.manifest.tmp" "$DST_DIR/Packages.manifest"

# 6. 生成 Packages.gz
echo "Compressing Packages to Packages.gz..."
gzip -c "$DST_DIR/Packages" > "$DST_DIR/Packages.gz"

# 7. 签名：复制公钥 & 使用 usign 签名
echo "Signing Packages..."
cp "$BASE_DIR/key-build.pub" "$DST_DIR/"
"$BASE_DIR/staging_dir/host/bin/usign" -S -m "$DST_DIR/Packages" -s "$BASE_DIR/key-build" > "$DST_DIR/Packages.sig"
rm -f "$DST_DIR/key-build.pub"

# 8. 打包 kmod 目录
ARCHIVE_NAME="kmod-repo-$(date +%Y%m%d-%H%M).tar.gz"
ARCHIVE_PATH="$BASE_DIR/bin/targets/qualcommax/ipq60xx/$ARCHIVE_NAME"
echo "Creating archive: $ARCHIVE_NAME"
tar -czf "$ARCHIVE_PATH" -C "$BASE_DIR/bin/targets/qualcommax/ipq60xx" kmod

echo "✅ kmod repo built at: $ARCHIVE_PATH"
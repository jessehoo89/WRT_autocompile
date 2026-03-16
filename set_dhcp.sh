#!/bin/sh
# 设置 LAN 口的 DHCP 为关闭状态
set_dhcp_off() {
    # 修改路径为 BUILD_DIR 的绝对路径（与 update.sh 中的路径一致）
    BUILD_DIR=${BUILD_DIR:-"$GITHUB_WORKSPACE/action_build"}
    DHCP_CONF_PATH="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    
    # 检查文件是否存在
    if [ ! -f "$DHCP_CONF_PATH" ]; then
        echo "错误: 找不到 DHCP 配置文件 $DHCP_CONF_PATH"
        exit 1
    fi

    # 使用 sed 修改配置文件（确保语法正确）
    sed -i '/config dhcp lan/,/^$/ {
        /^$/i\\
        \toption ignore\t1
    }' "$DHCP_CONF_PATH"
}
# 调用函数
set_dhcp_off
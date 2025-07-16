#!/usr/bin/env bash

set -e
set -o errexit
set -o errtrace

# 定义错误处理函数
error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

# 设置trap捕获ERR信号
trap 'error_handler' ERR

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="24.x"
THEME_SET="argon"
LAN_ADDR="192.168.1.1"

clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo $REPO_URL $REPO_BRANCH
        git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR
    fi
}

clean_up() {
    cd $BUILD_DIR
    if [[ -f $BUILD_DIR/.config ]]; then
        \rm -f $BUILD_DIR/.config
    fi
    if [[ -d $BUILD_DIR/tmp ]]; then
        \rm -rf $BUILD_DIR/tmp
    fi
    if [[ -d $BUILD_DIR/logs ]]; then
        \rm -rf $BUILD_DIR/logs/*
    fi
    mkdir -p $BUILD_DIR/tmp
    echo "1" >$BUILD_DIR/tmp/.build
}

reset_feeds_conf() {
    git reset --hard origin/$REPO_BRANCH
    git clean -f -d
    git pull
    if [[ $COMMIT_HASH != "none" ]]; then
        git checkout $COMMIT_HASH
    fi
}

update_feeds() {
    # 删除注释行
    sed -i '/^#/d' "$BUILD_DIR/$FEEDS_CONF"

    # 检查并添加 small-package 源
    if ! grep -q "small-package" "$BUILD_DIR/$FEEDS_CONF"; then
        # 确保文件以换行符结尾
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git small8 https://github.com/kenzok8/small-package" >>"$BUILD_DIR/$FEEDS_CONF"
    fi

    # 添加bpf.mk解决更新报错
    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi

    # 切换nss-packages源
    # if grep -q "nss_packages" "$BUILD_DIR/$FEEDS_CONF"; then
    #     sed -i '/nss_packages/d' "$BUILD_DIR/$FEEDS_CONF"
    #     [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
    #     echo "src-git nss_packages https://github.com/LiBwrt/nss-packages.git" >>"$BUILD_DIR/$FEEDS_CONF"
    # fi

    # 更新 feeds
    ./scripts/feeds clean
    ./scripts/feeds update -a
}

remove_unwanted_packages() {
    local luci_packages=(
        "luci-app-passwall" "luci-app-smartdns" "luci-app-ddns-go" "luci-app-rclone"
        "luci-app-ssr-plus" "luci-app-vssr" "luci-theme-argon" "luci-app-daed" "luci-app-dae"
        "luci-app-alist" "luci-app-argon-config" "luci-app-homeproxy" "luci-app-haproxy-tcp"
        "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter" "luci-app-msd_lite"
    )
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "smartdns" "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs"
        "shadowsocksr-libev" "dae" "daed" "mihomo" "geoview" "tailscale" "open-app-filter"
        "msd_lite"
    )
    local packages_utils=(
        "cups"
    )
    local small8_packages=(
        "ppp" "firewall" "dae" "daed" "daed-next" "libnftnl" "nftables" "dnsmasq" "luci-app-alist" "alist"
    )

    for pkg in "${luci_packages[@]}"; do
        if [[ -d ./feeds/luci/applications/$pkg ]]; then
            \rm -rf ./feeds/luci/applications/$pkg
        fi
        if [[ -d ./feeds/luci/themes/$pkg ]]; then
            \rm -rf ./feeds/luci/themes/$pkg
        fi
    done

    for pkg in "${packages_net[@]}"; do
        if [[ -d ./feeds/packages/net/$pkg ]]; then
            \rm -rf ./feeds/packages/net/$pkg
        fi
    done

    for pkg in "${packages_utils[@]}"; do
        if [[ -d ./feeds/packages/utils/$pkg ]]; then
            \rm -rf ./feeds/packages/utils/$pkg
        fi
    done

    for pkg in "${small8_packages[@]}"; do
        if [[ -d ./feeds/small8/$pkg ]]; then
            \rm -rf ./feeds/small8/$pkg
        fi
    done

    if [[ -d ./package/istore ]]; then
        \rm -rf ./package/istore
    fi

    # ipq60xx不支持NSS offload mnet_rx
    # if grep -q "nss_packages" "$BUILD_DIR/$FEEDS_CONF"; then
    #     rm -rf "$BUILD_DIR/feeds/nss_packages/wwan"
    # fi

    # 临时放一下，清理脚本
    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
}

update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        \rm -rf ./feeds/packages/lang/golang
        git clone --depth 1 $GOLANG_REPO -b $GOLANG_BRANCH ./feeds/packages/lang/golang
    fi
}

install_small8() {
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        luci-app-passwall alist luci-app-alist smartdns luci-app-smartdns v2dat mosdns luci-app-mosdns \
        adguardhome luci-app-adguardhome ddns-go luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd \
        luci-app-store quickstart luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest \
        luci-theme-argon netdata luci-app-netdata lucky luci-app-lucky luci-app-openclash luci-app-homeproxy \
        luci-app-amlogic nikki luci-app-nikki tailscale luci-app-tailscale oaf open-app-filter luci-app-oaf \
        easytier luci-app-easytier msd_lite luci-app-msd_lite luci-app-argon-config cups luci-app-cupsd
}

install_feeds() {
    ./scripts/feeds update -i
    for dir in $BUILD_DIR/feeds/*; do
        # 检查是否为目录并且不以 .tmp 结尾，并且不是软链接
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [ ! -L "$dir" ]; then
            if [[ $(basename "$dir") == "small8" ]]; then
                install_small8
                install_fullconenat
            else
                ./scripts/feeds install -f -ap $(basename "$dir")
            fi
        fi
    done
}

fix_default_set() {
    # 修改默认主题
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    if [ -d "$BUILD_DIR/feeds/small8/luci-theme-argon" ]; then
        find "$BUILD_DIR/feeds/small8/luci-theme-argon" -type f -name "cascade*" -exec sed -i 's/--bar-bg/--primary/g' {} \;
    fi

    install -Dm755 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm755 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"

    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

fix_miniupnpd() {
    local miniupnpd_dir="$BUILD_DIR/feeds/packages/net/miniupnpd"
    local patch_file="999-chanage-default-leaseduration.patch"

    if [ -d "$miniupnpd_dir" ] && [ -f "$BASE_PATH/patches/$patch_file" ]; then
        install -Dm644 "$BASE_PATH/patches/$patch_file" "$miniupnpd_dir/patches/$patch_file"
    fi
}

change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
}

install_fullconenat() {
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat-nft ]; then
        ./scripts/feeds install -p small8 -f fullconenat-nft
    fi
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat ]; then
        ./scripts/feeds install -p small8 -f fullconenat
    fi
}

fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' $BUILD_DIR/include/target.mk 2>/dev/null
    if [ -f $BUILD_DIR/target/linux/qualcommax/Makefile ]; then
        sed -i 's/wpad-openssl/wpad-mesh-openssl/g' $BUILD_DIR/target/linux/qualcommax/Makefile
    fi
}

add_wifi_default_set() {
    local qualcommax_uci_dir="$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults"
    local filogic_uci_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/etc/uci-defaults"
    if [ -d "$qualcommax_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$qualcommax_uci_dir/992_set-wifi-uci.sh"
    fi
    if [ -d "$filogic_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$filogic_uci_dir/992_set-wifi-uci.sh"
    fi
}

update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f $CFG_PATH ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' $CFG_PATH
    fi
}

remove_something_nss_kmod() {
    local ipq_target_path="$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk"
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    if [ -f $ipq_target_path ]; then
        sed -i 's/kmod-qca-nss-drv-eogremgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-gre//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-map-t//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-match//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-mirror//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-pvxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tun6rd//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tunipip6//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-vxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-macsec//g' $ipq_target_path
    fi

    if [ -f $ipq_mk_path ]; then
        sed -i 's/kmod-qca-nss-crypto //g' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-eogremgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-gre/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-map-t/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-match/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-mirror/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-tun6rd/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-tunipip6/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-vxlanmgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-macsec/d' $ipq_mk_path

        sed -i 's/automount //g' $ipq_mk_path
        sed -i 's/cpufreq //g' $ipq_mk_path
    fi
}

update_affinity_script() {
    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"

    if [ -d "$affinity_script_dir" ]; then
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
        install -Dm755 "$BASE_PATH/patches/smp_affinity" "$affinity_script_dir/base-files/etc/init.d/smp_affinity"
    fi
}

fix_build_for_openssl() {
    local openssl_dir="$BUILD_DIR/package/libs/openssl"
    local makefile="$openssl_dir/Makefile"
    if [ -d "$(dirname "$makefile")" ] && [ -f "$makefile" ]; then
        if grep -q "3.0.16" "$makefile"; then
            # 替换本地openssl版本
            rm -rf "$openssl_dir"
            cp -rf "$BASE_PATH/patches/openssl" "$openssl_dir"
        fi
    fi
}

update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    local new_mk="$BASE_PATH/patches/ath11k_fw.mk"

    if [ -d "$(dirname "$makefile")" ] && [ -f "$makefile" ]; then
        [ -f "$new_mk" ] && \rm -f "$new_mk"
        curl -L -o "$new_mk" https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile
        \mv -f "$new_mk" "$makefile"
    fi
}

fix_mkpkg_format_invalid() {
    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        if [ -f $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-store/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
        fi
    fi
}

add_ax6600_led() {
    local athena_led_dir="$BUILD_DIR/package/emortal/luci-app-athena-led"

    # 删除旧的目录（如果存在）
    rm -rf "$athena_led_dir" 2>/dev/null

    # 克隆最新的仓库
    git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led.git "$athena_led_dir"
    # 设置执行权限
    chmod +x "$athena_led_dir/root/usr/sbin/athena-led"
    chmod +x "$athena_led_dir/root/etc/init.d/athena_led"
}

change_cpuusage() {
    local luci_rpc_path="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    local qualcommax_sbin_dir="$BUILD_DIR/target/linux/qualcommax/base-files/sbin"
    local filogic_sbin_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/sbin"

    # Modify LuCI RPC script to prefer our custom cpuusage script
    if [ -f "$luci_rpc_path" ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" "$luci_rpc_path"
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' "$luci_rpc_path"
    fi

    # Remove old script if it exists from a previous build
    local old_script_path="$BUILD_DIR/package/base-files/files/sbin/cpuusage"
    if [ -f "$old_script_path" ]; then
        rm -f "$old_script_path"
    fi

    # Install platform-specific cpuusage scripts
    install -Dm755 "$BASE_PATH/patches/cpuusage" "$qualcommax_sbin_dir/cpuusage"
    install -Dm755 "$BASE_PATH/patches/hnatusage" "$filogic_sbin_dir/cpuusage"
}

update_tcping() {
    local tcping_path="$BUILD_DIR/feeds/small8/tcping/Makefile"

    if [ -d "$(dirname "$tcping_path")" ] && [ -f "$tcping_path" ]; then
        \rm -f "$tcping_path"
        curl -L -o "$tcping_path" https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/refs/heads/main/tcping/Makefile
    fi
}

set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
# 设置启动优先级
START=99

boot() {
    # 重新添加缓存请求定时任务
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root

    # 删除现有的 wireguard_watchdog 任务
    sed -i '/wireguard_watchdog/d' /etc/crontabs/root

    # 获取 WireGuard 接口名称
    local wg_ifname=$(wg show | awk '/interface/ {print $2}')

    if [ -n "$wg_ifname" ]; then
        # 添加新的 wireguard_watchdog 任务，每10分钟执行一次
        echo "*/15 * * * * /usr/bin/wireguard_watchdog" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi

    # 应用新的 crontab 配置
    crontab /etc/crontabs/root
}
EOF
    chmod +x "$sh_dir/custom_task"
}

update_pw() {
    local pw_share_dir="$BUILD_DIR/feeds/small8/luci-app-passwall/root/usr/share/passwall"
    local smartdns_lua_path="$pw_share_dir/helper_smartdns_add.lua"
    local rules_dir="$pw_share_dir/rules"

    # 清空chnlist
    [ -f "$rules_dir/chnlist" ] && echo "" >"$rules_dir/chnlist"
}

install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"

    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        cat <<'EOF' >"$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF

        sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile

        sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
    fi
}

update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f $pbuf_path ]; then
        sed -i "s/auto_scale '1'/auto_scale 'off'/g" $pbuf_path
        sed -i "s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" $pbuf_path
    fi
}

set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by ZqinKing')/g" "$file"
    fi
}

fix_compile_vlmcsd() {
    local dir="$BUILD_DIR/feeds/packages/net/vlmcsd"
    local patch_src="$BASE_PATH/patches/001-fix_compile_with_ccache.patch"
    local patch_dest="$dir/patches"

    if [ -d "$dir" ]; then
        mkdir -p "$patch_dest"
        cp -f "$patch_src" "$patch_dest"
    fi
}

update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        \rm -f "$file"
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
    fi
}

update_menu_location() {
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then
        sed -i 's/nas/services/g' "$samba4_path"
    fi

    local tailscale_path="$BUILD_DIR/feeds/small8/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi
}

fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}

update_homeproxy() {
    local repo_url="https://github.com/immortalwrt/homeproxy.git"
    local target_dir="$BUILD_DIR/feeds/small8/luci-app-homeproxy"

    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
        git clone --depth 1 "$repo_url" "$target_dir"
    fi
}

update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i '/dns_redirect/d' "$file"
    fi
}

# 更新版本
update_package() {
    local dir=$(find "$BUILD_DIR/package" \( -type d -o -type l \) -name $1)
    if [ -z "$dir" ]; then
        return 0
    fi
    local branch=$2
    if [ -z "$branch" ]; then
        branch="releases"
    fi
    local mk_path="$dir/Makefile"
    if [ -f "$mk_path" ]; then
        # 提取repo
        local PKG_REPO=$(grep -oE "^PKG_GIT_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" $mk_path | awk -F"/" '{print $(NF - 1) "/" $NF}')
        if [ -z "$PKG_REPO" ]; then
            PKG_REPO=$(grep -oE "^PKG_SOURCE_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" $mk_path | awk -F"/" '{print $(NF - 1) "/" $NF}')
            if [ -z "$PKG_REPO" ]; then
                return 0
            fi
        fi
        local PKG_VER=$(curl -sL "https://api.github.com/repos/$PKG_REPO/$branch" | jq -r '.[0] | .tag_name // .name')
        if [ -n "$3" ]; then
            PKG_VER=$3
        fi
        # 修复标签类型识别
        local tag_ref_info
        tag_ref_info=$(curl -sL "https://api.github.com/repos/$PKG_REPO/git/ref/tags/$PKG_VER")
        local COMMIT_SHA
    
        # 检查标签类型
        if [ "$(echo "$tag_ref_info" | jq -r '.object.type')" == "tag" ]; then
            # 处理附注标签 - 需要二次请求
            local tag_obj_url=$(echo "$tag_ref_info" | jq -r '.object.url')
            if [ "$tag_obj_url" != "null" ]; then
                tag_info=$(curl -sL "$tag_obj_url")
                COMMIT_SHA=$(echo "$tag_info" | jq -r '.object.sha')
            fi
        else
            # 轻量标签直接取SHA
            COMMIT_SHA=$(echo "$tag_ref_info" | jq -r '.object.sha')
        fi
    
        # 截取短SHA
        COMMIT_SHA=$(echo "$COMMIT_SHA" | cut -c1-7)
    
        if [ -n "$COMMIT_SHA" ]; then
            sed -i 's/^PKG_GIT_SHORT_COMMIT:=.*/PKG_GIT_SHORT_COMMIT:='$COMMIT_SHA'/g' $mk_path
        fi
		
        PKG_VER=$(echo $PKG_VER | grep -oE "[\.0-9]{1,}")

        local PKG_NAME=$(awk -F"=" '/PKG_NAME:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE=$(awk -F"=" '/PKG_SOURCE:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE_URL=$(awk -F"=" '/PKG_SOURCE_URL:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\{\}\?\.a-zA-Z0-9]{1,}")
        local PKG_GIT_URL=$(awk -F"=" '/PKG_GIT_URL:=/ {print $NF}' $mk_path)
        local PKG_GIT_REF=$(awk -F"=" '/PKG_GIT_REF:=/ {print $NF}' $mk_path)

        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_GIT_URL\)/$PKG_GIT_URL}
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_GIT_REF\)/$PKG_GIT_REF}
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE_URL=$(echo "$PKG_SOURCE_URL" | sed "s/\${PKG_VERSION}/$PKG_VER/g; s/\$(PKG_VERSION)/$PKG_VER/g")
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_VERSION\)/$PKG_VER}

        local PKG_HASH=$(curl -sL "$PKG_SOURCE_URL""$PKG_SOURCE" | sha256sum | cut -b -64)

        sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:='$PKG_VER'/g' $mk_path
        sed -i 's/^PKG_HASH:=.*/PKG_HASH:='$PKG_HASH'/g' $mk_path

        echo "Update Package $1 to $PKG_VER $PKG_HASH"
    fi
}

# 添加系统升级时的备份信息
function add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"

    if [ -f "$conf_path" ]; then
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
    fi
}

# 更新启动顺序
function update_script_priority() {
    # 更新qca-nss驱动的启动顺序
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then
        sed -i 's/START=.*/START=88/g' "$qca_drv_path"
    fi

    # 更新pbuf服务的启动顺序
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then
        sed -i 's/START=.*/START=89/g' "$pbuf_path"
    fi

    # 更新mosdns服务的启动顺序
    local mosdns_path="$BUILD_DIR/package/feeds/small8/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}

function optimize_smartDNS() {
    local smartdns_custom="$BUILD_DIR/feeds/small8/smartdns/conf/custom.conf"
    local smartdns_patch="$BUILD_DIR/feeds/small8/smartdns/patches/010_change_start_order.patch"
    install -Dm644 "$BASE_PATH/patches/010_change_start_order.patch" "$smartdns_patch"

    # 检查配置文件所在的目录和文件是否存在
    if [ -d "${smartdns_custom%/*}" ] && [ -f "$smartdns_custom" ]; then
        # 优化配置选项：
        # serve-expired-ttl: 缓存有效期(单位：小时)，默认值影响DNS解析速度
        # serve-expired-reply-ttl: 过期回复TTL
        # max-reply-ip-num: 最大IP数
        # dualstack-ip-selection-threshold: IPv6优先的阈值
        # server: 配置上游DNS
        echo "优化SmartDNS配置"
        cat >"$smartdns_custom" <<'EOF'
serve-expired-ttl 7200
serve-expired-reply-ttl 5
max-reply-ip-num 3
dualstack-ip-selection-threshold 15
server 223.5.5.5 -bootstrap-dns
EOF
    fi
}

update_mosdns_deconfig() {
    local mosdns_conf="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}

fix_quickstart() {
    local file_path="$BUILD_DIR/feeds/small8/luci-app-quickstart/luasrc/controller/istore_backend.lua"
    # 下载新的istore_backend.lua文件并覆盖
    if [ -f "$file_path" ]; then
        \rm -f "$file_path"
        curl -L https://gist.githubusercontent.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa/raw/istore_backend.lua \
            -o "$file_path"
    fi
}

update_oaf_deconfig() {
    local conf_path="$BUILD_DIR/feeds/small8/open-app-filter/files/appfilter.config"
    local uci_def="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0"
    local disable_path="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/99_disable_oaf"

    if [ -d "${conf_path%/*}" ] && [ -f "$conf_path" ]; then
        sed -i \
            -e "s/record_enable '1'/record_enable '0'/g" \
            -e "s/disable_hnat '1'/disable_hnat '0'/g" \
            -e "s/auto_load_engine '1'/auto_load_engine '0'/g" \
            "$conf_path"
    fi

    if [ -d "${uci_def%/*}" ] && [ -f "$uci_def" ]; then
        sed -i '/\(disable_hnat\|auto_load_engine\)/d' "$uci_def"

        # 禁用脚本
        cat >"$disable_path" <<-EOF
#!/bin/sh
[ "\$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
        chmod +x "$disable_path"
    fi
}

support_fw4_adg() {
    local src_path="$BASE_PATH/patches/AdGuardHome"
    local dst_path="$BUILD_DIR/package/feeds/small8/luci-app-adguardhome/root/etc/init.d/AdGuardHome"
    # 验证源路径是否文件存在且是文件，目标路径目录存在且脚本路径合法
    if [ -f "$src_path" ] && [ -d "${dst_path%/*}" ] && [ -f "$dst_path" ]; then
        # 使用 install 命令替代 cp 以确保权限和备份处理
        install -Dm 755 "$src_path" "$dst_path"
        echo "已更新AdGuardHome启动脚本"
    fi
}

add_timecontrol() {
    local timecontrol_dir="$BUILD_DIR/package/luci-app-timecontrol"
    # 删除旧的目录（如果存在）
    rm -rf "$timecontrol_dir" 2>/dev/null
    git clone --depth 1 https://github.com/sirpdboy/luci-app-timecontrol.git "$timecontrol_dir"
}

add_gecoosac() {
    local gecoosac_dir="$BUILD_DIR/package/openwrt-gecoosac"
    # 删除旧的目录（如果存在）
    rm -rf "$gecoosac_dir" 2>/dev/null
    git clone --depth 1 https://github.com/lwb1978/openwrt-gecoosac.git "$gecoosac_dir"
}

update_proxy_app_menu_location() {
    # passwall
    local passwall_path="$BUILD_DIR/package/feeds/small8/luci-app-passwall/luasrc/controller/passwall.lua"
    if [ -d "${passwall_path%/*}" ] && [ -f "$passwall_path" ]; then
        local pos=$(grep -n "entry" "$passwall_path" | head -n 1 | awk -F ":" '{print $1}')
        if [ -n "$pos" ]; then
            sed -i ''${pos}'i\	entry({"admin", "proxy"}, firstchild(), "Proxy", 30).dependent = false' "$passwall_path"
            sed -i 's/"services"/"proxy"/g' "$passwall_path"
        fi
    fi

    # homeproxy
    local homeproxy_path="$BUILD_DIR/package/feeds/small8/luci-app-homeproxy/root/usr/share/luci/menu.d/luci-app-homeproxy.json"
    if [ -d "${homeproxy_path%/*}" ] && [ -f "$homeproxy_path" ]; then
        sed -i 's/\/services\//\/proxy\//g' "$homeproxy_path"
    fi

    # nikki
    local nikki_path="$BUILD_DIR/package/feeds/small8/luci-app-nikki/root/usr/share/luci/menu.d/luci-app-nikki.json"
    if [ -d "${nikki_path%/*}" ] && [ -f "$nikki_path" ]; then
        sed -i 's/\/services\//\/proxy\//g' "$nikki_path"
    fi
}

update_dns_app_menu_location() {
    # smartdns
    local smartdns_path="$BUILD_DIR/package/feeds/small8/luci-app-smartdns/luasrc/controller/smartdns.lua"
    if [ -d "${smartdns_path%/*}" ] && [ -f "$smartdns_path" ]; then
        local pos=$(grep -n "entry" "$smartdns_path" | head -n 1 | awk -F ":" '{print $1}')
        if [ -n "$pos" ]; then
            sed -i ''${pos}'i\	entry({"admin", "dns"}, firstchild(), "DNS", 29).dependent = false' "$smartdns_path"
            sed -i 's/"services"/"dns"/g' "$smartdns_path"
        fi
    fi

    # mosdns
    local mosdns_path="$BUILD_DIR/package/feeds/small8/luci-app-mosdns/root/usr/share/luci/menu.d/luci-app-mosdns.json"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/\/services\//\/dns\//g' "$mosdns_path"
    fi

    # AdGuardHome
    local adg_path="$BUILD_DIR/package/feeds/small8/luci-app-adguardhome/luasrc/controller/AdGuardHome.lua"
    if [ -d "${adg_path%/*}" ] && [ -f "$adg_path" ]; then
        sed -i 's/"services"/"dns"/g' "$adg_path"
    fi
}

fix_easytier() {
    local easytier_path="$BUILD_DIR/package/feeds/small8/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -d "${easytier_path%/*}" ] && [ -f "$easytier_path" ]; then
        sed -i 's/util/xml/g' "$easytier_path"
    fi
}

update_geoip() {
    local geodata_path="$BUILD_DIR/package/feeds/small8/v2ray-geodata/Makefile"
    if [ -d "${geodata_path%/*}" ] && [ -f "$geodata_path" ]; then
        local GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' $geodata_path | grep -oE "[0-9]{1,}")
        if [ -n "$GEOIP_VER" ]; then
            local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
            # 下载旧的geoip.dat和新的geoip-only-cn-private.dat文件的校验和
            local old_SHA256=$(wget -qO- "$base_url/geoip.dat.sha256sum" | awk '{print $1}')
            local new_SHA256=$(wget -qO- "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}')
            # 更新Makefile中的文件名和校验和
            if [ -n "$old_SHA256" ] && [ -n "$new_SHA256" ]; then
                if grep -q "$old_SHA256" "$geodata_path"; then
                    sed -i "s|=geoip.dat|=geoip-only-cn-private.dat|g" "$geodata_path"
                    sed -i "s/$old_SHA256/$new_SHA256/g" "$geodata_path"
                fi
            fi
        fi
    fi
}

update_lucky() {
    # 从补丁文件名中提取版本号
    local version
    version=$(find "$BASE_PATH/patches" -name "lucky_*.tar.gz" -printf "%f\n" | head -n 1 | sed -n 's/^lucky_\(.*\)_Linux.*$/\1/p')
    if [ -z "$version" ]; then
        echo "Warning: 未找到 lucky 补丁文件，跳过更新。" >&2
        return 1
    fi

    local makefile_path="$BUILD_DIR/feeds/small8/lucky/Makefile"
    if [ ! -f "$makefile_path" ]; then
        echo "Warning: lucky Makefile not found. Skipping." >&2
        return 1
    fi

    echo "正在更新 lucky Makefile..."
    # 使用本地补丁文件，而不是下载
    local patch_line="\\t[ -f \$(TOPDIR)/../patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz ] && install -Dm644 \$(TOPDIR)/../patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz \$(PKG_BUILD_DIR)/\$(PKG_NAME)_\$(PKG_VERSION)_Linux_\$(LUCKY_ARCH).tar.gz"

    # 确保 Build/Prepare 部分存在，然后在其后添加我们的行
    if grep -q "Build/Prepare" "$makefile_path"; then
        sed -i "/Build\\/Prepare/a\\$patch_line" "$makefile_path"
        # 删除任何现有的 wget 命令
        sed -i '/wget/d' "$makefile_path"
        echo "lucky Makefile 更新完成。"
    else
        echo "Warning: lucky Makefile 中未找到 'Build/Prepare'。跳过。" >&2
    fi
}

fix_rust_compile_error() {
    if [ -f "$BUILD_DIR/feeds/packages/lang/rust/Makefile" ]; then
        sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$BUILD_DIR/feeds/packages/lang/rust/Makefile"
    fi
}

update_smartdns() {
    local feeds_dir="$BUILD_DIR/feeds/small8"
    local luci_app_smartdns_path="$feeds_dir/luci-app-smartdns"
    local old_smartdns_pkg_path="$feeds_dir/smartdns"
    local new_smartdns_pkg_path="$feeds_dir/openwrt-smartdns"
    local tmp_dir

    echo "正在更新 luci-app-smartdns..."
    # 删除旧版并克隆新版
    \rm -rf "$luci_app_smartdns_path"
    if ! git clone --depth 1 -b master https://github.com/pymumu/luci-app-smartdns.git "$luci_app_smartdns_path"; then
        echo "错误：克隆 luci-app-smartdns 失败。" >&2
        return 1
    fi

    # 修复 Makefile 中的路径
    local makefile_path="$luci_app_smartdns_path/Makefile"
    if [ -f "$makefile_path" ]; then
        sed -i 's/\.\.\/\.\.\/luci\.mk/$(TOPDIR)\/feeds\/luci\/luci\.mk/g' "$makefile_path"
    fi

    echo "正在更新 smartdns..."

    # 使用临时目录克隆
    tmp_dir=$(mktemp -d)
    if ! git clone --depth 1 -b master https://github.com/pymumu/openwrt-smartdns.git "$tmp_dir"; then
        echo "错误：克隆 openwrt-smartdns 仓库失败。" >&2
        rm -rf "$tmp_dir"
        return 1
    else
        # 删除旧版
        rm -rf "$old_smartdns_pkg_path"
        mv "$tmp_dir" "$new_smartdns_pkg_path"

        # 修复 Makefile 中的路径
        makefile_path="$new_smartdns_pkg_path/Makefile"
        if [ -f "$makefile_path" ]; then
            sed -i 's/\.\.\/\.\.\/lang/$(TOPDIR)\/feeds\/packages\/lang/g' "$makefile_path"
        fi
    fi

    echo "SmartDNS 更新完成。"
}

update_diskman() {
    local path="$BUILD_DIR/feeds/luci/applications/luci-app-diskman"
    if [ -d "$path" ]; then
        cd "$BUILD_DIR/feeds/luci/applications" || return # 显式路径避免歧义
        \rm -rf "luci-app-diskman"                        # 直接删除目标目录

        git clone --filter=blob:none --no-checkout https://github.com/lisaac/luci-app-diskman.git diskman || return
        cd diskman || return

        git sparse-checkout init --cone
        git sparse-checkout set applications/luci-app-diskman || return # 错误处理

        git checkout --quiet # 静默检出避免冗余输出

        mv applications/luci-app-diskman ../luci-app-diskman || return # 添加错误检查
        cd .. || return
        \rm -rf diskman
        cd "$BUILD_DIR"

        sed -i 's/fs-ntfs /fs-ntfs3 /g' "$path/Makefile"
        sed -i '/ntfs-3g-utils /d' "$path/Makefile"
    fi
}

#  fix_samba4() {
#      local SAMBA4_MAKEFILE="$BUILD_DIR/feeds/packages/net/samba4/Makefile"
#  
#      # 检查 samba4-libs 的依赖中是否已经包含了 libcrypt-compat
#      if ! sed -n '/define Package\/samba4-libs/,/endef/p' "$SAMBA4_MAKEFILE" | grep -q 'DEPENDS:=.*+libcrypt-compat'; then
#          echo "Adding +libcrypt-compat dependency to samba4-libs..."
#          # 使用更健壮的命令来添加依赖
#          sed -i '/define Package\/samba4-libs/,/endef/s/^\(\s*DEPENDS:=\)/\1 +libcrypt-compat/' "$SAMBA4_MAKEFILE"
#      else
#          echo "Dependency +libcrypt-compat already exists in samba4-libs."
#      fi
#  }

smart_fix_samba4() {
    local samba_makefile="$BUILD_DIR/feeds/packages/net/samba4/Makefile"
    
    if [ ! -f "$samba_makefile" ]; then
        echo "⚠️ samba4包不存在，跳过修复"
        return
    fi
    # 检测是否为24.10分支
    local is_24_10_branch=0
    if grep -qE "src-git.*(packages|luci|routing|telephony).*openwrt-24\.10" "$BUILD_DIR"/feeds.conf*; then
        is_24_10_branch=1
        echo "🔍 检测到 openwrt-24.10 分支，应用兼容性修复"
    fi
    
    # 应用基本修复（所有分支）
    sed -i \
        -e "s/PKG_CONFIG_DEPENDS:=/PKG_CONFIG_DEPENDS:= /" \
        -e "s/--enable-fhs/--enable-fhs --without-pam --without-ads --without-ad-dc/" \
        "$samba_makefile"
    
    # 仅对非24.10分支添加 libcrypt-compat
    if [ "$is_24_10_branch" -eq 0 ]; then
        echo "⚠️ 为非24.10分支添加额外依赖"
        # 在DEPENDS行末尾添加 libcrypt-compat
        sed -i '/DEPENDS/ s/$/ libcrypt-compat/' "$samba_makefile"
    fi
}

main() {
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    remove_unwanted_packages
    update_homeproxy
    fix_default_set
    fix_miniupnpd
    update_golang
    change_dnsmasq2full
    fix_mk_def_depends
    add_wifi_default_set
    update_default_lan_addr
    remove_something_nss_kmod
    update_affinity_script
    # fix_build_for_openssl
    update_ath11k_fw
    # fix_mkpkg_format_invalid
    change_cpuusage
    update_tcping
    add_ax6600_led
    set_custom_task
    update_pw
    install_opkg_distfeeds
    update_nss_pbuf_performance
    set_build_signature
    fix_compile_vlmcsd
    update_nss_diag
    update_menu_location
    fix_compile_coremark
    update_dnsmasq_conf
    add_backup_info_to_sysupgrade
    optimize_smartDNS
    update_mosdns_deconfig
    fix_quickstart
    update_oaf_deconfig
    add_timecontrol
    add_gecoosac
    update_lucky
    fix_rust_compile_error
    # update_smartdns 暂不更新，openwrt-smartdns不适配
    update_diskman
    # fix_samba4
	smart_fix_samba4
    install_feeds
    support_fw4_adg
    update_script_priority
    fix_easytier
    update_geoip
    update_package "runc" "releases" "v1.2.6"
    update_package "containerd" "releases" "v1.7.27"
    update_package "docker" "tags" "v28.2.2"
    update_package "dockerd" "releases" "v28.2.2"
    # update_package "xray-core"
    # update_proxy_app_menu_location
    # update_dns_app_menu_location
}

main "$@"

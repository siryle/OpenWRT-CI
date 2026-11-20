#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
LAN_IP="${WRT_IP:-192.168.1.1}"
#修改immortalwrt.lan关联IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$LAN_IP/g" {} +
#添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

#修改默认WIFI账号密码
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
ROUTER_TOOL="./package/emortal/luci-app-router-tool/root/etc/config/router-tool"
for file in "$ROUTER_TOOL" "$WIFI_UC"; do
	[ -f "$file" ] && sed -i "s/ssid '.*'/ssid '$WRT_SSID'/g; s/key '.*'/key '$WRT_WORD'/g" "$file"
done

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
grep -q 'lan) ipad=${ipaddr:-""}' "$CFG_FILE" 2>/dev/null && \
	sed -i 's#lan) ipad=${ipaddr:-""}#lan) ipad=${ipaddr:-"192.168.1.1"}#' "$CFG_FILE"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$LAN_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "$WRT_WIFI" == "WIFI-NO" ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

# 修改内核分区大小（qualcommax 平台开启 BTF/BPF 后内核体积增大，扩容避免 Kernel is too big 报错）
if [ -d target/linux/qualcommax/image ]; then
	for file in target/linux/qualcommax/image/*.mk; do
		sed -i 's/KERNEL_SIZE := [0-9]*k/KERNEL_SIZE := 12288k/g' "$file"
	done
	echo "qualcommax KERNEL_SIZE adjusted to 12288k for BTF support"
fi

# 固定 qualcommax 在内核下的 perf/PMU 选项，防止开启 BPF_EVENTS 时触发交互配置提示
target=$(grep -m 1 -oP '^CONFIG_TARGET_qualcommax_\K[[:alnum:]_]+(?=\=y)' "$GITHUB_WORKSPACE/Config/${WRT_CONFIG}.txt" 2>/dev/null || true)
if [ -n "$target" ] && [ -f "target/linux/qualcommax/${target}/config-default" ]; then
	cat >> "target/linux/qualcommax/${target}/config-default" <<'EOF'

# Kernel eBPF/BTF perf dependencies
# CONFIG_ARM64_BRBE is not set
# CONFIG_ARM_CCI_PMU is not set
# CONFIG_ARM_CCN is not set
# CONFIG_ARM_CMN is not set
# CONFIG_ARM_NI is not set
# CONFIG_ARM_SMMU_V3_PMU is not set
# CONFIG_ARM_DSU_PMU is not set
# CONFIG_ARM_SPE_PMU is not set
EOF
	echo "qualcommax perf/PMU kernel config pinned"
fi

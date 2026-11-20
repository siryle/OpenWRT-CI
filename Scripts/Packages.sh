#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_PATH="./package/$REPO_NAME"

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not fonud directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git" $REPO_PATH

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find $REPO_PATH -mindepth 1 -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		rm -rf $REPO_PATH
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg，可选，从大杂烩中单独提取包名插件"
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "fluent" "LazuliKao/luci-theme-fluent" "main"
UPDATE_PACKAGE "footstrap" "VizzleTF/luci-theme-footstrap" "main"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "shadcn" "eamonxg/luci-theme-shadcn" "main"
UPDATE_PACKAGE "vantage" "anothaDev/luci-theme-vantage" "main"

UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

# Honk 透明代理核心 + LuCI/Doona
UPDATE_PACKAGE "honk" "kenzok8/openwrt-honk" "main" "pkg"
# Honk 所需的 GeoIP / GeoSite 数据包
UPDATE_PACKAGE "v2ray-geodata" "kenzok8/wall" "main" "pkg" "v2ray-geoip v2ray-geosite"

# X86/ROCKCHIP：应用针对 x86/RK 平台优化和 p1 core 的补丁（若存在且启用）
case "$WRT_CONFIG" in
X86|ROCKCHIP)
	if [ -f "$GITHUB_WORKSPACE/patches/honk/honk-x86rk.patch" ] && [ "${HONK_STOCK:-false}" != "true" ]; then
		if patch -p1 -d ./package --no-backup-if-mismatch \
			-i "$GITHUB_WORKSPACE/patches/honk/honk-x86rk.patch"; then
			echo "honk: applied x86/RK patch successfully"
			if [ -f "$GITHUB_WORKSPACE/patches/honk/apply-makefile.sh" ]; then
				sh "$GITHUB_WORKSPACE/patches/honk/apply-makefile.sh" ./package/honk/Makefile
			fi
		else
			echo "!! honk: x86/RK patch did not apply, keeping stock" >&2
		fi
	fi
	;;
esac

# firewall4: 接受当前 runner 生成的归档哈希（解决源码 commit 相同但 tar 归档重打包哈希漂移导致报错的问题）
FW4=./package/network/config/firewall4/Makefile
if [ -f "$FW4" ] && grep -q '^PKG_MIRROR_HASH:=70cbaec533e7d635' "$FW4"; then
	sed -i 's|^PKG_MIRROR_HASH:=70cbaec533e7d635c00f5288a31a1d5d44cd43390d18c2df296e00079d1e4efe$|PKG_MIRROR_HASH:=a95c6cfe419c7d4e22bda5608aa6e46c67dadc9c7096879702d614cc498759d0|' "$FW4"
	echo "firewall4: accepted the regenerated archive hash (commit 3722eadc unchanged)"
fi

# 获取 honk stage 编译/哈希文件（仅在 x86/RK 应用了 p1 核心补丁时需要）
fetch_honk_stage() {
	local core rel_json base stage prov doona
	[ -d ./package/honk ] || return 0
	core=$(sed -n 's/^CORE_COMMIT:=//p' ./package/honk/Makefile 2>/dev/null | head -1)
	[ -n "$core" ] || return 0
	# 如果 Makefile 没有引用 core-p1 则说明使用 upstream 原版，无需 fetch stage
	grep -q 'core-p1' ./package/honk/Makefile || return 0

	if [ -n "${GITHUB_TOKEN:-}" ]; then
		rel_json=$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" \
			"https://api.github.com/repos/kwrum1/dpd-fw/releases?per_page=30" 2>/dev/null)
	fi
	if [ -z "${rel_json:-}" ]; then
		rel_json=$(curl -fsSL \
			"https://api.github.com/repos/kwrum1/dpd-fw/releases?per_page=30" 2>/dev/null)
	fi

	pick_from() {
		printf '%s' "$rel_json" | jq -r --arg a "$1" --arg n "$2" \
			'[.[] | select(.assets != null) | select([.assets[].name] | index($a))][0].assets[]? | select(.name == $n) | .browser_download_url' 2>/dev/null | head -1
	}

	stage=$(pick_from "honk-core-${core}-p1-x86_64.tar.gz" generated-stage.mk)
	if [ -z "$stage" ] || [ "$stage" = "null" ]; then
		echo "honk: no p1 core in kwrum1/dpd-fw, falling back to plain core" >&2
		stage=$(pick_from "honk-core-${core}-x86_64.tar.gz" generated-stage.mk)
	fi
	if [ -n "$stage" ] && [ "$stage" != "null" ]; then
		base="${stage%/*}/"
		if curl -fsSL -o ./package/honk/generated-stage.mk "$stage"; then
			sed -i "s|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=${base}|" ./package/honk/generated-stage.mk
			echo "honk: stage assets <- ${base}"
		fi
		prov=$(pick_from generated-provenance.json generated-provenance.json)
		[ -n "$prov" ] && [ "$prov" != "null" ] && curl -fsSL -o ./package/honk/generated-provenance.json "$prov" 2>/dev/null || true
		doona=$(pick_from generated-doona-stage.mk generated-doona-stage.mk)
		if [ -n "$doona" ] && [ "$doona" != "null" ] && [ -d ./package/luci-app-honk ]; then
			if curl -fsSL -o ./package/luci-app-honk/generated-doona-stage.mk "$doona"; then
				sed -i "s|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=${doona%/*}/|" ./package/luci-app-honk/generated-doona-stage.mk
			fi
		fi
	fi
}

case "$WRT_CONFIG" in
X86|ROCKCHIP) fetch_honk_stage ;;
esac

UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd sing-box luci-app-homeproxy luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"

UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"

UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"

UPDATE_PACKAGE "natmapt" "muink/openwrt-natmapt" "master"
UPDATE_PACKAGE "stuntman" "muink/openwrt-stuntman" "master"
UPDATE_PACKAGE "luci-app-natmapt" "muink/luci-app-natmapt" "master"

UPDATE_PACKAGE "airpi3000m-fancontrol" "LianXia233/luci-app-airpi3000m-fancontrol" "main"
UPDATE_PACKAGE "chfs" "LianXia233/luci-app-chfs" "main"
UPDATE_PACKAGE "fm350" "LianXia233/luci-app-fm350" "main"
UPDATE_PACKAGE "h5000m-netmode" "LianXia233/luci-app-h5000m-netmode" "main"
UPDATE_PACKAGE "mt5700" "LianXia233/luci-app-mt5700" "main"
UPDATE_PACKAGE "mt5700m" "LianXia233/luci-app-mt5700m" "main"
UPDATE_PACKAGE "netmonitor" "LianXia233/luci-app-netmonitor" "main"
UPDATE_PACKAGE "qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./package/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

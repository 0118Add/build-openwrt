#!/bin/bash
clear

# 使用专属优化
#sed -i 's,-mcpu=generic,-march=armv8-a,g' include/target.mk

# 交换 LAN/WAN 口
sed -i 's,"eth1" "eth0","eth0" "eth1",g' target/linux/rockchip/armv8/base-files/etc/board.d/02_network
sed -i "s,'eth1' 'eth0','eth0' 'eth1',g" target/linux/rockchip/armv8/base-files/etc/board.d/02_network

# 修改默认网关
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate
# 修改主机名
#sed -i 's/OpenWrt/OpenWrt/g' package/base-files/files/bin/config_generate
# 更改固件版本信息
#sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION=''|g" package/base-files/files/etc/openwrt_release
#sed -i "s|DISTRIB_DESCRIPTION='.*'|DISTRIB_DESCRIPTION='OpenWrt %V'|g" package/base-files/files/etc/openwrt_release
# 修改 luci version.lua
sed -i '/luciversion/d' feeds/luci/modules/luci-lua-runtime/luasrc/version.lua
echo "luciversion = 'LuCI openwrt-25.12 branch'" >> feeds/luci/modules/luci-lua-runtime/luasrc/version.lua

# remove LRNG for 3328
rm -f target/linux/generic/hack-${KERNEL_VERSION}/696*

#Vermagic
latest_version="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | sed -n '/[2-9][5-9]/p' | sed -n 1p | sed 's/v//g' | sed 's/.tar.gz//g')"
wget https://downloads.openwrt.org/releases/${latest_version}/targets/rockchip/armv8/profiles.json
jq -r '.linux_kernel.vermagic' profiles.json >.vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# 预配置一些插件
cp -rf ../PATCH/files ./files

find ./ -name *.orig | xargs rm -f
find ./ -name *.rej | xargs rm -f

#exit 0

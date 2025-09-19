#!/bin/bash

# 打包Toolchain
if [[ $REBUILD_TOOLCHAIN = 'true' ]]; then
    echo -e "\e[1;33m开始打包toolchain目录\e[0m"
    cd $OPENWRT_PATH
    sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    [ -d ".ccache" ] && (ccache=".ccache"; ls -alh .ccache)
    du -h --max-depth=1 ./staging_dir
    du -h --max-depth=1 ./ --exclude=staging_dir
    tar -I zstdmt -cf $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst staging_dir/host* staging_dir/tool* $ccache
    ls -lh $GITHUB_WORKSPACE/output
    [ -e $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst ] || exit 1
    exit 0
fi

[ -d $GITHUB_WORKSPACE/output ] || mkdir $GITHUB_WORKSPACE/output

color() {
    case $1 in
        cr) echo -e "\e[1;31m$2\e[0m" ;;
        cg) echo -e "\e[1;32m$2\e[0m" ;;
        cy) echo -e "\e[1;33m$2\e[0m" ;;
        cb) echo -e "\e[1;34m$2\e[0m" ;;
        cp) echo -e "\e[1;35m$2\e[0m" ;;
        cc) echo -e "\e[1;36m$2\e[0m" ;;
    esac
}

status() {
    local check=$? end_time=$(date '+%H:%M:%S') total_time
    total_time="==> 用时 $[$(date +%s -d $end_time) - $(date +%s -d $begin_time)] 秒"
    [[ $total_time =~ [0-9]+ ]] || total_time=""
    if [[ $check = 0 ]]; then
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(color cy $1) [ $(color cg ✔) ] $(echo -e "\e[1m$total_time")
    else
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(color cy $1) [ $(color cr ✕) ] $(echo -e "\e[1m$total_time")
    fi
}

find_dir() {
    find $1 -maxdepth 3 -type d -name $2 -print -quit 2>/dev/null
}

print_info() {
    printf "%s %-40s %s %s %s\n" $1 $2 $3 $4 $5
    # read -r param1 param2 param3 param4 param5 <<< $1
    # printf "%s %-40s %s %s %s\n" $param1 $param2 $param3 $param4 $param5
}

# 添加整个源仓库(git clone)
git_clone() {
    local repo_url branch target_dir current_dir
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    if [[ -n "$@" ]]; then
        target_dir="$@"
    else
        target_dir="${repo_url##*/}"
    fi
    git clone -q $branch --depth=1 $repo_url $target_dir 2>/dev/null || {
        print_info $(color cr 拉取) $repo_url [ $(color cr ✕) ]
        return 0
    }
    rm -rf $target_dir/{.git*,README*.md,LICENSE}
    current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
    if ([[ -d $current_dir ]] && rm -rf $current_dir); then
        mv -f $target_dir ${current_dir%/*}
        print_info $(color cg 替换) $target_dir [ $(color cg ✔) ]
    else
        mv -f $target_dir $destination_dir
        print_info $(color cb 添加) $target_dir [ $(color cb ✔) ]
    fi
}

# 添加源仓库内的指定目录
clone_dir() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null || {
        print_info $(color cr 拉取) $repo_url [ $(color cr ✕) ]
        return 0
    }
    local target_dir source_dir current_dir
    for target_dir in "$@"; do
        source_dir=$(find_dir "$temp_dir" "$target_dir")
        [[ -d $source_dir ]] || \
        source_dir=$(find $temp_dir -maxdepth 4 -type d -name $target_dir -print -quit) && \
        [[ -d $source_dir ]] || {
            print_info $(color cr 查找) $target_dir [ $(color cr ✕) ]
            continue
        }
        current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
        if ([[ -d $current_dir ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            print_info $(color cg 替换) $target_dir [ $(color cg ✔) ]
        else
            mv -f $source_dir $destination_dir
            print_info $(color cb 添加) $target_dir [ $(color cb ✔) ]
        fi
    done
    rm -rf $temp_dir
}

# 添加源仓库内的所有目录
clone_all() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null || {
        print_info $(color cr 拉取) $repo_url [ $(color cr ✕) ]
        return 0
    }
    local target_dir source_dir current_dir
    for target_dir in $(ls -l $temp_dir/$@ | awk '/^d/ {print $NF}'); do
        source_dir=$(find_dir "$temp_dir" "$target_dir")
        current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
        if ([[ -d $current_dir ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            print_info $(color cg 替换) $target_dir [ $(color cg ✔) ]
        else
            mv -f $source_dir $destination_dir
            print_info $(color cb 添加) $target_dir [ $(color cb ✔) ]
        fi
    done
    rm -rf $temp_dir
}

# 设置编译源码与分支
REPO_URL="https://github.com/immortalwrt/immortalwrt"
echo "REPO_URL=$REPO_URL" >>$GITHUB_ENV
REPO_BRANCH="openwrt-24.10"
echo "REPO_BRANCH=$REPO_BRANCH" >>$GITHUB_ENV

# 开始拉取编译源码
begin_time=$(date '+%H:%M:%S')
[[ $REPO_BRANCH != "master" ]] && BRANCH="-b $REPO_BRANCH --single-branch"
cd /workdir
git clone -q $BRANCH $REPO_URL openwrt
status "拉取编译源码"
ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
[ -d openwrt ] && cd openwrt || exit
echo "OPENWRT_PATH=$PWD" >>$GITHUB_ENV

# 开始生成全局变量
begin_time=$(date '+%H:%M:%S')
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cp -f $GITHUB_WORKSPACE/$CONFIG_FILE .config
make defconfig 1>/dev/null 2>&1

# 源仓库与分支
SOURCE_REPO=$(basename $REPO_URL)
echo "SOURCE_REPO=$SOURCE_REPO" >>$GITHUB_ENV
echo "LITE_BRANCH=${REPO_BRANCH#*-}" >>$GITHUB_ENV

# 平台架构
TARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_BOARD/{print $2}' .config)
SUBTARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_SUBTARGET/{print $2}' .config)
DEVICE_TARGET=$TARGET_NAME-$SUBTARGET_NAME
echo "DEVICE_TARGET=$DEVICE_TARGET" >>$GITHUB_ENV

# 内核版本
KERNEL=$(grep -oP 'KERNEL_PATCHVER:=\K[^ ]+' target/linux/$TARGET_NAME/Makefile)
KERNEL_VERSION=$(awk -F '-' '/KERNEL/{print $2}' include/kernel-$KERNEL | awk '{print $1}')
echo "KERNEL_VERSION=$KERNEL_VERSION" >>$GITHUB_ENV

# Toolchain缓存文件名
TOOLS_HASH=$(git log --pretty=tformat:"%h" -n1 tools toolchain)
CACHE_NAME="$SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-cache-$TOOLS_HASH"
echo "CACHE_NAME=$CACHE_NAME" >>$GITHUB_ENV

# 源码更新信息
COMMIT_AUTHOR=$(git show -s --date=short --format="作者: %an")
echo "COMMIT_AUTHOR=$COMMIT_AUTHOR" >>$GITHUB_ENV
COMMIT_DATE=$(git show -s --date=short --format="时间: %ci")
echo "COMMIT_DATE=$COMMIT_DATE" >>$GITHUB_ENV
COMMIT_MESSAGE=$(git show -s --date=short --format="内容: %s")
echo "COMMIT_MESSAGE=$COMMIT_MESSAGE" >>$GITHUB_ENV
COMMIT_HASH=$(git show -s --date=short --format="hash: %H")
echo "COMMIT_HASH=$COMMIT_HASH" >>$GITHUB_ENV
status "生成全局变量"

# 下载并部署Toolchain
if [[ $TOOLCHAIN = 'true' ]]; then
    cache_xa=$(curl -sL api.github.com/repos/$GITHUB_REPOSITORY/releases | awk -F '"' '/download_url/{print $4}' | grep $CACHE_NAME)
    cache_xc=$(curl -sL api.github.com/repos/Jejz168/toolchain-cache/releases | awk -F '"' '/download_url/{print $4}' | grep $CACHE_NAME)
    if [[ $cache_xa || $cache_xc ]]; then
        begin_time=$(date '+%H:%M:%S')
        [ $cache_xa ] && wget -qc -t=3 $cache_xa || wget -qc -t=3 $cache_xc
        [ -e *.tzst ]; status "下载toolchain缓存文件"
        [ -e *.tzst ] && {
            begin_time=$(date '+%H:%M:%S')
            tar -I unzstd -xf *.tzst || tar -xf *.tzst
            [ $cache_xa ] || (cp *.tzst $GITHUB_WORKSPACE/output && echo "OUTPUT_RELEASE=true" >>$GITHUB_ENV)
            sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
            [ -d staging_dir ]; status "部署toolchain编译缓存"
        }
    else
        echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_ENV
    fi
else
    echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_ENV
fi

# 开始更新&安装插件
begin_time=$(date '+%H:%M:%S')
./scripts/feeds update -a 1>/dev/null 2>&1
./scripts/feeds install -a 1>/dev/null 2>&1
status "更新&安装插件"

# 创建插件保存目录
destination_dir="package/A"
[ -d $destination_dir ] || mkdir -p $destination_dir

color cy "添加&替换插件"

# 添加额外插件
#clone_dir openwrt-23.05 https://github.com/coolsnowwolf/luci luci-app-adguardhome
#git_clone https://github.com/immortalwrt/homeproxy luci-app-homeproxy
sed -i "s/ImmortalWrt/OpenWrt/g" feeds/luci/applications/luci-app-homeproxy/po/zh_Hans/homeproxy.po
sed -i "s/ImmortalWrt proxy/OpenWrt proxy/g" feeds/luci/applications/luci-app-homeproxy/htdocs/luci-static/resources/view/homeproxy/{client.js,server.js}
#clone_all https://github.com/nikkinikki-org/OpenWrt-nikki
clone_all https://github.com/nikkinikki-org/OpenWrt-momo
#clone_dir https://github.com/QiuSimons/luci-app-daed daed luci-app-daed

#clone_all https://github.com/sbwml/luci-app-alist
#clone_all https://github.com/sbwml/luci-app-mosdns
#git_clone https://github.com/sbwml/packages_lang_golang golang

# 科学上网插件
rm -rf feeds/luci/applications/luci-app-openclash
clone_dir dev https://github.com/vernesong/OpenClash luci-app-openclash

# partexp
git_clone https://github.com/sirpdboy/luci-app-partexp package/luci-app-partexp

# tailscale zerotier
#git clone https://github.com/Jaykwok2999/luci-app-tailscale  package/luci-app-tailscale
sed -i 's/vpn/services/g' feeds/luci/applications/luci-app-zerotier/root/usr/share/luci/menu.d/luci-app-zerotier.json

# unblockneteasemusic
sed -i 's/解除网易云音乐播放限制/音乐解锁/g' feeds/luci/applications/luci-app-unblockneteasemusic/root/usr/share/luci/menu.d/luci-app-unblockneteasemusic.json

# 开始加载个人设置
begin_time=$(date '+%H:%M:%S')

[ -e $GITHUB_WORKSPACE/files ] && mv $GITHUB_WORKSPACE/files files

# 设置固件rootfs大小
if [ $PART_SIZE ]; then
    sed -i '/ROOTFS_PARTSIZE/d' $GITHUB_WORKSPACE/$CONFIG_FILE
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE" >>$GITHUB_WORKSPACE/$CONFIG_FILE
fi

# 修改默认IP
[ $DEFAULT_IP ] && sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# 更改主机名
sed -i "s/hostname='.*'/hostname='ImmortalWrt'/g" package/base-files/files/bin/config_generate

# TTYD 免登录
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# 设置 root 用户密码为 password
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

# 更改 Argon 主题背景
#cp -f $GITHUB_WORKSPACE/images/bg1.jpg feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg

# 添加编译日期
#echo "DISTRIB_DATE='R$(date +%y.%-m.%-d)'" >>package/base-files/files/etc/openwrt_release

# 取消主题默认设置
# find $destination_dir/luci-theme-*/ -type f -name '*luci-theme-*' -print -exec sed -i '/set luci.main.mediaurlbase/d' {} \;

# 修改连接数
sed -i 's/net.netfilter.nf_conntrack_max=.*/net.netfilter.nf_conntrack_max=65535/g' package/kernel/linux/files/sysctl-nf-conntrack.conf
# 修正连接数
sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=165535' package/base-files/files/etc/sysctl.conf

# 更改 ttyd 顺序和名称
#sed -i '3a \		"order": 10,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
#sed -i 's/\"终端\"/\"TTYD 终端\"/g' feeds/luci/applications/luci-app-ttyd/po/zh_Hans/ttyd.po

# 调整Dockerman到服务菜单
sed -i 's/"admin",/"admin","services",/g' feeds/luci/applications/luci-app-dockerman/luasrc/controller/*.lua
sed -i 's/"admin/"admin\/services/g' feeds/luci/applications/luci-app-dockerman/luasrc/model/*.lua
sed -i 's/"admin/"admin\/services/g' feeds/luci/applications/luci-app-dockerman/luasrc/model/cbi/dockerman/*.lua
sed -i 's/"admin/"admin\/services/g' feeds/luci/applications/luci-app-dockerman/luasrc/view/dockerman/*.htm
sed -i 's/"admin/"admin\/services/g' feeds/luci/applications/luci-app-dockerman/luasrc/view/dockerman/cbi/*.htm

# 自定义默认配置
#sed -i '/exit 0$/d' package/emortal/default-settings/files/99-default-settings
#cat ${GITHUB_WORKSPACE}/immortalwrt/default-settings >> package/emortal/default-settings/files/99-default-settings
curl -fsSL https://raw.githubusercontent.com/0118Add/Openwrt-CI/main/patch/10_system.js > ./feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
curl -fsSL https://raw.githubusercontent.com/0118Add/X86-N1-Actions/main/general/25_storage.js > ./feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/25_storage.js
curl -fsSL https://raw.githubusercontent.com/0118Add/Openwrt-CI/main/immortalwrt/29_ports.js > ./feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/29_ports.js

# comment out the following line to restore the full description
#sed -i '/# timezone/i grep -q '\''/tmp/sysinfo/model'\'' /etc/rc.local || sudo sed -i '\''/exit 0/i [ "$(cat /sys\\/class\\/dmi\\/id\\/sys_vendor 2>\\/dev\\/null)" = "Default string" ] \&\& echo "x86_64" > \\/tmp\\/sysinfo\\/model'\'' /etc/rc.local\n' package/emortal/default-settings/files/99-default-settings
#sed -i '/# timezone/i sed -i "s/\\(DISTRIB_DESCRIPTION=\\).*/\\1'\''ImmortalWrt $(sed -n "s/DISTRIB_DESCRIPTION='\''ImmortalWrt \\([^ ]*\\) .*/\\1/p" /etc/openwrt_release)'\'',/" /etc/openwrt_release\nsource /etc/openwrt_release \&\& sed -i -e "s/distversion\\s=\\s\\".*\\"/distversion = \\"$DISTRIB_ID $DISTRIB_RELEASE ($DISTRIB_REVISION)\\"/g" -e '\''s/distname    = .*$/distname    = ""/g'\'' /usr/lib/lua/luci/version.lua\nsed -i "s/luciname    = \\".*\\"/luciname    = \\"LuCI openwrt-24.10\\"/g" /usr/lib/lua/luci/version.lua\nsed -i "s/luciversion = \\".*\\"/luciversion = \\"\\"/g" /usr/lib/lua/luci/version.lua\necho "export const revision = '\''\'\'', branch = '\''LuCI openwrt-24.10'\'';" > /usr/share/ucode/luci/version.uc\n/etc/init.d/rpcd restart\n' package/emortal/default-settings/files/99-default-settings
#sed -i '/# timezone/i sed -i "s/\\(DISTRIB_DESCRIPTION=\\).*/\\1'\''ImmortalWrt $(sed -n "s/DISTRIB_DESCRIPTION='\''ImmortalWrt \\([^ ]*\\) .*/\\1/p" /etc/openwrt_release)'\'',/" /etc/openwrt_release\nsource /etc/openwrt_release \&\& sed -i -e "s/distversion\\s=\\s\\".*\\"/distversion = \\"$DISTRIB_ID $DISTRIB_RELEASE ($DISTRIB_REVISION)\\"/g" -e '\''s/distname    = .*$/distname    = ""/g'\'' /usr/lib/lua/luci/version.lua\nsed -i "s/luciname    = \\".*\\"/luciname    = \\"LuCI openwrt-24.10\\"/g" /usr/lib/lua/luci/version.lua\nsed -i "s/luciversion = \\".*\\"/luciversion = \\"v'$(date +%Y%m%d)'\\"/g" /usr/lib/lua/luci/version.lua\necho "export const revision = '\''v'$(date +%Y%m%d)'\'\'', branch = '\''LuCI openwrt-24.10'\'';" > /usr/share/ucode/luci/version.uc\n/etc/init.d/rpcd restart\n' package/emortal/default-settings/files/99-default-settings
curl -fsSL https://raw.githubusercontent.com/0118Add/Openwrt-CI/main/patch/release > package/base-files/files/etc/os-release

#sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile

# 修复 Makefile 路径
find $destination_dir/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i \
    -e 's?\.\./\.\./luci.mk?$(TOPDIR)/feeds/luci/luci.mk?' \
    -e 's?include \.\./\.\./\(lang\|devel\)?include $(TOPDIR)/feeds/packages/\1?' {}

# 转换插件语言翻译
for e in $(ls -d $destination_dir/luci-*/po feeds/luci/applications/luci-*/po); do
    if [[ -d $e/zh-cn && ! -d $e/zh_Hans ]]; then
        ln -s zh-cn $e/zh_Hans 2>/dev/null
    elif [[ -d $e/zh_Hans && ! -d $e/zh-cn ]]; then
        ln -s zh_Hans $e/zh-cn 2>/dev/null
    fi
done
status "加载个人设置"

# 开始下载openchash运行内核
#[[ $CLASH_KERNEL =~ amd64|arm64|armv7|armv6|armv5|386 ]] && {
#    begin_time=$(date '+%H:%M:%S')
#    chmod +x $GITHUB_WORKSPACE/scripts/preset-clash-core.sh
#    $GITHUB_WORKSPACE/scripts/preset-clash-core.sh $CLASH_KERNEL
#    status "下载openchash运行内核"
#}

# 开始下载zsh终端工具
[[ $ZSH_TOOL = 'true' ]] && {
    begin_time=$(date '+%H:%M:%S')
    chmod +x $GITHUB_WORKSPACE/scripts/preset-terminal-tools.sh
    $GITHUB_WORKSPACE/scripts/preset-terminal-tools.sh
    status "下载zsh终端工具"
}

# 开始下载adguardhome运行内核
#[[ $CLASH_KERNEL =~ amd64|arm64|armv7|armv6|armv5|386 ]] && {
#    begin_time=$(date '+%H:%M:%S')
#    chmod +x $GITHUB_WORKSPACE/scripts/preset-adguard-core.sh
#    $GITHUB_WORKSPACE/scripts/preset-adguard-core.sh $CLASH_KERNEL
#    status "下载adguardhome运行内核"
#}

# 开始更新配置文件
begin_time=$(date '+%H:%M:%S')
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cp -f $GITHUB_WORKSPACE/$CONFIG_FILE .config
make defconfig 1>/dev/null 2>&1
status "更新配置文件"

echo -e "$(color cy 当前编译机型) $(color cb $SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-$KERNEL_VERSION)"

# 更改固件文件名
# sed -i "s/\$(VERSION_DIST_SANITIZED)/$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION/" include/image.mk
# sed -i "/IMG_PREFIX:/ {s/=/=$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION-\$(shell date +%y.%m.%d)-/}" include/image.mk

color cp "脚本运行完成！"

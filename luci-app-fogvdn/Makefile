#
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/package.mk

LUCI_TITLE:=Fogvdn Luci App
LUCI_PKGARCH:=all
PKG_VERSION:=10
PKG_RELEASE:=$(AUTORELEASE)
PKG_NAME:=luci-app-fogvdn
LUCI_DEPENDS:=+fogvdn +jq
LUCI_SUBMENU_FORCED:=none
LUCI_SECTION:=services
LUCI_CATEGORY:=PCDN
LUCI_URL:=
LUCI_MAINTAINER:=

define Package/$(PKG_NAME)/preinst
#!/bin/sh
[ -f "/etc/config/fogvdn" ] && cp -v -f /etc/config/fogvdn /tmp/fogvdn.bak
[ -f "/etc/config/storagemanager" ] && cp -v -f /etc/config/storagemanager /tmp/storagemanager.bak
exit 0
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
if [ -f "/tmp/fogvdn.bak" ]; then
	cp -v -f /tmp/fogvdn.bak /etc/config/fogvdn
	rm -f /etc/config/fogvdn.default
else
	mv -f /etc/config/fogvdn.default /etc/config/fogvdn
fi
if [ -f "/tmp/storagemanager.bak" ];then
	cp -v -f /tmp/storagemanager.bak /etc/config/storagemanager
	rm -f /etc/config/storagemanager.default
else
	mv -f /etc/config/storagemanager.default /etc/config/storagemanager
fi
[ -n "$${IPKG_INSTROOT}" ] || {
	(. /etc/uci-defaults/30-run_post_update_cmd) && rm -f /etc/uci-defaults/30-run_post_update_cmd 
	(. /etc/uci-defaults/luci-fogvdn) && rm -f /etc/uci-defaults/luci-fogvdn
	exit 0
}
echo 1 > /tmp/fogvdn_enable_state
service fogvdn start 2>/dev/null
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
/etc/init.d/fogvdn stop
/etc/init.d/fogvdn disable
endef

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/conffiles
/etc/config/fogvdn
/etc/config/storagemanager
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

# $(call LuciTranslation,en,en)

# call BuildPackage - OpenWrt buildroot signature

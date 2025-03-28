#
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/package.mk

LLUCI_TITLE:=Fogvdn Luci App
LUCI_PKGARCH:=all
PKG_VERSION:=7
PKG_RELEASE:=$(AUTORELEASE)
LUCI_DEPENDS:=+fogvdn +jq
LUCI_SUBMENU_FORCED:=none
LUCI_SECTION:=services
LUCI_CATEGORY:=PCDN
LUCI_URL:=
LUCI_MAINTAINER:=

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/postinst
#!/bin/sh
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


# call BuildPackage - OpenWrt buildroot signature

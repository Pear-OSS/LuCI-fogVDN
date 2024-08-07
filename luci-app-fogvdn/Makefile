#
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/package.mk

LLUCI_TITLE:=Fogvdn Luci App
LUCI_PKGARCH:=all
PKG_VERSION:=5
PKG_RELEASE:=$(AUTORELEASE)
LUCI_DEPENDS:=+fogvdn +jq



include $(TOPDIR)/feeds/luci/luci.mk
define Package/$(LUCI_NAME)
	SECTION:=PCDN
	CATEGORY:=PCDN
	TITLE:=$(if $(LUCI_TITLE),$(LUCI_TITLE),LuCI $(LUCI_NAME) $(LUCI_TYPE))
	DEPENDS:=$(LUCI_DEPENDS)
	$(if $(LUCI_PKGARCH),PKGARCH:=$(LUCI_PKGARCH))
endef

$(eval $(call BuildPackage,$(LUCI_NAME)))

# call BuildPackage - OpenWrt buildroot signature

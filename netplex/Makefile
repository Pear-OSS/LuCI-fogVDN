include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:= netplex
PKG_RELEASE:=beta-1
PKG_VERSION:=0.9.1
PKG_SOURCE_URL:=git@github.com:Pear-OSS/pear-netplex.git
PKG_SOURCE_VERSION:=main
PKG_SOURCE_PROTO:=git

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk
define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=PearOS Netplex Daemon
endef


define Package/$(PKG_NAME)/description
	  PearOS Netplex Daemon
endef



define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/netplex.init $(1)/etc/init.d/netplex
	$(INSTALL_DIR) $(1)/usr/bin
	$(CP) $(PKG_BUILD_DIR)/netplex/netplex $(1)/usr/bin/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

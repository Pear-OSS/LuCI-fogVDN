include $(TOPDIR)/rules.mk

PKG_NAME:= netplex
PKG_RELEASE:=beta-1
PKG_VERSION:=0.9.1
# PKG_SOURCE_URL:=git@github.com:Pear-OSS/pear-netplex.git
# PKG_SOURCE_VERSION:=main
# PKG_SOURCE_PROTO:=git

include $(INCLUDE_DIR)/package.mk
define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=PearOS Netplex Daemon
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)/root
	$(PKG_UNPACK)

endef

define Package/$(PKG_NAME)/description
	  PearOS Netplex Daemon
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/usr/share/pcdn
	$(INSTALL_DIR) $(1)//etc/udhcpc.user.d
	$(INSTALL_DIR) $(1)//etc/odhcp6c.user.d
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/netplex.init $(1)/etc/init.d/netplex
	$(INSTALL_BIN) ./files/netplex.093.$(ARCH) $(1)/usr/bin/netplex
	$(INSTALL_BIN) ./files/netplex_update.init $(1)/etc/init.d/netplex_update
	$(INSTALL_BIN) ./files/01-pear-dhcpv4-script.dhcpscript $(1)/etc/udhcpc.user.d/01-pear-dhcpv4-script
	$(INSTALL_BIN) ./files/01-pear-dhcpv6-script.dhcpscript $(1)/etc/odhcp6c.user.d/01-pear-dhcpv6-script
	$(INSTALL_BIN) ./files/netplex_update $(1)/usr/share/pcdn/netplex_update
	$(INSTALL_BIN) ./files/01-pear-pppoe-update $(1)/etc/hotplug.d/iface/01-pear-pppoe-update
	$(INSTALL_BIN) ./files/99-add-ucitrack-to-network-and-multiwan $(1)/etc/uci-defaults/99-add-ucitrack-to-network-and-multiwan
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

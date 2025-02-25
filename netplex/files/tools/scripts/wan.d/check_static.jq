def is_ip4(str): str | test("\\A((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}\\z");
def is_ip6(str): str | test("\\A(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\\z");
def is_mac(str): str | test("\\A[0-9A-Fa-f][02468ACEace]:([0-9A-Fa-f]{2}:){4}[0-9A-Fa-f]{2}\\z");
if (has("ifname") | not) or (.ifname | tostring) == "" then error("no ifname") end
| if (has("nic") | not) or (.nic | tostring) == "" then error("no nic") end
| if (isempty(.default_on | tonumber?) | not) and (.default_on | tonumber) == 0 then
    . + {default_on: 0}
  else
    . + {default_on: 1}
  end
| if (isempty(.default_route | tonumber?) | not) and (.default_route | tonumber) == 0 then
    . + {default_route: 0}
  else
    . + {default_route: 1}
  end
| if (isempty(.vlan_enabled | tonumber?) | not) and (.vlan_enabled | tonumber) == 1 then
    if has("vlan_id") and (isempty(.vlan_id | tonumber?) | not) then
      . + {vlan_enabled: 1, vlan_id: (.vlan_id | tonumber)}
    else
      error("no valid vlan_id when vlan_enabled")
    end
  else
    . + {vlan_enabled: 0, vlan_id: 0}
  end
| if (isempty(.ipv4_enabled | tonumber?) | not) and (.ipv4_enabled | tonumber) == 1 then
    if is_ip4(.ipaddr | tostring) and is_ip4(.netmask | tostring) and is_ip4(.gateway | tostring) then
      . + {
        ipv4_enabled: 1,
        ipaddr, netmask, gateway
      }
    else
      error("IPv4 configuration error")
    end
  else
    . + {ipv4_enabled: 0, ipaddr: "", netmask: "", gateway: ""}
  end
| if (isempty(.dns_manual | tonumber?) | not) and (.dns_manual | tonumber) == 1 then
    if is_ip4(.dns1 | tostring) and ((.dns2 | tostring) == "" or is_ip4(.dns2 | tostring)) then
      . + {dns_manual: 1, dns1: (.dns1 | tostring), dns2: (.dns2 | tostring)}
    else
      error("dns_manual configuration error")
    end
  else
    . + {dns_manual: 0, dns1: "", dns2: ""}
  end
| if (isempty(.ipv6_enabled | tonumber?) | not) and (.ipv6_enabled | tonumber) == 1 then
    if is_ip6(.ip6addr | tostring) and is_ip6(.ip6gw | tostring) and (isempty(.prefix6 | tonumber?) | not) then
      . + {
        ipv6_enabled: 1,
        ip6addr, ip6gw, prefix6,
      }
    else
      error("IPv6 configuration error")
    end
  else
    . + {ipv6_enabled: 0, ip6addr: "", ip6gw: "", prefix6: 0}
  end
| if (isempty(.dns6_manual | tonumber?) | not) and (.dns6_manual | tonumber) == 1 then
    if is_ip6(.dns6_1 | tostring) and ((.dns6_2 | tostring) == "" or is_ip6(.dns6_2 | tostring)) then
      . + {dns6_manual: 1, dns6_1: (.dns6_1 | tostring), dns6_2: (.dns6_2 | tostring)}
    else
      error("dns6_manual configuration error")
    end
  else
    . + {dns6_manual: 0, dns6_1: "", dns6_2: ""}
  end
| if (isempty(.mac_manual | tonumber?) | not) and (.mac_manual | tonumber) == 1 then
    if is_mac(.mac | tostring) then
      . + {mac_manual: 1, mac: (.mac | tostring)}
    else
      error("mac_manual configuration error")
    end
  else
    . + {mac_manual: 0, mac: ""}
  end
| {
    (.ifname | tostring): {
      type: "static",
      nic: (.nic | tostring),
      default_on, default_route,
      vlan_enabled, vlan_id,
      ipv4_enabled, ipaddr, netmask, gateway,
      dns_manual, dns1, dns2,
      ipv6_enabled, ip6addr, ip6gw, prefix6,
      dns6_manual, dns6_1, dns6_2,
      mac_manual, mac
    }
}

def is_ip4(str): str | test("\\A((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}\\z");
def is_mac(str): str | test("\\A[0-9A-Fa-f][02468ACEace]:([0-9A-Fa-f]{2}:){4}[0-9A-Fa-f]{2}\\z");
if (has("ifname") | not) or (.ifname | tostring) == "" then error("no ifname") end
| if (has("nic") | not) or (.nic | tostring) == "" then error("no nic") end
| if (has("username") | not) or (.username | tostring) == "" then error("no username") end
| if (has("password") | not) or (.password | tostring) == "" then error("no password") end
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
| if (isempty(.dns_manual | tonumber?) | not) and (.dns_manual | tonumber) == 1 then
    if is_ip4(.dns1 | tostring) and ((.dns2 | tostring) == "" or is_ip4(.dns2 | tostring)) then
      . + {dns_manual: 1, dns1: (.dns1 | tostring), dns2: (.dns2 | tostring)}
    else
      error("dns_manual configuration error")
    end
  else
    . + {dns_manual: 0, dns1: "", dns2: ""}
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
| if (isempty(.pppoe_manual | tonumber?) | not) and (.pppoe_manual | tonumber) == 1 then
    . + {pppoe_manual: 1}
    | if has("pppoe_mtu") and (isempty(.vlan_id | tonumber?) | not) then
        . + {pppoe_mtu: (.pppoe_mtu | tonumber)}
      else
        . + {pppoe_mtu: 1492}
      end
    | if has("pppoe_redial_delay") and (isempty(.pppoe_redial_delay | tonumber?) | not) then
        . + {pppoe_redial_delay: (.pppoe_redial_delay | tonumber)}
      else
        . + {pppoe_redial_delay: 60}
      end
  else
    . + {pppoe_manual: 0, pppoe_mtu: 1492, pppoe_redial_delay: 60}
  end
| {
    (.ifname | tostring): {
      type: "pppoe",
      nic: (.nic | tostring),
      default_on, default_route,
      username, password,
      vlan_enabled, vlan_id,
      dns_manual, dns1, dns2,
      mac_manual, mac,
      pppoe_manual, pppoe_mtu, pppoe_redial_delay
    }
}

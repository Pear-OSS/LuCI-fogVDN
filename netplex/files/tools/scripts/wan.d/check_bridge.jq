def is_ip4(str): str | test("\\A((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}\\z");
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
      type: "bridge",
      nic: (.nic | tostring),
      default_on, default_route,
      vlan_enabled, vlan_id,
      mac_manual, mac
    }
}

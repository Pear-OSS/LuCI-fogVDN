local sys = require "luci.sys"
local json = require "luci.jsonc"

m = Map("storagemanager", translate("Storage Manager"), translate("Manage storage devices on your OpenWrt system."))

s = m:section(TypedSection, "manager", translate("Settings"))
s.anonymous = true
s.description = translate("Storage Settings")

cmd="/usr/share/pcdn/check_mount_point unmounted_info"
json_dump=luci.sys.exec(cmd)

devices = {}
if json_dump ~= nil then
    local unmount_point = json.parse(json_dump)
    if unmount_point and unmount_point.unmounted_info and #unmount_point.unmounted_info ~= 0 then
        device = s:option(DynamicList, "device", translate("Select Storage"))
        for _, dev_info in ipairs(unmount_point.unmounted_info) do
            local dev_entry = {
                path = dev_info.path,
                type = dev_info.type or "unknown",
                size = dev_info.size
            }
            table.insert(devices, dev_entry)
            
            local display_text = string.format("%s (%s) [%s]",
                dev_info.path,
                dev_info.size or "N/A",
                dev_info.type or "Unknown"
            )
            device:value(dev_info.path, display_text)
        end
    end
end

if devices and #devices == 0 then
    s:option(DummyValue, "no_device", " ", translate("No mountable storage space available at the moment."))
else
    btn = s:option(Button, "submitbtn", translate(" "))
    btn.inputtitle = translate("Format & Mount")

    function btn.write(self, section)

        -- 防止重复执行
        if self.executed then return end
        self.executed = true
    
        local selected = self.map:get(section, "device")
    
        if (not selected or #selected == 0) then
            m.message = translate("Please select at least one device.")
            return
        end
    
        local results = {}
    
        for _, selected_path in ipairs(selected) do
            local selected_dev = nil
            if devices and #devices > 0 then
                for _, dev in ipairs(devices) do
                    if dev.path == selected_path then
                        selected_dev = dev
                        break
                    end
                end
            end

            if not selected_dev then
                table.insert(results, string.format(translate("Device %s not found"), selected_path))
            else
                local cmd = string.format(
                    "/usr/share/pcdn/format_mount %s %s %s",
                    "format_mount",
                    selected_dev.path,
                    selected_dev.type
                )
                local result = sys.exec(cmd)
            
                if result and #result > 0 then
                    table.insert(results, string.format(translate("%s: %s"), selected_dev.path, result))
                else
                    table.insert(results, string.format(translate("%s: Command execution failed"), selected_dev.path))
                end
            end
    
        end
    
        m.message = table.concat(results, "<br>")

        self.map:set(section, "device", "")
    
        luci.http.redirect(luci.dispatcher.build_url("admin/services/storage_manager"))
        return
    end
end

return m
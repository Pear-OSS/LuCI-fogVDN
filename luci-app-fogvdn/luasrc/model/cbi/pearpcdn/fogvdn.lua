uci = require "luci.model.uci".cursor()
local fs = require "nixio.fs"
local json = require "luci.jsonc"
m = Map("fogvdn", translate("FOGVDN Node"))
s = m:section(NamedSection, "main", "main", translate("Main"))


act_status = s:option(DummyValue, "act_status", translate("Status"))
act_status.template = "pcdn/act_status"

enabled = s:option(Flag, "enable", translate("Enable"))
enabled.default = 0

node_info_file = "/etc/pear/pear_monitor/node_info.json"
if fs.access(node_info_file) then
    local node_info = fs.readfile(node_info_file)
    node_info = json.parse(node_info)
    for k,v in pairs(node_info) do
        option = s:option(DummyValue, "_"..k,translate(k))
        option.value = v
    end
end

openfog_link=s:option(DummyValue, "openfog_link", translate("<input type=\"button\" class=\"cbi-button cbi-button-apply\" value=\"Openfogos.com\" onclick=\"window.open('https://openfogos.com/')\" />"))
openfog_link.description = translate("OpenFogOS Official Website")

s = m:section(TypedSection, "instance", translate("Settings"))
s.anonymous = true
s.description = translate("Fogvdn Settings")



username = s:option(Value, "username", translate("username"))
username.description = translate("<input type=\"button\" class=\"cbi-button cbi-button-apply\" value=\"Register\" onclick=\"window.open('https://account.openfogos.com/signup?source%3Dopenfogos.com%26')\" />")

region = s:option(Value, "region", translate("Region"))
region.optional = true
region.template="cbi/city"


isp = s:option(Value, "isp", translate("ISP"))
isp.optional = true
isp:value("电信",  translate("China Telecom"))
isp:value("移动",  translate("China Mobile"))
isp:value("联通",  translate("China Unicom"))

per_line_up_bw = s:option(Value, "per_line_up_bw", translate("Per Line Up BW"))
per_line_up_bw.template = "cbi/digitonlyvalue"
per_line_up_bw.datatype = "uinteger"

per_line_down_bw = s:option(Value, "per_line_down_bw", translate("Per Line Down BW"))
per_line_down_bw.template = "cbi/digitonlyvalue"
per_line_down_bw.datatype = "uinteger"

limited_memory = s:option(Value, "limited_memory", translate("Limited Memory"))
limited_memory.optional = true
limited_memory.template = "cbi/digitonlyvalue"
limited_memory.datatype = "range(0, 100)"
-- 0-100%
limited_storage = s:option(Value, "limited_storage", translate("Limited Storage"))
limited_storage.optional = true
limited_storage.template = "cbi/digitonlyvalue"
limited_storage.datatype = "range(0, 100)"
-- 0-100%

limited_area = s:option(Value, "limited_area", translate("Limited Area"))
limited_area.default = "1"
limited_area:value("-1", "不设置")
limited_area:value("0", "全国调度")
limited_area:value("1", "省份调度")
limited_area:value("2", "大区调度")
-- 限制地区 -1 不设置（采用openfogos默认） 0 全国调度，1 省份调度，2 大区调度

nics = s:option(DynamicList,"nics",translate("netdev"))
uci:foreach("multiwan","multiwan",function (instance)
    nics:value(instance["tag"])
end
)

storage = s:option(DynamicList, "storage", translate("Storage"))
storage.default = "/opt/openfogos"
storage.description = translate("Warnning: System directory is not allowed!")
--filter start with /etc /usr /root /var /tmp /dev /proc /sys /overlay /rom and root
mount_point = {}
cmd="/usr/share/pcdn/check_mount_ponit mount_point"
json_dump=luci.sys.exec(cmd)
mount_point=json.parse(json_dump)
for k,v in pairs(mount_point) do
    storage:value(k,k.."("..v..")")
end

return m

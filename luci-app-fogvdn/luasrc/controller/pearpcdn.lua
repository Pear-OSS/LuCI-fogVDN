module("luci.controller.pearpcdn", package.seeall)
fs = require "nixio.fs"
I18N = require "luci.i18n"
translate = I18N.translate
json = require "luci.jsonc"
function index()
	-- entry({"admin", "services"}, firstchild(), _("OpenFog"), 60).dependent = true
	entry({"admin", "services","openfog"}, cbi("pearpcdn/fogvdn"),_("OpenFog"),60).dependent = true
    entry({"admin", "services","openfog", "get_act_status"}, call("get_act_status"),nil).leaf = true
end

function get_act_status()
    data = {}
    data["status"] = "0"
    
    --pid file
    pid_file="/run/pear_restart.pid"
    --if not exist, return 0
    if  fs.access(pid_file) then
        --if dir /proc/pid exist, return 1 
        --trim \n
        pid = fs.readfile(pid_file)
        pid = string.gsub(pid, "\n", "")
        if fs.access("/proc/"..pid) then
            data["status"] = "1"
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(data)
end

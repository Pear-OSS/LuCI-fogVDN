module("luci.controller.storagemanager", package.seeall)

function index()
    entry({"admin", "services", "storage_manager"}, cbi("storagemanager", {autoapply=true, hideapplybtn=true, hidesavebtn=true, hideresetbtn = true}), translate("Storage Manager"), 50).dependent = false
end

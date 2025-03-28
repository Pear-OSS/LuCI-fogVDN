module("luci.controller.storagemanager", package.seeall)

function index()
    entry({"admin", "pcdn", "storage_manager"}, cbi("storagemanager", {autoapply=true, hideapplybtn=true, hidesavebtn=true, hideresetbtn = true}), translate("Storage Manager"), 50).dependent = false
end

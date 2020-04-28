--[[
    @file: EnerTalk.lua (EnerTalk.fqa)
    @author: SuSu Daddy (inganyoyo@me.com)
    @created date: 2020.04.20.
    적용방법
    1. EnerTalk 가입
    - https://developer.enertalk.com/my-apps/
    2. Client Id, Client Secret 발급 및 Redirect URL 설정
    - Redirect URL: http://localhost
    3. code 발급
    - https://auth.enertalk.com/authorization?client_id={Client Id}&response_type=code&redirect_uri=http://localhost
    - 주소창에 위의 주소입력 후 EnerTalk 개발센터 로그인 후 리다이렉트된 code값 복사 http://localhost?code=XXXX
    - code값은 XXXX
    4. QuickApp 생성 및 변수 저장
    - QuickApp생성 후 등록된 변수 중 CLIENT_ID, CLIENT SECRET, CODE 값입력
]]
if dofile then
  dofile("fibaroapiHC3.lua")
  local cr = loadfile("credentials.lua")
  if cr then
    cr()
  end
  require("mobdebug").coro()
end 
_APP = {version = "v0.1", name = "EnerTalk", logLevel = "debug"}

APP2DEV = {EnerTalkMultilevelSensor = {}, EnerTalkEnergyMeter = {}}

APP2DEV = {
  EnerTalkMultilevelSensor = {yDay = {kNm = "전일사용요금"}, toDay = {kNm = "오늘사용요금"}, past = {kNm = "누적사용요금"}, future = {kNm = "예상사용요금"}},
  EnerTalkEnergyMeter = {real = {kNm = "실시간사용량"}, yDay = {kNm = "전일사용량"}, toDay = {kNm = "오늘사용량"}, past = {kNm = "누적사용량"}, future = {kNm = "예상사용량"}}
}


DEV2APP = {}
unitMap = { EnerTalkMultilevelSensor = { real = "₩", yDay = "₩", toDay = "₩", past = "₩", future = "₩"},
  EnerTalkEnergyMeter = { real = "mW", yDay = "kWh", toDay = "kWh", past = "kWh", future = "kWh"}
}
enerTalkKey = {code = "", clientSecret = "", clientId = "", siteId = "", accessToken = "", refreshToken = ""}
enerTalkEndPoint = {authorizeEndPoint = "https://auth.enertalk.com/token", apiEndPoint = "https://api2.enertalk.com/sites/"}

interval_time = {["interval_today"] = "600", ["interval_real"] = "600", ["interval_accrue"] = "600", ["interval_estimate"] = "600" }
interval_key = {["interval_today"] = {}, ["interval_real"] = {}, ["interval_accrue"] = {}, ["interval_estimate"] = {} }

errs = 0

local function newEnerTalk()
  local self = {}
  function post(ev, t) return setTimeout(function() events(ev) end, t or 0) end

  function httpCall( url, header, requestBody, requestType, referer, success, error)
    net.HTTPClient():request(url , { 
        options={
          headers = header or {},
          data = json.encode(requestBody or {}),
          method = requestType 
        },
        success = function(resp)
          local data = json.decode(resp.data)
          if resp.status == 200 then
            errs = 0
            quickSelf:updateProperty("log", os.date("%m-%d %X"))
            post({type = success, value = resp})
          elseif resp.status == 401 and data.type == "UnauthorizedError" then
            post({type = "callRefreshToken", value = resp, referer = referer})
          end
        end,
        error = function(resp)
          Logger(LOG.error,"%s:", json.encode(resp))
          post({type = error, value = resp})
        end
      })
  end

  function events(e)
    ({
        ["successFuture"] = function(e)
          local data = json.decode(e.value.data)
          APP2DEV["EnerTalkMultilevelSensor"]["future"].device:setValue(data.bill.charge)
          APP2DEV["EnerTalkEnergyMeter"]["future"].device:setValue(data.usage)
          interval_key['interval_estimate'] = post({type = "callFuture"}, tonumber(interval_time['interval_estimate']) * 1000) 
        end,
        ["callFuture"] = function(e)
          local url = string.format("%s%s%s",enerTalkEndPoint.apiEndPoint, enerTalkKey.siteId, "/usages/billing?timeType=pastToFuture")
          local header = { ["Authorization"] = "Bearer " .. enerTalkKey.accessToken }
          httpCall(url, header, nil, "GET", "callFuture", "successFuture","error")
        end,
        ["successPast"] = function(e)
          local data = json.decode(e.value.data) 
          APP2DEV["EnerTalkMultilevelSensor"]["past"].device:setValue(data.bill.charge)
          APP2DEV["EnerTalkEnergyMeter"]["past"].device:setValue(data.usage) 
          interval_key['interval_accrue'] = post({type = "callPast"}, tonumber(interval_time['interval_accrue']) * 1000) 
        end,
        ["callPast"] = function(e)
          local url = string.format("%s%s%s",enerTalkEndPoint.apiEndPoint, enerTalkKey.siteId, "/usages/billing?period=day")
          local header = { ["Authorization"] = "Bearer " .. enerTalkKey.accessToken }
          httpCall(url, header, nil, "GET", "callPast", "successPast","error")
        end,
        ["successCallYestDayToDay"] = function(e)
          local yDate = split(os.date("%Y-%m-%d",os.time()-24*60*60),"-")
          local yTimestamp = dateTotimestamp(yDate[1],yDate[2],yDate[3]) * 1000
          local tDate = split(os.date("%Y-%m-%d",os.time()),"-")
          local tTimestamp = dateTotimestamp(tDate[1],tDate[2],tDate[3]) * 1000
          local data = json.decode(e.value.data)
          for index,value in ipairs(data.items) do 
            if tonumber(value.timestamp) == tonumber(yTimestamp) then
              APP2DEV["EnerTalkMultilevelSensor"]["yDay"].device:setValue(value.bill.charge)
              APP2DEV["EnerTalkEnergyMeter"]["yDay"].device:setValue(value.usage)
            elseif tonumber(value.timestamp) == tonumber(tTimestamp) then
              APP2DEV["EnerTalkMultilevelSensor"]["toDay"].device:setValue(value.bill.charge)
              APP2DEV["EnerTalkEnergyMeter"]["toDay"].device:setValue(value.usage)
            end
          end
          local data = json.decode(e.value.data)
          interval_key['interval_today'] = post({type = "callYestDayToDay"}, tonumber(interval_time['interval_today']) * 1000) 
        end,
        ["callYestDayToDay"] = function(e)
          local yDate = split(os.date("%Y-%m-%d",os.time()-24*60*60),"-")
          local yTimestamp = dateTotimestamp(yDate[1],yDate[2],yDate[3]) * 1000
          local url = string.format("%s%s%s%s",enerTalkEndPoint.apiEndPoint, enerTalkKey.siteId, "/usages/billing?period=day&start=",yTimestamp)
          local header = { ["Authorization"] = "Bearer " .. enerTalkKey.accessToken }
          httpCall(url, header, nil, "GET", "callYestDayToDay", "successCallYestDayToDay","error")
        end,
        ["successReal"] = function(e)
          local data = json.decode(e.value.data)
          APP2DEV["EnerTalkEnergyMeter"]["real"].device:setValue(data.billingActivePower)
          interval_key['interval_real'] = post({type = "callReal"}, tonumber(interval_time['interval_real']) * 1000) 
        end,
        ["callReal"] = function(e)
          local url = string.format("%s%s%s",enerTalkEndPoint.apiEndPoint, enerTalkKey.siteId, "/usages/realtime")
          local header = { ["Authorization"] = "Bearer " .. enerTalkKey.accessToken }
          httpCall(url, header, nil, "GET", "callReal", "successReal","error")
        end,
        ["successCallRefreshToken"] = function(e)
          local data = json.decode(e.value.data)
          enerTalkKey.accessToken = data.access_token
          enerTalkKey.refreshToken = data.refresh_token
          quickSelf:setVariable("accessToken", data.access_token)
          quickSelf:setVariable("refreshToken", data.refresh_token)
          post({type = e.referer})
        end,
        ["callRefreshToken"] = function(e)
          local url = enerTalkEndPoint.authorizeEndPoint
          local header = { 
            ["Authorization"] = string.format("Basic %s:%s", enerTalkKey.clientId, enerTalkKey.clientSecret),
            ["Content-Type"] = "application/json" 
          }
          local requestBody ={grant_type = "refresh_token", refresh_token = enerTalkKey.refreshToken}
          httpCall(url, header, requestBody, "POST", "callRefreshToken", "successCallRefreshToken", "error")
        end,
        ["successCallAccessToken"] = function(e) 
          local data = json.decode(e.value.data)
          enerTalkKey.accessToken = data.access_token
          enerTalkKey.refreshToken = data.refresh_token
          quickSelf:setVariable("accessToken", data.access_token)
          quickSelf:setVariable("refreshToken", data.refresh_token)
          Logger(LOG.debug,"new accessToken: %s", enerTalkKey.accessToken)
          Logger(LOG.debug,"new refreshToken: %s", enerTalkKey.refreshToken)
          post({type = "callSiteId"})
        end,
        ["callAccessToken"] = function(e)
          local url = enerTalkEndPoint.authorizeEndPoint
          local header = { ["Content-Type"] = "application/json" }
          local requestBody = {client_id = enerTalkKey.clientId, client_secret = enerTalkKey.clientSecret, grant_type = 'authorization_code', code = enerTalkKey.code}
          httpCall(url, header, requestBody, "POST", "callAccessToken", "successCallAccessToken", "error")
        end,
        ["successCallSiteId"] = function(e)
          data = json.decode(e.value.data)
          enerTalkKey.siteId = data[1].id
          quickSelf:setVariable("siteId", data[1].id)
          Logger(LOG.debug,"new siteId: %s", enerTalkKey.siteId)
        end,
        ["callSiteId"] = function(e)
          local url = enerTalkEndPoint.apiEndPoint
          local header = { ["Authorization"] = "Bearer " .. enerTalkKey.accessToken }
          httpCall(url, header, nil, "GET", "callSiteId", "successCallSiteId", "error")
        end,
        ["error"] = function(e)
          Logger(LOG.error, "ERROR: %s", json.encode(e))
          quickSelf:updateProperty("log", json.encode(e))
          errs = errs + 1
          if errs > 3 then
            self:turnOff()
          end
        end
        })[e.type](e)
  end

  function self.init()
    for key, value in pairs(interval_time) do
      if quickSelf:getVariable(key) == "" or quickSelf:getVariable(key)  == nil then 
        quickSelf:setVariable(key, value) 
      end
      interval_time[key] = quickSelf:getVariable(key)
    end

    for key,value in pairs(enerTalkKey) do
      if quickSelf:getVariable(key) == "" or quickSelf:getVariable(key)  == nil then 
        quickSelf:setVariable(key,"-") 
      end
      enerTalkKey[key] = quickSelf:getVariable(key)
    end

    if enerTalkKey.code == "-" or enerTalkKey.clientSecret == "-" or enerTalkKey.clientId  == "-" then
      Logger(LOG.error,"please check code, clientSecret, clientId ")
      return false
    else
      if enerTalkKey.accessToken == "-" then
        post({type = "callAccessToken"})
      end
      return true
    end
  end

  function self.start()
    Logger(LOG.debug, "---- START EnerTalk ----")
    post({type = "callPast"})
    post({type = "callYestDayToDay"})
    post({type = "callReal"})
    post({type = "callFuture"})
  end
  function self.stop()
    Logger(LOG.debug, "---- STOP EnerTalk ----")
    for key, value in pairs(interval_key) do
      if interval_key[key] then 
        clearTimeout(interval_key[key])
      end
    end
  end

  return self
end


function QuickApp:installChildDevice()
  self:initChildDevices(
    {
      ["com.fibaro.multilevelSensor"] = EnerTalkMultilevelSensor,
      ["com.fibaro.energyMeter"] = EnerTalkEnergyMeter
    }
  )
  local isSaveLogs = self.properties.saveLogs
  self.childDevices = self.childDevices or {}
  --set APP2DEV, DEV2APP
  for lclass, devices in pairs(APP2DEV) do
    print(lclass) 
  end
  Logger(LOG.sys, "---- set APP2DEV, DEV2APP ----")
  local cdevs = api.get("/devices?parentId=" .. plugin.mainDeviceId) or {}
  for _, cd in ipairs(cdevs) do
    local lClass, name = cd.properties.userDescription:match("([%w]+):(%w+)")
    if APP2DEV[lClass][name] ~= nil then
      APP2DEV[lClass][name].deviceId = cd.id
      APP2DEV[lClass][name].device = self.childDevices[cd.id]
      DEV2APP[cd.id] = {type = lClass, name = name}
    end
  end
  Logger(LOG.sys, "-----------------------")

  Logger(LOG.sys, "---- create device ----")
  for lClass, devices in pairs(APP2DEV) do
    for name, device in pairs(devices) do
      if APP2DEV[lClass][name].deviceId == nil then
        Logger(LOG.debug, "created device - %s", device.kNm)
        APP2DEV[lClass][name].device = createChild[lClass](lClass, name, device.kNm)
        APP2DEV[lClass][name].deviceId = APP2DEV[lClass][name].device.id
      end
        DEV2APP[APP2DEV[lClass][name].deviceId] = {type = lClass, name = name}
        APP2DEV[lClass][name].device.properties.saveLogs = isSaveLogs
    end
  end
  Logger(LOG.sys, "-----------------------")
  
  Logger(LOG.sys, "---- remove device ----")
  local cdevs = api.get("/devices?parentId=" .. plugin.mainDeviceId) or {}
  for _, cd in ipairs(cdevs) do
    local lClass, name = cd.properties.userDescription:match("([%w]+):(%w+)")
    if APP2DEV[lClass][name] == nil then
      plugin.deleteDevice(cd.id)
      Logger(LOG.sys, "removed device - %s", name)
    end
  end
  Logger(LOG.sys, "-----------------------")

  Logger(LOG.sys, "---- child device ----")
  for lClass, devices in pairs(APP2DEV) do
    for name, dev in pairs(devices) do 
      Logger(LOG.sys, "[%s] Class: %s, DeviceId: %s, Device Name: %s", name, lClass, dev.deviceId, APP2DEV[lClass][name].kNm)
    end
  end
  Logger(LOG.sys, "-----------------------")
end

--[[ 
  Children 
]]
class "EnerTalkMultilevelSensor"(QuickAppChild)
class "EnerTalkEnergyMeter"(QuickAppChild)

createChild = {
  ["EnerTalkMultilevelSensor"] = function(tp, nm, kNm)
    return quickSelf:createChildDevice(
      {
        name = string.format("%s_%s", _APP.name, kNm),
        type = "com.fibaro.multilevelSensor",
        initialProperties = {
          userDescription = string.format("%s:%s", tp, nm),
          unit = unitMap[tp][nm] or ""
        }
      },
      AwairTemperature
    )
  end,
  ["EnerTalkEnergyMeter"] = function(tp, nm, kNm)
    return quickSelf:createChildDevice(
      {
        name = string.format("%s_%s", _APP.name, kNm),
        type = "com.fibaro.energyMeter",
        initialProperties = {
          userDescription = string.format("%s:%s", tp, nm),
          unit = unitMap[tp][nm] or ""
        }
      },
      EnerTalkEnergyMeter
    )
  end
}

--[[
  function of children
]]
function EnerTalkMultilevelSensor:__init(device)
  QuickAppChild.__init(self, device)
end
function EnerTalkMultilevelSensor:setValue(value)
  self:updateProperty("value", value )
  value = round(tonumber(value),0)
  self:updateProperty("log", tostring(value) .. self.properties.unit)
end

function EnerTalkEnergyMeter:__init(device)
  QuickAppChild.__init(self, device)
end
function EnerTalkEnergyMeter:setValue(value) 
  if self.properties.unit == "mW" then
    value = round(tonumber(value) * 0.001,1)
  else 
    value = round(tonumber(value) * 0.000001,1)
  end
  self:updateProperty("log", tostring(value) .. self.properties.unit)
  self:updateProperty("energy", value) 
end

function QuickApp:onInit()
  Utilities(self)
  quickSelf = self
  Logger(LOG.sys,"---- version: %s name: %s ----", _APP.version, _APP.name)
  self:installChildDevice()
  oEnerTalk = newEnerTalk()
  
  if oEnerTalk.init() then 
    self:turnOn() 
  end
end


function QuickApp:turnOn()
  self:updateProperty("value", true)
  oEnerTalk.start()
end
function QuickApp:turnOff()
  oEnerTalk.stop()
  self:updateProperty("value", false)
end

--[[
  Utilities 
]]
function Utilities()
  logLevel = {trace = 1, debug = 2, warning = 3,  error = 4}
  LOG = {debug = "debug", warning = "warning", trace = "trace", error = "error", sys = "sys"}
  function Logger(tp, ...)
    if tp == "debug" then
      if logLevel[_APP.logLevel] <= logLevel.debug then
        quickSelf:debug(string.format(...))
      end
    elseif tp == "warning" then
      if logLevel[_APP.logLevel] <= logLevel.warning then
        quickSelf:warning(string.format(...))
      end
    elseif tp == "trace" then
      if logLevel[_APP.logLevel] <= logLevel.trace  then
        quickSelf:trace(string.format(...))
      end
    elseif tp == "error" then
      if logLevel[_APP.logLevel] <= logLevel.error  then
        quickSelf:error(string.format(...))
      end
    elseif tp == "sys" then
      quickSelf:debug("[SYS]" .. string.format(...))   
    end
  end
  local oldtostring,oldformat = tostring,string.format -- redefine format and tostring
  tostring = function(o)
    if type(o)=='table' then
      if o.__tostring and type(o.__tostring)=='function' then return o.__tostring(o)
      else return json.encode(o) end
    else return oldtostring(o) end
  end  
  string.format = function(...) -- New format that uses our tostring
    local args = {...}
    for i=1,#args do if type(args[i])=='table' then args[i]=tostring(args[i]) end end
    return #args > 1 and oldformat(table.unpack(args)) or args[1]
  end
  format = string.format

  function split(s, sep)
    local fields = {}
    sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(
      s,
      pattern,
      function(c)
        fields[#fields + 1] = c
      end
    )
    return fields
  end
  function round(number, precision)
    local fmtStr = string.format('%%0.%sf',precision)
    number = string.format(fmtStr,number)
    return number
  end
  function dateTotimestamp(yyyy,mm,dd)
    local dt = {year=yyyy, month=mm, day=dd, hour=0, min=0, sec=0}
    return os.time(dt)
  end
  function timestampToDate(ts)
    return os.date('%Y-%m-%d', ts)
  end   
  function b64enc( data )
    -- character table string 
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ( (data:gsub( '.', function( x ) 
            local r,b='', x:byte()
            for i=8,1,-1 do r=r .. ( b % 2 ^ i - b % 2 ^ ( i - 1 ) > 0 and '1' or '0' ) end
            return r;
          end ) ..'0000' ):gsub( '%d%d%d?%d?%d?%d?', function( x )
          if ( #x < 6 ) then return '' end
          local c = 0
          for i = 1, 6 do c = c + ( x:sub( i, i ) == '1' and 2 ^ ( 6 - i ) or 0 ) end
          return b:sub( c+1, c+1 )
        end) .. ( { '', '==', '=' } )[ #data %3 + 1] )
  end  
end

if dofile then
  hc3_emulator.colorDebug = false
  hc3_emulator.offline = true
  hc3_emulator.start {
    id = 461,
    name = "EnerTalk", -- Name of QA
    type = "com.fibaro.binarySwitch",
    proxy = true,
    poll = 2000 -- Poll HC3 for triggers every 2000ms
  }
end
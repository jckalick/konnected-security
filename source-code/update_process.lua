local function getHeaderValue(line, headerPattern)
  local l1 = string.match(line, headerPattern .. ": (.*)")
  if l1 then 
    local l2 = string.sub(l1, 1, ( string.find(l1, "\r\n") - 1 ))
    return l2
  else
    return nil
  end
end

print("Heap: ", node.heap(), "Updater: Processing manifest")
dofile("manifest")
tmr.create():alarm(200, tmr.ALARM_AUTO, function(t)
  t:stop()
  if manifest[1] then
    local fw = file.open(manifest[1].filenm .. ".tmp", "w")
    local conn = net.createConnection(net.TCP, 1)
    conn:connect(443, manifest[1].host)
    conn:on("receive", function(sck, c)  fw:write(c) end)
    conn:on("disconnection", function(sck)
      fw:close()
      sck:close()
      collectgarbage()
      
      local redirect = false
      local fr = file.open(manifest[1].filenm .. ".tmp", "r+")
      local fr_line = ""
      while true do
        fr_line = fr:readline()
        if fr_line == nil then
          break
        end
        if string.find(fr_line, "Status: 302 Found") then
          redirect = true
        end
        if redirect then
          if string.match(fr_line, "Location: (.*)") then  
            fr:seek("set", (fr:seek("cur") - #fr_line))
            fr_line = fr:read(1024)
            local host, port, path = findAttr(getHeaderValue(fr_line, "Location"))
            table.insert(manifest, { host = host, port = port, path = path, filenm = manifest[1].filenm })
            print("Heap: ", node.heap(), "Updater: File redirection", manifest[1].filenm, "\r\nhttps:\/\/".. host .. path)
            break
          end
        end
      end
      fr:close()
      fr_line = nil
      collectgarbage()
      
      if redirect == false then
        print("Heap: ", node.heap(), "Updater: Downloaded", manifest[1].filenm)
        
        local fr_body_pos = 0
        local fr_line = ""
        local fr_len = 0
        fr = file.open(manifest[1].filenm .. ".tmp", "r+")
        print("Heap: ", node.heap(), "Updater: Processing file", manifest[1].filenm)
        while true do
          local fr_line = fr:readline()
          if fr_line == nil then
            break
          end
          
          fr_len = getHeaderValue(fr_line, "Content%-Length") 
          if fr_len then
            fr_body_pos = fr:seek("end") - string.format( "%d", fr_len )
            break
          end
        end
        fr_len = nil
        fr_line = nil
        collectgarbage()
        
        local fr_line = ""
        local fw = file.open(manifest[1].filenm .. ".bak.tmp", "w")
        if fr_body_pos > 0 then
          print("Heap: ", node.heap(), "Updater: Finalizing file", manifest[1].filenm)
          while fr:seek("set", fr_body_pos) do
            fr_body_pos = fr_body_pos + 512
            fr_line = fr:read(512)
            fw:write(fr_line)
          end
        end
        fr_line = nil
        fr_body_pos = nil
        fr:close()
        fw:close()
        collectgarbage()
        
        file.rename(manifest[1].filenm .. ".bak.tmp", manifest[1].filenm)
      end
      
      table.remove(manifest, 1)
      local fw = file.open("manifest", "w")
      fw.writeline("manifest = { ")
      for i, dl in pairs(manifest) do
        fw.write(table.concat({"{ host = \"",dl.host,"\", port = \"",dl.port,"\", path = \"", dl.path, "\", filenm = \"",dl.filenm,"\" }"}))
        if i < #manifest then
          fw.writeline(",")
        end
      end
      fw.writeline("}")
      fw.close()
      collectgarbage()
      
      t:start()
    end)
    conn:on("connection", function(sck)
      sck:send("GET " .. manifest[1].path .. " HTTP/1.1\r\nHost: ".. manifest[1].host .."\r\nConnection: keep-alive\r\n"..
               "Accept: */*\r\nUser-Agent: ESP8266\r\n\r\n")
    end)
  else
    t:unregister()
    local fw = file.open("var_update.lua", "w")
    fw:writeline("update = { run = false, force = false, setFactory = false }")
    fw:close()
    if file.exists("manifest") then 
      file.remove("manifest")
    end
    if file.exists("device") then
      file.rename("device", "var_device.lua")
    end
    print("Heap: ", node.heap(), "Updater: Done restarting in 3 seconds")
    tmr.create():alarm(3000, tmr.ALARM_SINGLE, function(t) node.restart() end)
  end
end)




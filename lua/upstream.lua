--[[实现对upstream的操作，并写入配置文件，upstream与上层应用对应]]

ngx.req.read_body()
local data_json = ngx.req.get_body_data()
local upstream_name = ngx.var.src_name .. "." .. http_suffix_url


-- request {}
-- response {"protocol": "none", "items": ["up1", "up2"]}
local function GET()
    local lines = utils.exec(string.format("ls %s 2>/dev/null|grep -e '.conf$'|xargs -I CC basename CC .%s.conf", dynamic_upstreams_dir, http_suffix_url))
    local items = utils.split(lines, "\n")

    local result = {}
    result.protocol = "none"
    result.items = items

    ngx.status = HTTP_OK
    ngx.print(cjsonf.encode(result))

end

-- request {"name": "5000.grb5060d.vzrd9po6", "servers": [{"addr":"127.0.0.1:8088", "weight": 5}, {"addr":"127.0.0.1:8089", "weight": 5}]}
-- response {"status": 205, "message": "success"}
local function UPDATE()
    local data_table = cjsonf.decode(data_json)

    -- 参数验证
    if data_table == nil then
        ngx.log(ngx.ERR, string.format("Illegal parameter body: %s", data_json))
        ngx.status = HTTP_NOT_ALLOWED
        ngx.print(string.format("Illegal parameter body: %s", data_json))
        return
    end

    data_table.name = upstream_name

    -- 将server列表拼接为单行形式："server 127.0.0.1:8089;server 127.0.0.1:8088;"
    local servers_line = ""
    for _, item in pairs(data_table.servers) do
        servers_line =  string.format("%sserver %s;", servers_line, item.addr)
    end

    -- 通过dyups插件更新内存中的upstream
    local status, r = dyups.update(upstream_name, servers_line);

    -- 更新持久层
    local err = dao.upstream_save(data_table)

    local result = {}

    -- 合并日志信息
    if err ~= nil then
        result.message = string.format("%s; %s", r, err)
    end

    -- 处理结果
    result.message = r
    if status == ngx.HTTP_OK and err == nil then
        result.status = HTTP_OK
    else
        ngx.log(ngx.ERR, result.message)
        result.status = status
        -- 回退
        dao.upstream_delete(upstream_name)
    end

    -- 返回结果
    ngx.status = result.status
    ngx.print(cjsonf.encode(result))

end

local function POST()
    UPDATE()
end

-- request {}
-- response {"status": 205, "message": "success"}
local function DELETE()
    -- 创建或更新指定upstream
    local status, r = dyups.delete(upstream_name)

    -- 处理结果
    local result = {}
    result.message = r
    if status == ngx.HTTP_OK or status == 404 then
        result.status = HTTP_OK
    else
        ngx.log(ngx.ERR, result.message)
        result.status = status
    end

    -- 返回结果
    ngx.status = result.status
    ngx.print(cjsonf.encode(result))

    -- 更新持久层
    dao.upstream_delete(upstream_name)
end



-- 处理请求
local function main()
    local method = ngx.req.get_method()
    ngx.log(ngx.INFO, method, " /v1/upstreams/", upstream_name, " ", data_json)

    if method == post then
        POST()
    elseif method == del then
        DELETE()
    elseif method == update then
        UPDATE()
    elseif method == get then
        GET()
    else
        ngx.status = ngx.HTTP_NOT_FOUND
    end
end

main()
-- Helper functions
function strSplit(delim,str)
    local t = {}

    for substr in string.gmatch(str, "[^".. delim.. "]*") do
        if substr ~= nil and string.len(substr) > 0 then
            table.insert(t,substr)
        end
    end

    return t
end

function Split(s, delimiter)
    result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

local mail = require "resty.mail"
local imap4 = require 'resty.imap4'
local pop3 = require "pop3"
local shell = require("resty.shell")

-- Read body being passed
-- Required for ngx.req.get_body_data()
ngx.req.read_body();
-- Parser for sending JSON back to the client
local cjson = require("cjson")
-- Strip the api/ bit from the request path
local reqPath = ngx.var.uri:gsub("api/", "");
-- Get the request method (POST, GET etc..)
local reqMethod = ngx.var.request_method
-- Parse the body data as JSON
local body = ngx.req.get_body_data() ==
        -- This is like a ternary statement for Lua
        -- It is saying if doesn't exist at least
        -- define as empty object
        nil and {} or cjson.decode(ngx.req.get_body_data());



Api = {}
Api.__index = Api
-- Declare API not yet responded
Api.responded = false;
-- Function for checking input from client
function Api.endpoint(method, path, callback)
    -- If API not already responded
    if Api.responded == false then
        -- KeyData = params passed in path
        local keyData = {}
        -- If this endpoint has params
        if string.find(path, "<(.-)>")
        then
            -- Split origin and passed path sections
            local splitPath = strSplit("/", path)
            local splitReqPath = strSplit("/", reqPath)
            -- Iterate over splitPath
            for i, k in pairs(splitPath) do
                -- If chunk contains <something>
                if string.find(k, "<(.-)>")
                then
                    -- Add to keyData
                    keyData[string.match(k, "%<(%a+)%>")] = splitReqPath[i]
                    -- Replace matches with default for validation
                    reqPath = string.gsub(reqPath, splitReqPath[i], k)
                end
            end
        end

        -- return false if path doesn't match anything
        if reqPath ~= path
        then
            return false;
        end
        -- return error if method not allowed
        if reqMethod ~= method
        then
            return ngx.say(
                cjson.encode({
                    error=500,
                    message="Method " .. reqMethod .. " not allowed"
                })
            )
        end

        -- Make sure we don't run this again
        Api.responded = true;

        -- return body if all OK
        body.keyData = keyData
        return callback(body);
    end

    return false;
end

Api.endpoint('POST', '/mails/create',
        function(body)
            local emailname = body['emailname']
            local from = body['from']
            local to = body['to']
            local subject = body['subject']
            local text = body['text']
            local html = body['html']


            local mailer, err = mail.new({
                host = "localhost",
                port = 25,
                starttls = false,
                username = emailname,
                password = "123456",
            })
            if err then
                ngx.log(ngx.ERR, "mail.new error: ", err)
                return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end

            local ok, err = mailer:send({
                from = from,
                to = { to },
                subject = subject,
                text = text,
                html = html,
            })
            if err then
                ngx.log(ngx.ERR, "mailer:send error: ", err)
                return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end

            return ngx.say(
                    cjson.encode(
                            {id = 1}
                    )
            );

        end
)

Api.endpoint('GET', '/mails/getList',
        function(body)
            local emailname = ngx.unescape_uri(ngx.var.arg_emailname)

            local some_mail = {
                host     = os.getenv("LUA_MAIL_HOST") or 'localhost';
                username = os.getenv("LUA_MAIL_USER") or  emailname;
                password = os.getenv("LUA_MAIL_PASS") or '321456789';
            }

            local maillist = {}
            local mbox = pop3.new()

            mbox:open(some_mail.host, some_mail.port or '110')
            print('open   :', mbox:is_open())

            mbox:auth(some_mail.username, some_mail.password)
            print('auth   :', mbox:is_auth())
            num=1
            for k, msg in mbox:messages() do
                print(string.format("   *** MESSAGE NO %d ***", k))
                maillist[k] = {}
                maillist[k]["id"] = num
                maillist[k]["subject"] = msg:subject()
                maillist[k]["from"] = msg:from()
                --maillist[msg:id()]["fromAddr"] = msg:from_address()
                maillist[k]["to"] = msg:to()
                maillist[k]["date"] = msg:date()
                num = num + 1

            end


            return ngx.say(
                    cjson.encode(
                            maillist
                    )
            );
        end
)

Api.endpoint('POST', '/test',
    function(body)
        return ngx.say(
            cjson.encode(
                {
                    method=method,
                    path=path,
                    body=body['example'],
                }
            )
        );
    end
)

Api.endpoint('GET', '/test/<id>/<name>',
    function(body)
        return ngx.say(
            cjson.encode(
                {
                    method=method,
                    path=path,
                    body=body,
                }
            )
        );
    end
)

Api.endpoint('GET', '/mail/<inbox>/<status>',
    function(body)
        local emailname = body['emailname']
        local some_mail = {
            host     = os.getenv("LUA_MAIL_HOST") or 'localhost';
            username = os.getenv("LUA_MAIL_USER") or  emailname;
            password = os.getenv("LUA_MAIL_PASS") or '123456';
        }

        local maillist = {}
        local mbox = pop3.new()

        mbox:open(some_mail.host, some_mail.port or '110')
        print('open   :', mbox:is_open())

        mbox:auth(some_mail.username, some_mail.password)
        print('auth   :', mbox:is_auth())

        for k, msg in mbox:messages() do
            print(string.format("   *** MESSAGE NO %d ***", k))
            maillist[k] = {}
            maillist[k]["subject"] = msg:subject()
            maillist[k]["from"] = msg:from()
            --maillist[msg:id()]["fromAddr"] = msg:from_address()
            maillist[k]["to"] = msg:to()
            maillist[k]["date"] = msg:date()

        end

        
        return ngx.say(
            cjson.encode(
                    maillist
            )
        );
    end
)


Api.endpoint('GET', '/user/<userlist>/<status>',
        function(body)
            local stdin = "hello"
            local timeout = 10000  -- ms
            local max_size = 4096  -- byte

            local result = {}

            local cmdd = 'cat /proc/sys/kernel/random/uuid'
            local ok, stdout, stderr, reason, status = shell.run(cmdd, stdin, timeout, max_size)

            if ok then
                local res = string.gsub(stdout, "\n", ",")
                result = Split(res,",")
            end

            return ngx.say(
                cjson.encode(
                    result
                )
            );
        end
)

Api.endpoint('POST', '/createuser/<createuser>/<status>',
        function(body)
            local emailname = body['emailname']
            local stdin = "hello"
            local timeout = 10000  -- ms
            local max_size = 4096  -- byte

            local result = {}

            --local cmdd = 'cat /proc/sys/kernel/random/uuid'
            local ok, stdout, stderr, reason, status = shell.run(cmddaddu, stdin, timeout, max_size)

            if ok then
                result[1] = stdout
            end

            return ngx.say(
                    result
            );
        end
)




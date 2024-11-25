--[[
LogCurve tool for ETHOS X14
FlyDragon Mo
Release:
v0.1 2024-11-15, First version.
v0.2 2024-11-25, Added reading prompts.
]]

--Script information
local NAME         = "LogCurve"
local VERSION      = "0.2"
local DATE         = "2024-11-25"

local BACK_COLOR   = lcd.RGB(40, 40, 40)
local SELECT_COLOR = lcd.RGB(248, 176, 56)
local CURSOR_X_MAX = 464
local CURSOR_H_MAX = 266

local icon         = lcd.loadMask("curve.png")
local log_folders  = {}
local log_files    = {}
local log_data     = { {}, {} }
local maxmin_str   = {}
local curves_y     = { {}, {}, {}, {}, {} }
local rpm_zoom     = 10

local function list_control(xs, ys, w, str, back, ali)
    lcd.color(back)
    lcd.drawFilledRectangle(xs, ys, w, 33)
    if ali == CENTERED then
        xs = xs + w / 2
    else
        xs = xs + 5
    end
    lcd.font(FONT_S)
    lcd.color(COLOR_WHITE)
    lcd.drawText(xs, ys + 8, str, ali)
end

local function curve_ruler(xs, ys, w, h)
    lcd.color(BACK_COLOR)
    lcd.drawLine(xs, ys, xs, ys + h)
    lcd.drawLine(xs, ys + h, xs + w, ys + h)
end

local function curve_data(xs, zoom, array, x_pos, x_max, color)
    lcd.color(color)
    for index = math.max(1, x_pos - CURSOR_X_MAX / zoom - 1), x_max - 1 do
        lcd.drawLine(xs, array[index], xs + zoom, array[index + 1])
        xs = xs + zoom
        if xs > CURSOR_X_MAX + 2 then
            break
        end
    end
end

local function curve_cursor(xs, ys, h, zoom, array, pointer, step)
    local time = array[pointer][1]
    local minutes = math.floor((time % 3600) / 60)
    local seconds = time % 60
    local px = math.min(pointer - 1, CURSOR_X_MAX / zoom)
    local sx_b = xs + px * zoom + 5
    local sx_c = sx_b + 5
    local ali = LEFT
    --Cursor
    lcd.color(COLOR_WHITE)
    lcd.drawLine(sx_b - 5, ys, sx_b - 5, ys + h)
    if sx_b > 370 then
        sx_b = sx_b - 110
        sx_c = sx_c - 20
        ali = RIGHT
    end
    --Background
    lcd.color(COLOR_GREEN)
    lcd.drawFilledRectangle(sx_b, ys + 50, 100, 25)  --Voltage
    lcd.color(COLOR_RED)
    lcd.drawFilledRectangle(sx_b, ys + 80, 100, 25)  --Current
    lcd.color(COLOR_YELLOW)
    lcd.drawFilledRectangle(sx_b, ys + 110, 100, 25) --Headspeed
    lcd.color(COLOR_CYAN)
    lcd.drawFilledRectangle(sx_b, ys + 140, 100, 25) --ESC1 PWM
    lcd.color(COLOR_MAGENTA)
    lcd.drawFilledRectangle(sx_b, ys + 170, 100, 25) --ESC Temp
    lcd.color(BACK_COLOR)
    lcd.drawFilledRectangle(sx_b, ys + 240, 100, 25) --Time
    --Content
    lcd.font(FONT_S)
    lcd.color(COLOR_BLACK)
    lcd.drawText(sx_c, ys + 50 + 5, tostring(array[pointer][2]) .. 'V', ali)
    lcd.drawText(sx_c, ys + 80 + 5, tostring(array[pointer][4]) .. 'A', ali)
    lcd.drawText(sx_c, ys + 110 + 5, tostring(array[pointer][5]) .. "RPM", ali)
    lcd.drawText(sx_c, ys + 140 + 5, tostring(array[pointer][6]) .. '%', ali)
    lcd.drawText(sx_c, ys + 170 + 5, tostring(array[pointer][3]) .. '°C', ali)
    --Time
    lcd.color(COLOR_WHITE)
    --lcd.drawText(sx_c, ys + 200 + 5, tostring(pointer), ali)
    lcd.drawText(sx_c, ys + 240 + 5, string.format("%02d", minutes) .. ':' .. string.format("%02d", seconds) .. "  x" .. tostring(step), ali)
end

local function tele_control(xs, ys, w, str1, str2, color)
    lcd.font(FONT_S)
    --Tile
    lcd.color(color)
    lcd.drawFilledRectangle(xs, ys, w, 20)
    lcd.color(COLOR_BLACK)
    lcd.drawText(xs + 5, ys + 1, str1, LEFT)
    --Background
    lcd.color(BACK_COLOR)
    lcd.drawFilledRectangle(xs, ys + 20, w, 22)
    --Content
    lcd.color(COLOR_WHITE)
    lcd.drawText(xs + 5, ys + 23, "MAX:", LEFT)
    lcd.drawText(xs + 60, ys + 23, str2, LEFT)
end

local function tele2_control(xs, ys, w, str1, str2, str3, color)
    lcd.font(FONT_S)
    --Tile
    lcd.color(color)
    lcd.drawFilledRectangle(xs, ys, w, 20)
    lcd.color(COLOR_BLACK)
    lcd.drawText(xs + 5, ys + 1, str1, LEFT)
    --Background
    lcd.color(BACK_COLOR)
    lcd.drawFilledRectangle(xs, ys + 20, w, 41)
    --Content
    lcd.color(COLOR_WHITE)
    lcd.drawText(xs + 5, ys + 23, "MAX:", LEFT)
    lcd.drawText(xs + 60, ys + 23, str2, LEFT)
    lcd.drawText(xs + 5, ys + 41, "MIN:", LEFT)
    lcd.drawText(xs + 60, ys + 41, str3, LEFT)
end

local function read_log_file(path)
    local file_obj = io.open(path, "r")
    if not file_obj then
        return nil
    end
    local data = {}
    local skip_header = true
    local line = file_obj:read("*l")
    while line do
        if skip_header then
            skip_header = false
            line = file_obj:read("*l")
        else
            local row = {}
            for value in string.gmatch(line, "([^,]+)") do
                row[#row + 1] = tonumber(value)
            end
            data[#data + 1] = row
            line = file_obj:read("*l")
        end
    end
    file_obj:close()
    return data
end

local function create()
    local widget = {
        model_name       = model.name(),
        date             = os.date("%Y%m%d"),
        display_mode     = 0,
        log_file_path    = "/scripts/widget-flylog/logs/",
        model_file_path  = "/scripts/widget-flylog/logs/" .. model.name() .. '/',
        date_file_path   = "",
        folder_total     = 0,
        file_total       = 0,
        folder_pointer   = 0,
        file_pointer     = 0,
        folder_page      = 1,
        file_page        = 1,
        folder_page_max  = 1,
        file_page_max    = 1,
        read_data_flag   = false,
        cursor_x_pointer = 1,
        cursor_x_max     = 1,
        x_pointer_step   = 10,
        steps            = 1,
        x_zoom           = 2,
    }
    local folders = system.listFiles(widget.model_file_path)
    if folders ~= nil then
        if #folders > 2 then
            for _, folder in ipairs(folders) do
                if folder ~= "info" then
                    table.insert(log_folders, folder)
                end
            end
            widget.folder_total = #folders - 2
            widget.folder_pointer = 1
            widget.folder_page_max = math.floor((widget.folder_total - 1) / 28) + 1
        end
    end
    return widget
end

local function event(widget, category, value, x, y)
    if category == EVT_KEY then
        if value == KEY_ENTER_FIRST then
            if widget.display_mode == 0 and widget.folder_total > 0 then
                widget.file_total = 0
                widget.file_pointer = 0
                log_files = system.listFiles(widget.model_file_path .. log_folders[widget.folder_pointer + 1])
                if log_files ~= nil then
                    if #log_files > 1 then
                        widget.file_total = #log_files - 1
                        widget.file_pointer = 1
                        widget.file_page = 1
                        widget.file_page_max = math.floor((widget.file_total - 1) / 28) + 1
                        widget.date_file_path = widget.model_file_path .. log_folders[widget.folder_pointer + 1] .. '/'
                    end
                end
                widget.display_mode = 1
            elseif widget.display_mode == 1 and widget.file_total > 0 then
                widget.read_data_flag = true
            elseif widget.display_mode == 2 then
                if widget.x_pointer_step == 10 then
                    widget.x_pointer_step = 5
                elseif widget.x_pointer_step == 5 then
                    widget.x_pointer_step = 1
                else
                    widget.x_pointer_step = 10
                end
            end
        elseif value == KEY_MDL_FIRST then
            if widget.display_mode > 0 then
                widget.display_mode = widget.display_mode - 1
            end
        elseif value == KEY_DISP_FIRST then
            if widget.x_zoom < 4 then
                widget.x_zoom = widget.x_zoom + 2
            else
                widget.x_zoom = 2
            end
        elseif value == KEY_ROTARY_RIGHT then
            if widget.display_mode == 0 and widget.folder_total > 0 then
                if widget.folder_pointer < widget.folder_total then
                    widget.folder_pointer = widget.folder_pointer + 1
                else
                    widget.folder_pointer = 1
                end
                widget.folder_page = math.floor((widget.folder_pointer - 1) / 28) + 1
            elseif widget.display_mode == 1 and widget.file_total > 0 then
                if widget.file_pointer < widget.file_total then
                    widget.file_pointer = widget.file_pointer + 1
                else
                    widget.file_pointer = 1
                end
                widget.file_page = math.floor((widget.file_pointer - 1) / 28) + 1
            elseif widget.display_mode == 2 then
                if widget.cursor_x_pointer < widget.cursor_x_max then
                    widget.cursor_x_pointer = widget.cursor_x_pointer + widget.x_pointer_step
                end
                if widget.cursor_x_pointer > widget.cursor_x_max then
                    widget.cursor_x_pointer = widget.cursor_x_max
                end
            end
        elseif value == KEY_ROTARY_LEFT then
            if widget.display_mode == 0 and widget.folder_total > 0 then
                if widget.folder_pointer > 1 then
                    widget.folder_pointer = widget.folder_pointer - 1
                else
                    widget.folder_pointer = widget.folder_total
                end
                widget.folder_page = math.floor((widget.folder_pointer - 1) / 28) + 1
            elseif widget.display_mode == 1 and widget.file_total > 0 then
                if widget.file_pointer > 1 then
                    widget.file_pointer = widget.file_pointer - 1
                else
                    widget.file_pointer = widget.file_total
                end
                widget.file_page = math.floor((widget.file_pointer - 1) / 28) + 1
            elseif widget.display_mode == 2 then
                if widget.cursor_x_pointer > 1 then
                    widget.cursor_x_pointer = widget.cursor_x_pointer - widget.x_pointer_step
                end
                if widget.cursor_x_pointer < 1 then
                    widget.cursor_x_pointer = 1
                end
            end
        elseif value == KEY_PAGE_FIRST then
            if widget.display_mode == 0 and widget.folder_total > 0 then
                if widget.folder_page < widget.folder_page_max then
                    widget.folder_page = widget.folder_page + 1
                    widget.folder_pointer = (widget.folder_page - 1) * 28 + 1
                else
                    widget.folder_page = 1
                    widget.folder_pointer = 1
                end
            elseif widget.display_mode == 1 and widget.file_total > 0 then
                if widget.file_page < widget.file_page_max then
                    widget.file_page = widget.file_page + 1
                    widget.file_pointer = (widget.file_page - 1) * 28 + 1
                else
                    widget.file_page = 1
                    widget.file_pointer = 1
                end
            end
        end
        --Refresh the interface
        lcd.invalidate()
        system.killEvent(value)
        return true
    else
        return false
    end
end

local function wakeup(widget)
    if widget.display_mode == 0 then
    elseif widget.display_mode == 1 then
        if widget.read_data_flag then
            log_data = read_log_file(widget.date_file_path .. log_files[widget.file_pointer + 1])
            if log_data ~= nil then
                widget.cursor_x_pointer = 1
                widget.cursor_x_max = #log_data
                widget.steps = 1
                widget.display_mode = 2
            else
                widget.cursor_x_max = 0
            end
            widget.read_data_flag = false
        end
    elseif widget.display_mode == 2 then
        if widget.steps == 1 then
            local maxmin_data = {}
            maxmin_data[1] = 0
            maxmin_data[2] = 100
            maxmin_data[3] = 0
            maxmin_data[4] = 200
            maxmin_data[5] = 0
            maxmin_data[6] = 0
            maxmin_data[7] = 0
            maxmin_data[8] = log_data[widget.cursor_x_max][1]
            for s = 1, widget.cursor_x_max do
                --Voltage
                local value = log_data[s][2]
                if maxmin_data[1] < value then
                    maxmin_data[1] = value
                end
                if maxmin_data[2] > value then
                    maxmin_data[2] = value
                end
                --ESC Temp
                value = log_data[s][3]
                if maxmin_data[3] < value then
                    maxmin_data[3] = value
                end
                if maxmin_data[4] > value then
                    maxmin_data[4] = value
                end
                --Current
                value = log_data[s][4]
                if maxmin_data[5] < value then
                    maxmin_data[5] = value
                end
                --Headspeed
                value = log_data[s][5]
                if maxmin_data[6] < value then
                    maxmin_data[6] = value
                end
                --ESC1 PWM
                value = log_data[s][6]
                if maxmin_data[7] < value then
                    maxmin_data[7] = value
                end
            end
            rpm_zoom      = (maxmin_data[6] + 200) / CURSOR_H_MAX
            maxmin_str[1] = tostring(maxmin_data[1]) .. 'V'
            maxmin_str[2] = tostring(maxmin_data[2]) .. 'V'
            maxmin_str[3] = tostring(maxmin_data[3]) .. '°C'
            maxmin_str[4] = tostring(maxmin_data[4]) .. '°C'
            maxmin_str[5] = tostring(maxmin_data[5]) .. 'A'
            maxmin_str[6] = tostring(maxmin_data[6]) .. "RPM"
            maxmin_str[7] = tostring(maxmin_data[7]) .. '%'
            maxmin_str[8] = string.format("[%02d:%02d]", math.floor(maxmin_data[8] / 60), maxmin_data[8] % 60)
            widget.steps  = 2
        elseif widget.steps == 2 then
            for index, value in ipairs(log_data) do
                -- Voltage
                curves_y[1][index] = 311 - math.min(value[2] * 5, CURSOR_H_MAX)
                -- ESC Temp
                curves_y[2][index] = 311 - math.min(value[3] * 2, CURSOR_H_MAX)
                -- Current
                curves_y[3][index] = 311 - math.min(value[4], CURSOR_H_MAX)
                -- Headspeed
                curves_y[4][index] = 311 - math.min(math.floor(value[5] / rpm_zoom), CURSOR_H_MAX)
                -- ESC1 PWM
                curves_y[5][index] = 311 - math.min(value[6] * 2, CURSOR_H_MAX)
            end
            widget.steps = 0
            --Refresh the interface
            lcd.invalidate()
        end
    end
end

local function paint(widget)
    local w, h = lcd.getWindowSize() --X14: w=632 h=314 X20: w=784 h=406
    local sx, sy = 5, 45
    local l_w = (w - 10 - 15) / 4
    local t_w = l_w * 3 + 10
    local tile = 'v' .. VERSION .. " [" .. widget.model_name .. ']'
    local st
    local color

    --Mode
    if widget.display_mode == 0 then --Log folder
        list_control(5, 5, t_w, tile, BACK_COLOR, LEFT)
        list_control(5 + t_w + 5, 5, l_w, tostring(widget.folder_pointer) .. '/' .. tostring(widget.folder_total) .. " [" .. tostring(widget.folder_page) .. ']', BACK_COLOR, CENTERED)
        if widget.folder_total > 0 then
            st = (widget.folder_page - 1) * 28 + 1
            for s = st, widget.folder_total, 1 do
                color = BACK_COLOR
                if s == widget.folder_pointer then
                    color = SELECT_COLOR
                end
                list_control(sx, sy, l_w, '[' .. log_folders[s + 1] .. ']', color, CENTERED)
                sx = sx + l_w + 5
                if s % 4 == 0 then
                    sy = sy + 38
                    sx = 5
                end
                if s == st + 27 then
                    break
                end
            end
        end
    elseif widget.display_mode == 1 then --Log file
        list_control(5, 5, t_w, tile .. " / " .. log_folders[widget.folder_pointer + 1], BACK_COLOR, LEFT)
        list_control(5 + t_w + 5, 5, l_w, tostring(widget.file_pointer) .. '/' .. tostring(widget.file_total) .. " [" .. tostring(widget.file_page) .. ']', BACK_COLOR, CENTERED)
        if widget.read_data_flag then
            list_control(w / 2 - 80, h / 2, 160, "Reading log file...", BACK_COLOR, CENTERED)
        else
            if widget.file_total > 0 then
                st = (widget.file_page - 1) * 28 + 1
                for s = st, widget.file_total, 1 do
                    color = BACK_COLOR
                    if s == widget.file_pointer then
                        color = SELECT_COLOR
                    end
                    local file_str = log_files[s + 1]
                    list_control(sx, sy, l_w, file_str:sub(1, -5), color, CENTERED)
                    sx = sx + l_w + 5
                    if s % 4 == 0 then
                        sy = sy + 38
                        sx = 5
                    end
                    if s == st + 27 then
                        break
                    end
                end
            end
        end
    elseif widget.display_mode == 2 and widget.steps == 0 then --Curve display
        list_control(5, 5, t_w, tile .. " / " .. log_folders[widget.folder_pointer + 1] .. " / " .. log_files[widget.file_pointer + 1], BACK_COLOR, LEFT)
        list_control(5 + t_w + 5, 5, l_w, maxmin_str[8], BACK_COLOR, CENTERED)
        --Tele max min
        tele2_control(5 + t_w + 5, sy, l_w, "Voltage", maxmin_str[1], maxmin_str[2], COLOR_GREEN)      --h=61
        tele_control(5 + t_w + 5, sy + 66, l_w, "Current", maxmin_str[5], COLOR_RED)                   --h=42
        tele_control(5 + t_w + 5, sy + 113, l_w, "Headspeed", maxmin_str[6], COLOR_YELLOW)             --h=42
        tele_control(5 + t_w + 5, sy + 160, l_w, "Throttle", maxmin_str[7], COLOR_CYAN)                --h=42
        tele2_control(5 + t_w + 5, sy + 207, l_w, "Temp", maxmin_str[3], maxmin_str[4], COLOR_MAGENTA) --h=61
        --Curve ruler
        curve_ruler(5, sy, t_w, 267)
        --Curve data
        curve_data(5 + 1, widget.x_zoom, curves_y[1], widget.cursor_x_pointer, widget.cursor_x_max, COLOR_GREEN)
        curve_data(5 + 1, widget.x_zoom, curves_y[2], widget.cursor_x_pointer, widget.cursor_x_max, COLOR_MAGENTA)
        curve_data(5 + 1, widget.x_zoom, curves_y[3], widget.cursor_x_pointer, widget.cursor_x_max, COLOR_RED)
        curve_data(5 + 1, widget.x_zoom, curves_y[4], widget.cursor_x_pointer, widget.cursor_x_max, COLOR_YELLOW)
        curve_data(5 + 1, widget.x_zoom, curves_y[5], widget.cursor_x_pointer, widget.cursor_x_max, COLOR_CYAN)
        --Curve cursor
        curve_cursor(5 + 1, sy, CURSOR_H_MAX, widget.x_zoom, log_data, widget.cursor_x_pointer, widget.x_pointer_step)
    end
end

local function close(widget)

end

local function init()
    system.registerSystemTool({
        name = NAME,
        icon = icon,
        create = create,
        wakeup = wakeup,
        event = event,
        paint = paint,
        close = close,
        title = true
    })
end

return { init = init }

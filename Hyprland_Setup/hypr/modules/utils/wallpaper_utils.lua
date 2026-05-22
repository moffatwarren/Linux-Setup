local wallpaper_utils = {}
local home = os.getenv("HOME")
local wallpaper_dir = home .. "/Pictures/wallpapers"

function wallpaper_utils.set_random()
    -- Verify the directory exists
    local dir_check = io.popen(string.format('test -d "%s" && echo yes', wallpaper_dir))
    if not dir_check then
        os.execute(string.format('notify-send "Wallpaper Error" "Directory does not exist: %s"', wallpaper_dir))
        return
    end

    -- Find all images and pick one at random
    -- We escape the parentheses with \\ so Lua passes them to the shell correctly
    local find_cmd = string.format(
        'find "%s" -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \\) | shuf -n 1',
        wallpaper_dir
    )

    local handle = io.popen(find_cmd)

    if not handle then
        return
    end

    local random_pic = handle:read("*a"):gsub("%s+", "")
    handle:close()

    -- Check if we actually found an image
    if random_pic == "" then
        os.execute(string.format('notify-send "Wallpaper Error" "No images found in %s"', wallpaper_dir))
        return
    end

    -- Apply it with awww
    local awww_cmd = string.format(
        'awww img "%s" --transition-type grow --transition-pos 0.5,0.5 --transition-fps 60 --transition-duration 1',
        random_pic
    )
    os.execute(awww_cmd)

    -- Update hyprlock.conf
    local hyprlock_conf = home .. "/.config/hypr/hyprlock.conf"
    local sed_cmd = string.format(
        'sed -i "s|path = .*|path = %s|g" "%s"',
        random_pic,
        hyprlock_conf
    )
    os.execute(sed_cmd)
end

-- function wallpaper_utils.select()
--     local dir_check = io.popen(string.format('test -d "%s" && echo yes', wallpaper_dir))
--     if not dir_check then
--         os.execute('notify-send "Error" "Wallpaper directory not found: ' .. wallpaper_dir .. '"')
--         return
--     end

--     -- Create a temporary file to hold the Rofi input.
--     -- This avoids shell escaping nightmares with null bytes and special characters.
--     local tmp_file = os.tmpname()
--     local f = io.open(tmp_file, "w")

--     if not f then
--         return
--     end

--     -- Get files and build the Rofi list
--     local find_cmd = io.popen('find "' .. wallpaper_dir .. '" -maxdepth 1 -type f -printf "%f\n"')

--     if not find_cmd then
--         return
--     end

--     for file in find_cmd:lines() do
--         -- In Lua strings, \000 is the null byte (\0) and \031 is the unit separator (\x1f)
--         f:write(string.format("%s\000icon\031%s/%s\n", file, wallpaper_dir, file))
--     end
--     find_cmd:close()
--     f:close()

--     -- 5. Pipe the list into Rofi
--     -- Note the %% to escape the percent sign in string.format
--     local rofi_cmd = string.format([[rofi -dmenu -i -p "Choose Wallpaper:" ]] ..
--         [[-show-icons ]] ..
--         [[-theme-str 'window { width: 60%%; }' ]] ..
--         [[-theme-str 'listview { columns: 4; lines: 3; }' ]] ..
--         [[-theme-str 'element-icon { size: 8em; }' ]] ..
--         [[-theme-str 'element-text { horizontal-align: 0.5; }' ]] ..
--         [[-theme-str 'element { orientation: vertical; }' ]] ..
--         [[< "%s"]], tmp_file)

--     -- Run Rofi and read the selected output
--     local rofi = io.popen(rofi_cmd, "r")

--     if not rofi then
--         return
--     end

--     local selected = rofi:read("*l") -- Read the selected line
--     rofi:close()

--     -- Clean up the temporary file
--     os.remove(tmp_file)

--     -- 6. If you selected something, apply it
--     if selected and selected ~= "" then
--         local wallpaper_path = wallpaper_dir .. "/" .. selected

--         -- Apply with awww (Note: if this was a typo for swww, change it here)
--         local awww_cmd = string.format([[awww img "%s" --transition-type grow --transition-pos 0.5,0.5 --transition-duration 1 --transition-fps 60]], wallpaper_path)
--         os.execute(awww_cmd)

--         -- Update hyprlock.conf using sed
--         local sed_cmd = string.format([[sed -i "s|path = .*|path = %s|g" "%s/.config/hypr/hyprlock.conf"]], wallpaper_path, home)
--         os.execute(sed_cmd)
--     end
-- end

return wallpaper_utils
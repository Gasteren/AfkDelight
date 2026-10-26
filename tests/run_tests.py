"""Runs AfkDelight on a real Lua 5.1 VM (the language version World of Warcraft uses) against a strict WoW API mock.

Usage: python tests/run_tests.py   (GitHub Actions runs this before every CurseForge upload)
Needs: pip install lupa
Lint (optional): luacheck --config tests/.luacheckrc *.lua
mock.lua only accepts widget methods and events that exist in both the live 12.1.5 and the
forever 1.60.1 clients (api_widgets.lua / api_events_smf.lua were generated from Blizzard's
API documentation); tests.lua holds the retail, forever, settings-upgrade and saved-variable scenarios.
"""
import os
import sys

import lupa.lua51 as lupa

TOOLS = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(TOOLS)

DRIVER = r'''
local read, files, flavor, scenario = ...
local function chunk(source, name)
	local fn, err = loadstring(source, "@" .. name)
	if not fn then error(err, 0) end
	return fn
end
local widgets = chunk(read("tools", "api_widgets.lua"), "api_widgets.lua")()
local lists = chunk(read("tools", "api_events_smf.lua"), "api_events_smf.lua")()
local H = chunk(read("tools", "mock.lua"), "mock.lua")(widgets, lists, flavor)
local ns = {}
for i = 1, #files do
	local ok, err = xpcall(function() chunk(read("addon", files[i]), files[i])("AfkDelight", ns) end, debug.traceback)
	if not ok then return 1, "  LOAD ERROR in " .. files[i] .. "\n" .. tostring(err) end
end
local tests = chunk(read("tools", "tests.lua"), "tests.lua")
local ok, failures, report = xpcall(function() return tests(ns, H, scenario) end, debug.traceback)
if not ok then return 1, "  HARNESS ERROR\n" .. tostring(failures) end
return failures, report
'''


def read(kind, name):
    folder = TOOLS if kind == "tools" else ADDON
    with open(os.path.join(folder, name), encoding="utf-8") as handle:
        return handle.read()


def toc_files():
    files = []
    for line in read("addon", "AfkDelight.toc").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line)
    return files


def main():
    files = toc_files()
    print("TOC load order:", ", ".join(files))
    total_failures = 0
    for flavor, scenario in (("retail", "retail"), ("forever", "forever"), ("forever", "upgrade"), ("retail", "sanitize")):
        lua = lupa.LuaRuntime()
        driver = lua.execute("return function(...) " + DRIVER + " end")
        failures, report = driver(read, lua.table_from(files), flavor, scenario)
        failures = int(failures)
        total_failures += failures
        print(f"\n=== {scenario} ({flavor} client) - {'OK' if failures == 0 else str(failures) + ' FAILED'} ===")
        print(report)
    print("\nRESULT:", "ALL PASSED" if total_failures == 0 else f"{total_failures} FAILURE(S)")
    return 1 if total_failures else 0


if __name__ == "__main__":
    sys.exit(main())

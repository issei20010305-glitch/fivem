"""
projectin_rpg サーバーロジックのシミュレーションテスト
必要: Python 3 + `pip install lupa` (Lua 5.4 ランタイムを同梱)
実行: python3 tests/run_tests.py
FiveM本体・Qbox・ox_inventory・oxmysql はモックです。実サーバーでの動作確認の代わりにはなりません。
"""
import os
import sys
from lupa import lua54

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = [
    'tests/mock_fivem.lua', 'tests/mock_mysql.lua',
    'config.lua', 'shared/utils.lua', 'shared/items.lua', 'shared/schema.lua',
    'data/default_content.lua',
    'server/bridge.lua', 'server/db.lua', 'server/characters.lua', 'server/rpg_inventory.lua',
    'server/holding.lua', 'server/parties.lua', 'server/instances.lua', 'server/combat.lua',
    'server/events.lua', 'server/editor.lua', 'server/admin.lua', 'server/main.lua',
    'tests/scenario.lua',
]

lua = lua54.LuaRuntime(unpack_returned_tuples=True)
loader = lua.eval('function(src, name) local f, e = load(src, "@" .. name, "t"); if not f then error(e) end; return f() end')
result = 0
for f in FILES:
    with open(os.path.join(ROOT, f), encoding='utf-8') as fh:
        r = loader(fh.read(), f)
    if f == 'tests/scenario.lua':
        result = r
sys.exit(1 if result else 0)

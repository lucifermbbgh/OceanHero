import io
p='scripts/autoload/data_registry.gd'
t=io.open(p,encoding='utf-8').read()
if 'var modules: Dictionary' not in t:
    t=t.replace('var ammo: Dictionary = {}','var ammo: Dictionary = {}\nvar modules: Dictionary = {}')
    t=t.replace('\tammo = _load_dir("res://data/ammo")','\tammo = _load_dir("res://data/ammo")\n\tmodules = _load_dir("res://data/modules")')
    t=t.replace('print("[DataRegistry] ships=%d(基准 %d) gear=%d cannons=%d ammo=%d commodities=%d enemies=%d ports=%d buildings=%d maps=%d" % [','print("[DataRegistry] ships=%d(基准 %d) gear=%d cannons=%d ammo=%d commodities=%d enemies=%d ports=%d buildings=%d maps=%d modules=%d" % [')
    t=t.replace('\t\tcommodities.size(), ports.size(), buildings.size(), maps.size(),', '\t\tcommodities.size(), ports.size(), buildings.size(), maps.size(), modules.size(),')
    io.open(p,'w',encoding='utf-8').write(t)
    print('registry patched')
else:
    print('already patched')
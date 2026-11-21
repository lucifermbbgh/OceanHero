import io
p='scripts/base/base_scene.gd'
t=io.open(p,encoding='utf-8').read()
old='''\tvar owned_count := 0
\tfor k in DataRegistry.gear.keys():
\t\tvar g: Resource = DataRegistry.gear[k]
\t\tif g == null or String(g.slot) != filter_slot:
\t\t\tcontinue
\t\tif not GameState.slot_allows(filter_slot, String(g.id)):
\t\t\tcontinue
\t\t# 只列出已拥有的装备（未拥有需先去船厂购买）
\t\tif not GameState.has_gear(g.id):
\t\t\tcontinue'' '
new='''\tvar owned_count := 0
\tvar candidates: Array = []
\tfor k in DataRegistry.gear.keys():
\t\tvar g: Resource = DataRegistry.gear[k]
\t\tif g == null or String(g.slot) != filter_slot:
\t\t\tcontinue
\t\tif not GameState.slot_allows(filter_slot, String(g.id)):
\t\t\tcontinue
\t\tif not GameState.has_gear(g.id):
\t\t\tcontinue
\t\tcandidates.append(g)
\tfor g in _sorted_rar(candidates):
\t\tvar owned_count2 := 0'' '
if old in t:
    t=t.replace(old,new)
    t=t.replace('\t\towned_count += 1\n', '\t\towned_count += 1\n')
    io.open(p,'w',encoding='utf-8').write(t)
    print('gear options restructured')
else:
    print('pattern miss')
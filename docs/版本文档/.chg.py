import io
p='docs/版本文档/变更记录.md'
t=io.open(p,encoding='utf-8').read()
entry='''### 2026-11-20 取消需求模块并重排特性版本

| # | 决策 | 说明 |
|---|---|---|
| 1 | **取消 1.4 NPC 居民与真实需求** | 体量约 10 轮，经济已可玩，风险与收益不匹配 |
| 2 | 生态整合一并取消 | 依赖需求模块 |
| 3 | 重排 1.4~2.0 | 装备深化 → 世界地图 → 内容扩展 → 美术 → 平衡 → 回归 → 发布 |
| 4 | 1.3 遗留三项并入 1.4 | 攻击巡逻队、事件关税、sawmill 修复 |

'''
t=entry+t
io.open(p,'w',encoding='utf-8').write(t)
print('changelog updated')
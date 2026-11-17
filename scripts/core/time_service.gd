extends Node
## 游戏内时间轴（维多利亚式流动时间）。关闭游戏即停止，不做离线推进。

signal day_advanced(total_days: int)
signal week_advanced(week_index: int)

const DAYS_PER_WEEK := 7
const WEEKS_PER_MONTH := 4
const MONTHS_PER_YEAR := 12
const DAYS_PER_YEAR := DAYS_PER_WEEK * WEEKS_PER_MONTH * MONTHS_PER_YEAR  # 336

var speed := 1.0
var paused := false
var total_days := 0

var _accum := 0.0

func _ready() -> void:
	set_process(true)

func _real_sec_per_day() -> float:
	var v := 24.0
	if DataRegistry != null and DataRegistry.balance != null:
		v = float(DataRegistry.balance.get("real_sec_per_game_day"))
	return maxf(1.0, v)

func _process(delta: float) -> void:
	if paused:
		return
	_accum += delta * speed
	var per_day := _real_sec_per_day()
	while _accum >= per_day:
		_accum -= per_day
		total_days += 1
		day_advanced.emit(total_days)
		if total_days % DAYS_PER_WEEK == 0:
			week_advanced.emit(total_days / DAYS_PER_WEEK)

# ---------------- 日期查询 ----------------

## 从开局起的累计周数（投资升格计时用）
func total_weeks() -> int:
	return total_days / DAYS_PER_WEEK

func year() -> int:
	return total_days / DAYS_PER_YEAR + 1

func month() -> int:
	return (total_days / (DAYS_PER_WEEK * WEEKS_PER_MONTH)) % MONTHS_PER_YEAR + 1

func week_of_month() -> int:
	return (total_days / DAYS_PER_WEEK) % WEEKS_PER_MONTH + 1

func day_of_week() -> int:
	return total_days % DAYS_PER_WEEK + 1

func date_text() -> String:
	return "第 %d 年 · %d 月 · 第 %d 周" % [year(), month(), week_of_month()]

func speed_text() -> String:
	if paused:
		return "暂停"
	return "%d×" % int(speed)

func to_dict() -> Dictionary:
	return {"total_days": total_days, "speed": speed}

func from_dict(d: Dictionary) -> void:
	total_days = int(d.get("total_days", 0))
	speed = float(d.get("speed", 1.0))
	paused = false
	_accum = 0.0

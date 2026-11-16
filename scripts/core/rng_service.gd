extends Node
## 确定性随机源：所有玩法随机都必须走这里，保证测试可复现。

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0

func _ready() -> void:
	randomize()

func set_seed(s: int) -> void:
	seed_value = s
	_rng.seed = s

func randf() -> float:
	return _rng.randf()

func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]

func chance(p: float) -> bool:
	return _rng.randf() < p

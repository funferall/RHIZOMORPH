extends RefCounted
## Reusable command/animation state; combat integration can listen for impact.
signal bash_impact
const BASH_SECONDS := 1.10
const ROOT_SECONDS := 1.0
const UPROOT_SECONDS := 0.85
const CAPTURE_RADIUS := 3.0
const CAPTURE_DAMAGE_SCALE := 0.25
const SUNK_DEPTH := 0.85
const MOTION_MARGIN := 1.05

enum State { IDLE, WALK, BASH, ROOTING, BRACED, UPROOTING }
var state := State.IDLE
var brace := 0.0
var bash := -1.0
var walking := 0.0
var clock := 0.0
var _elapsed := 0.0
var _impact_sent := false
var _move_after_uproot := false

func attack() -> bool:
	if state not in [State.IDLE, State.WALK]:
		return false
	state = State.BASH
	_elapsed = 0.0
	_impact_sent = false
	bash = 0.0
	return true

func toggle_brace() -> void:
	if state in [State.ROOTING, State.BRACED]:
		state = State.UPROOTING
		_move_after_uproot = false
	elif state in [State.IDLE, State.WALK, State.UPROOTING]:
		state = State.ROOTING
		_move_after_uproot = false

func move() -> void:
	if state in [State.ROOTING, State.BRACED, State.UPROOTING]:
		state = State.UPROOTING
		_move_after_uproot = true
	elif state != State.BASH:
		state = State.WALK

func stop() -> void:
	if state == State.WALK:
		state = State.IDLE

func advance(delta: float) -> void:
	clock += delta
	if state == State.BASH:
		_elapsed += delta
		bash = minf(_elapsed / BASH_SECONDS, 1.0)
		if bash >= 0.43 and not _impact_sent:
			_impact_sent = true
			bash_impact.emit()
		if bash >= 1.0:
			state = State.IDLE
			bash = -1.0
	elif state == State.ROOTING:
		brace = move_toward(brace, 1.0, delta / ROOT_SECONDS)
		if brace >= 1.0:
			state = State.BRACED
	elif state == State.UPROOTING:
		brace = move_toward(brace, 0.0, delta / UPROOT_SECONDS)
		if brace <= 0.0:
			state = State.WALK if _move_after_uproot else State.IDLE
	walking = move_toward(walking, 1.0 if state == State.WALK else 0.0, delta * 3.0)

func capture_active() -> bool:
	return state == State.BRACED

func capture_damage(raw_damage: float, hostile := true) -> float:
	return raw_damage * CAPTURE_DAMAGE_SCALE if capture_active() and hostile else raw_damage

static func entry_fraction(start: Vector3, end: Vector3, center: Vector3, radius := CAPTURE_RADIUS) -> float:
	# Swept XZ circle test: fast shots cannot tunnel through the capture area.
	var a := Vector2(start.x - center.x, start.z - center.z)
	var d := Vector2(end.x - start.x, end.z - start.z)
	var c := a.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var length_squared := d.length_squared()
	if length_squared < 0.000001:
		return -1.0
	var b := a.dot(d)
	var discriminant := b * b - length_squared * c
	if discriminant < 0.0:
		return -1.0
	var t := (-b - sqrt(discriminant)) / length_squared
	return t if t >= 0.0 and t <= 1.0 else -1.0

extends RigidBody3D

# 拖拽状态标记
var is_dragging: bool = false
const RAY_MAX_LENGTH = 100.0
# 拖拽起点（地面平面坐标）
var drag_start_plane_pos: Vector3 = Vector3.ZERO

# 可调参数
@export var throw_scale: float = 6.0
@export var drag_plane_y: float = 0.0

@onready var camera: Camera3D = get_viewport().get_camera_3d()

func _input(event: InputEvent) -> void:
	# 按下左键拾取骰子
	if event.is_action_pressed("mouse_left"):
		var hit = ray_cast_mouse()
		if hit and hit["collider"] == self:
			is_dragging = true
			# 冻结物理，骰子固定原地不动
			gravity_scale = 0.0
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			# 记录按下瞬间鼠标平面坐标作为蓄力起点
			drag_start_plane_pos = get_mouse_plane_pos()
			print("选中骰子，开始蓄力拖拽")
	
	# 松开左键，根据拖拽距离投掷
	if event.is_action_released("mouse_left") and is_dragging:
		is_dragging = false
		# 恢复重力
		gravity_scale = 1.0
		
		var drag_end_plane_pos = get_mouse_plane_pos()
		var drag_delta = drag_end_plane_pos - drag_start_plane_pos
		# 拖拽位移转为投掷冲量
		var throw_impulse = drag_delta * throw_scale
		apply_central_impulse(throw_impulse)
		print("释放投掷，力度向量：", throw_impulse)

func _physics_process(delta: float) -> void:
	# 拖拽时不移动骰子，直接清空物理速度固定原位
	if is_dragging:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

# 获取鼠标射线与拖拽平面交点
func get_mouse_plane_pos() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var ground_plane = Plane(Vector3.UP, drag_plane_y)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	
	if intersect == null:
		return global_position
	return intersect

# 鼠标拾取射线检测骰子
func ray_cast_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_from = camera.project_ray_origin(mouse_pos)
	var ray_to = ray_from + camera.project_ray_normal(mouse_pos) * RAY_MAX_LENGTH
	var ray_query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	return get_world_3d().direct_space_state.intersect_ray(ray_query)

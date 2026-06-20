extends RigidBody3D

# 拖拽状态标记（原版完全不动）
var is_dragging: bool = false
const RAY_MAX_LENGTH = 100.0
var drag_start_plane_pos: Vector3 = Vector3.ZERO

# 导出可调参数
@export var throw_scale: float = 6.0
@export var drag_plane_y: float = 0.0
# 虚线点阵配置
@export var point_interval: float = 0.4
@export var point_size: float = 0.08
@export var max_preview_length: float = 12.0
@export var color_weak: Color = Color(0, 0.7, 1)
@export var color_strong: Color = Color(1, 0.2, 0.1)

@onready var camera: Camera3D = get_parent().get_node("Camera3D")

# 虚线点缓存数组
var preview_points: Array[MeshInstance3D] = []
# 【改动1：替换为四边形面片，不再用球体】
var dot_mesh: QuadMesh
var dot_mat: StandardMaterial3D

func _ready():
	# 初始化薄四边形面片
	dot_mesh = QuadMesh.new()
	dot_mesh.size = Vector2(point_size, point_size)
	
	# 初始化材质（核心：开启Billboard，永远面向相机）
	dot_mat = StandardMaterial3D.new()
	dot_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.depth_draw_mode = StandardMaterial3D.DEPTH_DRAW_DISABLED
	# 公告板模式：面片永远正对相机，任何角度都是正方块/圆点
	dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# 正交相机保持屏幕尺寸不变，模拟UI
	dot_mat.billboard_keep_scale = true

func _input(event: InputEvent) -> void:
	# 鼠标左键按下拾取骰子
	if event.is_action_pressed("mouse_left"):
		var hit = ray_cast_mouse()
		if hit and hit["collider"] == self:
			is_dragging = true
			gravity_scale = 0.0
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			drag_start_plane_pos = get_mouse_plane_pos()
			print("选中骰子，开始拖拽蓄力")
	
	# 鼠标松开投掷
	if event.is_action_released("mouse_left") and is_dragging:
		is_dragging = false
		gravity_scale = 1.0
		
		var drag_end_plane_pos = get_mouse_plane_pos()
		var drag_delta = drag_end_plane_pos - drag_start_plane_pos
		drag_delta.y = 0
		var throw_impulse = drag_delta * throw_scale
		apply_central_impulse(throw_impulse)
		
		clear_all_points()

func _process(delta: float) -> void:
	if is_dragging:
		update_dashed_preview()

func _physics_process(delta: float) -> void:
	if is_dragging:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

# 获取鼠标与桌面平面交点
func get_mouse_plane_pos() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var table_plane = Plane(Vector3.UP, drag_plane_y)
	var intersect = table_plane.intersects_ray(ray_origin, ray_dir)
	
	if intersect == null:
		return drag_start_plane_pos
	intersect.y = drag_plane_y
	return intersect

# 鼠标射线拾取检测
func ray_cast_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_from = camera.project_ray_origin(mouse_pos)
	var ray_to = ray_from + camera.project_ray_normal(mouse_pos) * RAY_MAX_LENGTH
	var ray_query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	return get_world_3d().direct_space_state.intersect_ray(ray_query)

# 清空所有预览虚线点
func clear_all_points():
	for p in preview_points:
		if p.is_inside_tree():
			p.queue_free()
	preview_points.clear()

# 实时刷新虚线点阵【已修正向量方向，线条和拖拽同向】
func update_dashed_preview():
	clear_all_points()
	
	var current_mouse_pos = get_mouse_plane_pos()
	# 修复线条反向：鼠标当前 - 按下起点
	var drag_dir_raw = current_mouse_pos - drag_start_plane_pos
	drag_dir_raw.y = 0
	var drag_power = drag_dir_raw.length()
	
	# 限制最大显示长度
	var display_dir: Vector3
	if drag_power > max_preview_length:
		display_dir = drag_dir_raw.normalized() * max_preview_length
	else:
		display_dir = drag_dir_raw
	
	var power_ratio = clamp(drag_power / max_preview_length, 0, 1)
	var point_color = lerp(color_weak, color_strong, power_ratio)
	
	var total_length = display_dir.length()
	var step_float = floor(total_length / point_interval)
	var step_count: int = int(step_float)
	
	# 生成一排公告板面片虚线点
	for i in range(1, step_count + 1):
		var step_offset = display_dir.normalized() * point_interval * i
		var point_world_pos = drag_start_plane_pos + step_offset
		
		var dot = MeshInstance3D.new()
		dot.mesh = dot_mesh
		var mat_inst = dot_mat.duplicate()
		mat_inst.albedo_color = point_color
		mat_inst.albedo_color.a = 0.7
		dot.material_override = mat_inst
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.global_position = point_world_pos
		
		add_child(dot)
		preview_points.append(dot)

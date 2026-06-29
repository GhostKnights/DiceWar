extends RigidBody3D

# 拖拽状态标记
var is_dragging: bool = false
const RAY_MAX_LENGTH = 100.0
var drag_start_plane_pos: Vector3 = Vector3.ZERO

# 导出可调参数
@export var throw_scale: float = 6.0
@export var drag_plane_z: float = 0.0 # 原drag_plane_y改名，固定Z轴高度
# 虚线点阵配置
@export var point_interval: float = 0.4
@export var point_size: float = 0.08
@export var max_preview_length: float = 12.0
@export var color_weak: Color = Color(0, 0.7, 1)
@export var color_strong: Color = Color(1, 0.2, 0.1)
# 碰撞翻面力度参数
@export var hit_spin_force: float = 8.0
# 【新增】虚拟摩擦力参数，越大减速越快
@export var virtual_friction: float = 2.5

@onready var camera: Camera3D = get_parent().get_node("Camera3D")

# 虚线点缓存数组
var preview_points: Array[MeshInstance3D] = []
var dot_mesh: QuadMesh
var dot_mat: StandardMaterial3D

func _ready():
	# 初始化薄四边形面片
	dot_mesh = QuadMesh.new()
	dot_mesh.size = Vector2(point_size, point_size)
	
	# 初始化公告板材质
	dot_mat = StandardMaterial3D.new()
	dot_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.depth_draw_mode = StandardMaterial3D.DEPTH_DRAW_DISABLED
	dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot_mat.billboard_keep_scale = true

	# 无重力物理设置
	self.gravity_scale = 0.0

	# 绑定碰撞信号，撞击骰子自动翻面
	body_entered.connect(_on_body_collide)

func _input(event: InputEvent) -> void:
	# 鼠标左键按下拾取骰子
	if event.is_action_pressed("mouse_left"):
		var hit = ray_cast_mouse()
		if hit and hit["collider"] == self:
			is_dragging = true
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			drag_start_plane_pos = get_mouse_xy_plane_pos()
			print("选中骰子，开始拖拽蓄力")
	
	# 鼠标松开投掷
	if event.is_action_released("mouse_left") and is_dragging:
		is_dragging = false
		var drag_end_plane_pos = get_mouse_xy_plane_pos()
		var drag_delta = drag_end_plane_pos - drag_start_plane_pos
		drag_delta.z = 0 # 强制忽略Z轴，只保留XY推力
		var throw_impulse = drag_delta * throw_scale
		apply_central_impulse(throw_impulse)
		
		clear_all_points()

# 消除未使用参数警告 + 顶层安全校验
func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	if is_dragging:
		update_dashed_preview()

func _physics_process(delta: float) -> void:
	if is_dragging:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return # 拖拽状态直接退出，不执行减速逻辑


	
	# 检测当前和多少个物理体接触
	var contact_count = get_contact_count()
	print("当前接触物体数量：", contact_count)

	# ========== 新增：纯代码虚拟摩擦力减速逻辑 ==========
	var slow_factor = 1.0 - virtual_friction * delta
	slow_factor = max(slow_factor, 0.0) # 防止系数为负反向加速
	# 仅对XY滑行速度做缩放减速
	linear_velocity.x *= slow_factor
	linear_velocity.y *= slow_factor
	# 低速阈值，速度极低直接归零，避免无限微滑抖动
	var min_stop_speed = 0.02
	if linear_velocity.length() < min_stop_speed:
		linear_velocity = Vector3.ZERO
	# ====================================================

# 碰撞回调：骰子互撞产生翻转轴力
func _on_body_collide(hit_body: Node3D) -> void:
	if hit_body == self or hit_body is StaticBody3D:
		return
	var random_torque = Vector3(
		randf_range(-hit_spin_force, hit_spin_force),
		randf_range(-hit_spin_force, hit_spin_force),
		randf_range(-hit_spin_force, hit_spin_force)
	)
	apply_torque_impulse(random_torque)

# 【核心改造】鼠标投射至 XY 垂直平面，固定Z，完全忽略Z轴
func get_mouse_xy_plane_pos() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	# Plane(法向量, 固定Z高度)：法向BACK = Z轴方向，平面平行XY
	var xy_plane = Plane(Vector3.BACK, drag_plane_z)
	var intersect = xy_plane.intersects_ray(ray_origin, ray_dir)
	
	if intersect == null:
		return drag_start_plane_pos
	intersect.z = drag_plane_z
	return intersect

# 鼠标射线拾取检测
func ray_cast_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_from = camera.project_ray_origin(mouse_pos)
	var ray_to = ray_from + camera.project_ray_normal(mouse_pos) * RAY_MAX_LENGTH
	var ray_query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	return get_world_3d().direct_space_state.intersect_ray(ray_query)

# 安全清空虚线点，解决游离节点崩溃
func clear_all_points():
	var to_remove = preview_points
	preview_points = []
	for p in to_remove:
		if p.is_inside_tree():
			p.queue_free()

# 刷新拖拽预览线（抬高Z避免穿透平面，仅XY方向延伸）
func update_dashed_preview():
	if not is_inside_tree():
		return
	clear_all_points()
	
	var current_mouse_pos = get_mouse_xy_plane_pos()
	var drag_dir_raw = current_mouse_pos - drag_start_plane_pos
	drag_dir_raw.z = 0 # 预览线只走XY，剔除Z分量
	var drag_power = drag_dir_raw.length()
	
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
	
	for i in range(1, step_count + 1):
		var step_offset = display_dir.normalized() * point_interval * i
		# Z轴轻微抬高0.05，预览线悬浮平面上方，不会穿透
		var point_world_pos = drag_start_plane_pos + step_offset + Vector3(0, 0, 0.05)
		
		var dot = MeshInstance3D.new()
		dot.mesh = dot_mesh
		var mat_inst = dot_mat.duplicate()
		mat_inst.albedo_color = point_color
		mat_inst.albedo_color.a = 0.7
		dot.material_override = mat_inst
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		add_child(dot)
		dot.global_position = point_world_pos
		
		if dot.is_inside_tree():
			preview_points.append(dot)

extends RigidBody3D

# 拖拽状态标记
var is_dragging: bool = false
const RAY_MAX_LENGTH = 100.0

# 全局相机缓存
@onready var camera: Camera3D = get_viewport().get_camera_3d()

func _input(event: InputEvent) -> void:
	# 鼠标左键按下
	if event.is_action_pressed("mouse_left"):
		var hit = ray_cast_mouse()
		# hit不为空 = 命中碰撞体
		if hit and hit["collider"] == self:
			is_dragging = true
			print("【拖拽触发】成功选中骰子，进入拖拽状态")
	
	# 鼠标松开，结束拖拽
	if event.is_action_released("mouse_left") and is_dragging:
		is_dragging = false
		print("【拖拽结束】松开鼠标，退出拖拽状态")

# 鼠标射线检测（Godot4 标准3D射线写法）
func ray_cast_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_from = camera.project_ray_origin(mouse_pos)
	var ray_to = ray_from + camera.project_ray_normal(mouse_pos) * RAY_MAX_LENGTH
	
	# 构建射线查询参数（4.x必须这么写）
	var ray_query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	# 执行射线检测，只传一个参数ray_query
	var result = get_world_3d().direct_space_state.intersect_ray(ray_query)
	return result

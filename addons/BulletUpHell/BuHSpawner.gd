@tool
extends Node2D

signal bullet_collided_area(area:Area2D,area_shape_index:int,bullet:Dictionary,local_shape_index:int,shared_area:Area2D)
signal bullet_collided_body(body:Node,body_shape_index:int,bullet:Dictionary,local_shape_index:int,shared_area:Area2D)
signal resume_process(process_id:int)

const STANDARD_BULLET_RADIUS:float = 5

var CUSTOM:customFunctions = customFunctions.new()
var DrawerInstance:Node2D

@export var custom_bullet_prop_data:Dictionary
@export_placeholder("Group name") var GROUP_BOUNCE:PackedStringArray = ["Bounce"]
@export_range(0.001, 999, 0.01, "hide_slider") var time_scale:float = 1
@export var Gravity:Vector2 = Vector2(0,0)
@export var MAX_ACC:int = 500

@export_group("Resource Lists")
@export var default_idle:animState
@export var default_spawn:animState
@export var default_shoot:animState
@export var default_waiting:animState
@export var default_delete:animState

@export_group("Optimisation Culling", "cull_")
enum CULLINGLVL {Anim, Move, Full, Inherit}
@export var cull_technique:CULLINGLVL = CULLINGLVL.Full
@export var cull_trigger:bool = true
@export_range(0.01, 60, 0.016, "hide_slider") var cull_culling_rate:float = 0.01
@export_subgroup("Screen Culling", "cull_")
@export_range(0, 999999, 10, "hide_slider") var cull_margin:float = STANDARD_BULLET_RADIUS*10
@export var cull_fixed_screen:bool = false
@export_range(0.01, 60, 0.016, "hide_slider") var cull_viewport_refresh:float = 0.01
@export_subgroup("Culling from distance to...")
@export_range(0, 999999, 10, "hide_slider") var cull_faking_dist:float = 0
@export_range(0, 999999, 10, "hide_slider") var cull_unfaking_dist:float = 0


## Data Structs
var arrayProps:Dictionary = {}
var arrayTriggers:Dictionary = {}
var arrayPatterns:Dictionary = {}
var arrayContainers:Dictionary = {}
var arrayInstances:Dictionary = {}
var arrayAnim:Dictionary = {}
@onready var textures:SpriteFrames = $ShapeManager.sprite_frames
@onready var arrayShapes:Dictionary = {} # format: id={shape, offset, rotation}


var poolBullets:Dictionary = {} # (active rid, bullet) OPTI: array=rid + array[Dict]=bullet
var Phys = PhysicsServer2D
enum BState{Unactive, Spawning, Spawned, Shooting, Moving, Deleting, QueuedFree}
const UNACTIVE_ZONE:Vector2 = Vector2(99999,99999)
# pooling
var inactive_pool:Dictionary = {}

# spawning processes
var process_stop:Array[int] = []
var process_stop_all:bool = false
var process_pause:Array[int] = []
var process_pause_all:bool = false
var process_get:int = 0
var process_infos:Array = []
var process_counter:int = 0

# spawning delays
var poolQueue:Array = [] # format : [action:0=spawn1=shoot2=both, arraytospawn, arraytoshoot]
var poolTimes:Array[float] = []
var time:float = 0

var RAND = RandomNumberGenerator.new()
var expression = Expression.new()
var _delta:float = 0
var start_homing_group:Array[String]
var HOMING_MARGIN := 20.0
enum GROUP_SELECT{Nearest_on_homing, Nearest_on_spawn, Nearest_on_shoot, Nearest_anywhen, Random}
enum SYMTYPE{ClosedShape,Line}
enum CURVE_TYPE{None, LoopFromStart, OnceThenDie, OnceThenStay, LoopFromEnd, OnceThenStop}
enum LIST_ENDS{Stop, Loop, Reverse}
enum ANIM{TEXTURE, COLLISION, SFX, SCALE, SKEW}
enum LATENCE {No, PosOnly, Rotation, Spin, Aim}
enum INTERRUPT {Continue, Destroy, Shoot}

# culling
enum CULLINGSTATES {Onscreen=-1, Invisible=0, Frozen=1, UnFrozen=-2, Culled=2, Fake=3}
@onready var viewrect = get_viewport().get_visible_rect().grow(cull_margin)
var _viewport_refresher:float = 0
var _cull_rate:float = 0
var can_cull:bool = false
var interest_list:Array[Node]

var global_reset_counter:int = 0



#§§§§§§§§§§§§§ GLOBAL §§§§§§§§§§§§§

func _ready():
	$ShapeManager.hide()
	if Engine.is_editor_hint(): return

	DrawerInstance = $"Drawers/0".duplicate()
	$"Drawers/0".z_index = z_index
	$"Drawers/0".name = str(z_index)

	randomize()

	for s:Node2D in $ShapeManager.get_children():
		assert(s is CollisionShape2D or s is CollisionPolygon2D)
		if s.shape: arrayShapes[s.name] = [s.shape,s.position,s.rotation]
		s.queue_free()

	for a:Area2D in $SharedAreas.get_children():
		assert(a is Area2D)
		a.connect("area_shape_entered",Callable(self,"bullet_collide_area").bind(a))
		a.connect("body_shape_entered",Callable(self,"bullet_collide_body").bind(a))
		a.set_meta("ShapeCount", 0)
		a.set_meta("Bullets", {})

	reset_bounce()

	var default_anims:Array[animState] = [default_idle, default_spawn, default_shoot, default_waiting, default_delete]
	for a:int in default_anims.size():
		default_anims[a].ID = "@"+["anim_idle","anim_spawn","anim_shoot","anim_waiting","anim_delete"][a]
		set_anim_states(default_anims[a])


func reset(minimal:bool=false):
	# change that in order signal that a reset has been made and stop the currently running func
	global_reset_counter += 1
	# reset bullets
	reset_bullets()
	# empty data structure
	inactive_pool.clear()
	poolBullets.clear()
	poolQueue.clear()
	poolTimes.clear()
	# reset time count
	time = 0
	_delta = 0
	# reset active bullet states
	for a:Area2D in $SharedAreas.get_children():
		a.set_meta("ShapeCount", 0)
		a.set_meta("Bullets", {})
	# reset bounce calculation
	reset_bounce()
	# remove Drawers
	for child:Node2D in $Drawers.get_children():
		child.queue_free()
	# remove unneeded resources
	if not minimal:
		arrayContainers.clear()
		arrayInstances.clear()
		arrayPatterns.clear()
		arrayTriggers.clear()
		arrayProps.clear()
	else:
		for array:Dictionary in [arrayContainers, arrayInstances, arrayPatterns, arrayProps, arrayTriggers, arrayAnim]:
			for elem in array.keys():
				if elem[0] == "@": continue
				array.erase(elem)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	_delta = delta*time_scale

	if not cull_fixed_screen:
		_viewport_refresher += _delta
		if _viewport_refresher >= cull_viewport_refresh: update_viewport()

	if not poolBullets.is_empty():
		_update_culling()
		queue_redraw()

	time += _delta
	var next_in_queue:Array
	while not poolQueue.is_empty() and poolTimes[0] < time:
		next_in_queue = poolQueue.pop_front()
		if next_in_queue[0]["state"] == BState.Unactive: _spawn(next_in_queue)
		elif next_in_queue[0]["state"] < BState.Moving: _shoot(next_in_queue)
		poolTimes.pop_front()

	# handle bounces
	for i:int in range(min(bounce_queue.size(), $Bouncy.get_child_count())):
		var bounce_data:Array = bounce_queue.pop_front()
		_process_bounce(bounce_data[0], bounce_data[1], bounce_data[2])

func change_scene_to_file(file:String):
	reset_bullets()
	get_tree().change_scene_to_file(file)

func change_scene_to_packed(scene:PackedScene):
	reset_bullets()
	get_tree().change_scene_to_packed(scene)

func reset_bullets():
	clear_all_bullets()

func call_custom(function:String, argv:Array=[]):
	if not CUSTOM.has_method(function): return
	CUSTOM.callv(function, argv)




#§§§§§§§§§§§§§ RESOURCES §§§§§§§§§§§§§

func new_instance(id:String, instance:Node2D):
	if arrayInstances.has(id):
		push_warning("Warning : New instance ignored. Name "+id+" already exists. Make sure this duplicate isn't an error.")
		return
	arrayInstances[id] = instance
func new_trigger(id:String, t:RichTextEffect):
	if arrayTriggers.has(id):
		push_warning("Warning : New trigger ignored. Name "+id+" already exists. Make sure this duplicate isn't an error.")
		return
	arrayTriggers[id] = t
func new_pattern(id:String, p:Pattern):
	if arrayPatterns.has(id):
		push_warning("Warning : New pattern ignored. Name "+id+" already exists. Make sure this duplicate isn't an error.")
		return
	arrayPatterns[id] = p
func new_bullet(id:String, b:Dictionary):
	if arrayProps.has(id):
		push_warning("Warning : New bullet ignored. Name "+id+" already exists. Make sure this duplicate isn't an error.")
		return
	arrayProps[id] = b
func new_container(node):
	if arrayContainers.has(node.id):
		push_warning("Warning : New container ignored. Name "+node.id+" already exists. Make sure this duplicate isn't an error.")
		return
	arrayContainers[node.id] = node

func instance(id:String) -> Node2D:
	assert(arrayInstances.has(id), "Trying to get the scene instance named "+id+", which doesn't exist.")
	return arrayInstances[id]
func trigger(id:String):
	assert(arrayTriggers.has(id), "Trying to get the trigger "+id+", which doesn't exist.")
	return arrayTriggers[id]
func pattern(id:String):
	assert(arrayPatterns.has(id), "Trying to get the pattern "+id+", which doesn't exist.")
	return arrayPatterns[id]
func bullet(id:String):
	assert(arrayProps.has(id), "Trying to get the bulletprops "+id+", which doesn't exist.")
	return arrayProps[id]
func container(id:String):
	assert(arrayContainers.has(id), "Trying to get the trigger container "+id+", which doesn't exist.")
	return arrayContainers[id]


#### API for nodes ####

func update_custom_bullet_prop_data(props:BulletProps):
	for key in self.custom_bullet_prop_data:
		if props.custom_data.has(key): continue
		else: props.custom_data[key] = self.custom_bullet_prop_data[key]
	for key in props.custom_data:
		if self.custom_bullet_prop_data.has(key): continue
		else: props.custom_data.erase(key)
	return props

func generate_new_bulletprops():
	var props := BulletProps.new()
	# manage custom data
	if not self.custom_bullet_prop_data.is_empty():
		return update_custom_bullet_prop_data(props)
	return props

func generate_new_bulletnodeprops():
	var props := BulletNodeProps.new()
	# manage custom data
	if not self.custom_bullet_prop_data.is_empty():
		return update_custom_bullet_prop_data(props)
	return props

# remove unnecessary bloat from bulletprops and return a clean dictionary
func sanitize_bulletprops(props:PackedDataContainer, id:String, source:Node) -> Dictionary:
	if not props is ObjectProps:
		if props.homing_type == props.TARGET_TYPE.ListPositions:
			props.homing_list = props.homing_list_pos.duplicate()
		elif props.homing_type == props.TARGET_TYPE.ListNodes:
			props.homing_list = []
			for n:NodePath in props.homing_list_nodes: props.homing_list.append(source.get_node(n))
		elif props.homing_type == props.TARGET_TYPE.MouseCursor:
			props.homing_mouse = true
		if props.homing_target: props.node_homing = source.get_node(props.homing_target)
		elif props.homing_special_target: props.node_homing = get_special_target(props.homing_special_target)
		elif not (props.homing_list.size() < 2 or props.homing_list_ordered): props.homing_list.shuffle()

	var dict:Dictionary = {}; var P:String; var value; var has_random:bool=false;
	var allow_random:bool = (props is ObjectProps or randf_range(0,1) <= props.get("r_randomisation_chances"));
	for p:Dictionary in props.get_property_list():
		P = p["name"]
		value = props.get(P)
		if P in ["__data__","spec_top_level","spec_ally","mask","r_randomisation_chances", "resource_scene_unique_id",
			"RefCounted","Resource","resource_local_to_scene","resource_path","Resource","node_container",
			"resource_name","PackedDataContainer","script","Script Variables","homing_position", "homing_list_ordered", "homing_type",
			"homing_list_pos","homing_list_nodes","Movement","Physics","Visuals","Homing","Destruction", "Depth",
			"Triggers","Homing","BulletProps.gd","ObjectProps.gd","BulletNodeProps.gd","Random","","Color","Trail","Scale"]:
				continue
		elif P in ["a_direction_equation","trigger_container", "anim_spawn_texture","anim_waiting_texture",\
			"anim_delete_texture","anim_spawn_collision","anim_waiting_collision","anim_delete_collision",\
			"homing_special_target","homing_group","homing_start_signal","a_angular_equation"] and value == "": continue
		elif P in ["a_speed_multi_iterations","scale_multi_iterations","spec_bounces","spec_rotating_speed", \
			"spec_warn","spec_explo","spec_skew","spec_modulate_loop","spec_trail_length",\
			"a_curve_movement","death_speed_under","homing_detection_dist","spec_trail_unlimited"] and int(value) == int(0): continue
		elif P in ["anim_idle_sfx","anim_spawn_sfx","anim_waiting_sfx","anim_delete_sfx"] and value == -1: continue
		elif P in ["spec_tourment","spec_no_collision","overwrite_groups","homing_mouse","spec_spin_only_sprite","no_rotation", \
				] and value == false: continue
		elif P == "homing_target" and value == NodePath(): continue
		elif P in ["homing_position","homing_imprecision", "depth_active"] and value == Vector2(): continue
		elif P in ["spec_modulate","curve", "spec_trail_gradient"] and value == null: continue
		elif P in ["homing_list","homing_surface","groups"] and value.is_empty(): continue
		elif P == "death_outside_box" and value == Rect2(): continue
		elif P == "spec_weight" and value == 1 and Gravity == Vector2.ZERO: continue

		elif P in ["homing_steer","homing_time_start","homing_duration","node_homing","homing_range","homing_imprecision","homing_detection_dist"] \
			and not ((dict.get("homing_target",false) or dict.get("homing_position",false)) \
			or (dict.get("homing_group",false) or dict.get("homing_special_target",false)) \
			or (dict.get("homing_surface",false) or dict.get("homing_mouse",false) or dict.get("homing_list",false))): continue
		elif P in ["a_speed_multiplier","a_speed_multi_scale"] \
			and not dict.get("a_speed_multi_iterations",false): continue
		elif P in ["scale_multiplier","scale_multi_scale"] \
			and not dict.get("scale_multi_iterations",false): continue
		elif P == "trigger_wait_for_shot" and not dict.has("trigger_container"): continue
		elif P == "homing_select_in_group" and not (dict.has("homing_group") or dict.has("homing_mouse")): continue
		elif P in ["homing_when_list_ends"] and not dict.has("homing_list"): continue
		elif P in ["spec_trail_modulate","spec_trail_width","spec_trail_fade_out", "spec_trail_thin_out", "spec_trail_smooth"] \
				and not dict.has("spec_trail_length"): continue
		elif P in ["depth_spawn","depth_speed","depth_min_max","depth_bounce"] \
				and not dict.has("depth_active"): continue

		elif P.left(5) == "anim_":
			if P == "anim_more":
				for a:animState in value: set_anim_states(a, P, id)
			elif P == "anim_idle":
				if value == null: dict[P] = "@anim_idle"
				else:
					set_anim_states(value, P, id)
					dict[P] = value.ID
			elif P in ["anim_spawn","anim_shoot","anim_waiting","anim_delete"]:
				if value == null: dict[P] = dict["anim_idle"]
				else:
					set_anim_states(value, P, id)
					dict[P] = value.ID
			continue

		elif P.left(2) == "r_":
			if not allow_random or \
			(p["type"] == TYPE_STRING and value == "") or \
			(p["type"] == TYPE_VECTOR3 and value == Vector3()) or \
			(p["type"] == TYPE_FLOAT and value == 0.0) or \
			(p["type"] in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, \
				TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY] and value.is_empty()): continue

			if p["type"] == TYPE_STRING: props.set(P, Array(value.split(";",false)))

			if not has_random:
				has_random = true
				dict["has_random"] = true

		elif P == "instance_id":
			assert(value != "", "Instance_ID field can't be empty in node "+name)
			if ";" in value: props.set(P, Array(value.split(";",false)))

		elif P == "custom_data":
			for key in value:
				dict[key] = value[key]

		elif P == "z_index":
			if value == 0: value = z_index
			if value != z_index and not $Drawers.has_node(str(value)):
				var new_node := DrawerInstance.duplicate()
				new_node.name = str(value)
				new_node.z_index = value
				$Drawers.add_child(new_node)

		dict[P] = value
	dict["__ID__"] = id
	return dict

func set_anim_states(a:animState, P:String="", id:String=""):
	if a.ID == "": a.ID = "_"+id+"_"+P
	var col
	var sfx
	if a.texture == "": a.texture = arrayAnim["@"+P][ANIM.TEXTURE]
	if a.collision == "": col = arrayAnim["@"+P][ANIM.COLLISION]
	else: col = arrayShapes[a.collision]
	if a.SFX == "": sfx = null
	else: sfx = $SFX.get_node(a.SFX)

	arrayAnim[a.ID] = [a.texture, col, sfx, a.tex_scale, a.tex_skew]
	return a.ID

func sanitize_pattern(pattern:Pattern, source:Node):
	if pattern.forced_target: pattern.node_target = source.get_node(pattern.forced_target)
	if pattern.get("pattern_angle_target"):
		var test = pattern.get("pattern_angle_target");
		pattern.node_pattern_target = source.get_node(pattern.pattern_angle_target)
	if pattern.resource_name == "PatternCustomShape":
		if pattern.closed_shape: pattern.symmetry_type = SYMTYPE.ClosedShape
	elif pattern.resource_name in ["PatternLine","PatternCircle"]:
		if not pattern.skip_list.is_empty():
			pattern.skip_array = pattern.skip_list
		elif pattern.skip_step > 0:
			var i:int = 0
			while i < pattern.nbr:
				if (i+1)%pattern.skip_step == 0:
					for amount:int in pattern.skip_amount: pattern.skip_array.append(i+amount+1)
					i += pattern.skip_amount-1
				i += 1

	if pattern.bullet == "" and not pattern.bullet_list.is_empty():
		pattern.bullet = pattern.bullet_list[0]

	if not pattern.cooldown_layers.is_empty():
		pattern.max_layer = pattern.cooldown_layers[pattern.cooldown_layers.size()-1].x

	# determines if the pattern contains randomness
	if pattern.random != null:
		var ran:PatternRandomizer = pattern.random
		if int(ran.randomisation_chances) == 1 or randf_range(0, 1) < ran.randomisation_chances:
			var P:String
			for p:Dictionary in ran.get_property_list():
				P = p["name"]
				if (p["type"] == TYPE_STRING and ran.get(P) == "") or \
					(p["type"] == TYPE_VECTOR3 and ran.get(P) == Vector3()) or \
					(p["type"] == TYPE_FLOAT and ran.get(P) == 0.0) or \
					(p["type"] in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY] \
					and ran.get(P).is_empty()) or \
					P == "randomisation_chances": continue
				pattern.has_random = true
				break
	return pattern

# PatternCustomArea : creates a polygon from a curve
func curve_to_polygon(pattern:NavigationPolygon, curve:Curve2D):
	var point:Vector2; var poly:Array[Vector2]
	for p:int in curve.get_point_count():
		point = curve.get_point_position(p)
		poly.append(point)
		if point.x < pattern.limit_rect.position.x: pattern.limit_rect.position.x = point.x
		if point.x > pattern.limit_rect.size.x: pattern.limit_rect.size.x = point.x
		if point.y < pattern.limit_rect.position.y: pattern.limit_rect.position.y = point.y
		if point.y > pattern.limit_rect.size.y: pattern.limit_rect.size.y = point.y
	pattern.polygon = PackedVector2Array(poly)

# PatternCustomPoints : find the positions and angles of the bullets
func points_distribute(pattern:NavigationPolygon, curve:Curve2D):
	var point_count:int = curve.get_point_count()
	pattern.nbr = point_count
	var angle:float; var pos:Vector2
	for point:int in point_count:
		pos = curve.get_point_position(point)
		if pattern.calculate_angles == pattern.ANGLE_TYPE.FromTangeant:
			if point == point_count-1:
				angle = pos.angle_to_point(curve.get_point_position(point-1))+PI/2
			elif point == 0:
				angle = curve.get_point_position(point+1).angle_to_point(pos)+PI/2
			else:
				angle = curve.get_point_position(point+1).angle_to_point(curve.get_point_position(point-1))+PI/2
		elif pattern.calculate_angles == pattern.ANGLE_TYPE.FromCenter:
			angle = pattern.center_pos.angle_to_point(pos)+PI
		pattern.pos.append(pos-pattern.center_pos)
		if pattern.calculate_angles != pattern.ANGLE_TYPE.Custom:
			pattern.angles.append(angle+(PI*int(pattern.reversed_angle)))

# PatternCustomArea : generates spawn positions for bullets inside an area
func area_distribute(pattern:NavigationPolygon):
	var maybe_pos; var tries:int
	for i:int in pattern.pooling:
		pattern.pos.append([])
		for j:int in pattern.nbr:
			maybe_pos = Vector2(randf_range(pattern.limit_rect.position.x,pattern.limit_rect.size.x),\
								randf_range(pattern.limit_rect.position.y,pattern.limit_rect.size.y))
			tries = pattern.tries_max
			while tries > 0 and not Geometry2D.is_point_in_polygon(maybe_pos, pattern.polygon):
				tries -= 1
				maybe_pos = Vector2(randf_range(pattern.limit_rect.position.x,pattern.limit_rect.size.x),\
									randf_range(pattern.limit_rect.position.y,pattern.limit_rect.size.y))
			pattern.pos[i].append(maybe_pos-pattern.center_pos)

# PatternCustomArea : generates spawn positions for bullets inside an area following a grid pattern
func grid_distribute(pattern:NavigationPolygon):
	pattern.pos.append([])
	var maybe_pos
	for x:float in (pattern.limit_rect.size.x-pattern.limit_rect.position.x)/pattern.grid_spawning.x:
		for y:float in (pattern.limit_rect.size.y-pattern.limit_rect.position.y)/pattern.grid_spawning.y:
			maybe_pos = pattern.limit_rect.position+Vector2(pattern.grid_spawning.x*x,pattern.grid_spawning.y*y)
			if Geometry2D.is_point_in_polygon(maybe_pos, pattern.polygon):
				pattern.pos[0].append(maybe_pos-pattern.center_pos)
	pattern.nbr = pattern.pos[0].size()
	pattern.pooling = 1

# PatternCustomShape : generates spawn positions and angles for bullets along a custom curve
func shape_distribute(pattern:NavigationPolygon, curve:Curve2D, follow:PathFollow2D):
	var length:float = curve.get_baked_length()
	for b:int in pattern.nbr:
		var pos_on_curve
		if pattern.closed_shape: pos_on_curve = length/pattern.nbr*b
		else: pos_on_curve = length/(pattern.nbr-1)*b
		follow.h_offset = pos_on_curve
		pattern.pos.append(pattern.shape.sample_baked(pos_on_curve).rotated(pattern.pattern_angle)-pattern.center_pos)
		pattern.angles.append(follow.rotation-PI/2)




#§§§§§§§§§§§§§ POOLING §§§§§§§§§§§§§

func create_pool(bullet:String, shared_area:String, amount:int, object:bool=false):
	var props:Dictionary = arrayProps[bullet]
	if not inactive_pool.has(bullet):
		inactive_pool[bullet] = []
		inactive_pool["__SIZE__"+bullet] = 0

	if object:
		for i:int in amount:
			inactive_pool[bullet].append(instance(props["instance_id"]).duplicate())
	else:
		var area:Area2D = $SharedAreas.get_node(shared_area)
		var current_count:int
		var new_rid:RID
		for i:int in amount:
			current_count = area.get_meta("ShapeCount")
			new_rid = create_shape(area, arrayAnim[props["anim_spawn"]][ANIM.COLLISION], true, current_count+1)
			area.set_meta("ShapeCount", current_count+1)
			inactive_pool[bullet].append([new_rid, shared_area, current_count]) # Opti ?
	inactive_pool["__SIZE__"+bullet] += amount

# return RID for default bullets OR object reference for scenes
func wake_from_pool(bullet:String, queued_instance:Dictionary, shared_area:String, object:bool=false):
	if not inactive_pool.has(bullet):
		push_warning("WARNING : there's no bullet pool for bullet of ID "+bullet+" . Create a pool upon game load to avoid lag by calling Spawning.create_pool()")
		create_pool(bullet, queued_instance["shared_area"].name, 50, object) # TODO : 50 is arbitrary, there might be lag if it needs more
	elif inactive_pool[bullet].is_empty():
		push_warning("WARNING : bullet pool for bullet of ID "+bullet+" is empty. Create bigger one next time to avoid lag.")
		create_pool(bullet, queued_instance["shared_area"].name, max(inactive_pool["__SIZE__"+bullet]/10, 50), object)

	if inactive_pool[bullet][0] is Array:
		var i:int = 0
		while inactive_pool[bullet][i][1] != shared_area: i += 1
		return inactive_pool[bullet].pop_at(i)
	else: return inactive_pool[bullet].pop_at(0)

func back_to_grave(bullet:String, B:Dictionary):
	var bID = B["RID"]
	if bID is RID:
		B["state"] = BState.QueuedFree
		inactive_pool[bullet].append([bID, B["shared_area"].name, B["index"]])
	else:#if is_instance_valid(bID):  # <--- add if there is an issue
		inactive_pool[bullet].append(bID)
		bID.get_parent().call_deferred("remove_child", bID)
		poolBullets.erase(bID)

func create_shape(shared:Area2D, ColID:Array, init:bool=false, count:int=0) -> RID:
	var new_shape:RID
	var template_shape:Shape2D = ColID[0]
	if template_shape is CircleShape2D:
		new_shape = Phys.circle_shape_create()
		Phys.shape_set_data(new_shape, template_shape.radius)
	elif template_shape is CapsuleShape2D:
		new_shape = Phys.capsule_shape_create()
		Phys.shape_set_data(new_shape, [template_shape.radius,template_shape.height])
	elif template_shape is ConcavePolygonShape2D:
		new_shape = Phys.concave_polygon_shape_create()
		Phys.shape_set_data(new_shape, template_shape.segments)
	elif template_shape is ConvexPolygonShape2D:
		new_shape = Phys.convex_polygon_shape_create()
		Phys.shape_set_data(new_shape, template_shape.points)
	elif template_shape is WorldBoundaryShape2D:
		new_shape = Phys.line_shape_create()
		Phys.shape_set_data(new_shape, [template_shape.d,template_shape.normal])
	elif template_shape is SeparationRayShape2D:
		new_shape = Phys.separation_ray_shape_create()
		Phys.shape_set_data(new_shape, [template_shape.length,template_shape.slide_on_slope])
	elif template_shape is RectangleShape2D:
		new_shape = Phys.rectangle_shape_create()
		Phys.shape_set_data(new_shape, template_shape.extents)
	elif template_shape is SegmentShape2D:
		new_shape = Phys.segment_shape_create()
		Phys.shape_set_data(new_shape, [template_shape.a,template_shape.b])

	Phys.area_add_shape(shared.get_rid(), new_shape, Transform2D(ColID[2],ColID[1]+(UNACTIVE_ZONE*int(init))))
	if count == 0: count = shared.get_meta("ShapeCount")
	Phys.area_set_shape_disabled(shared.get_rid(), count-1, true)
	return new_shape






#§§§§§§§§§§§§§ SPAWN §§§§§§§§§§§§§

### INIT BULLETS DATA ###

func set_angle(pattern:Pattern, pos:Vector2, queued_instance:Dictionary):
	if pattern.forced_target != NodePath() and is_instance_valid(pattern.node_target):
		if pattern.forced_pattern_lookat: queued_instance["rotation"] = pos.angle_to_point(pattern.node_target.global_position)
		else: queued_instance["rotation"] = (pos+queued_instance["spawn_pos"]).angle_to_point(pattern.node_target.global_position)
	elif pattern.forced_lookat_mouse:
		if pattern.forced_pattern_lookat: queued_instance["rotation"] = pos.angle_to_point(get_global_mouse_position())
		else: queued_instance["rotation"] = (pos+queued_instance["spawn_pos"]).angle_to_point(get_global_mouse_position())
	elif pattern.forced_angle != 0.0:
		queued_instance["rotation"] = pattern.forced_angle

func _set_bullet_props(bullet:String, bullet_props:Dictionary={}):
	if bullet_props.is_empty(): bullet_props = arrayProps[bullet]
	if bullet_props.get("has_random", false): bullet_props = create_random_props(bullet_props)
	return bullet_props

func create_bullet_instance_dict(queued_instance:Dictionary, bullet_props:Dictionary, pattern:Pattern):
	queued_instance["shape_disabled"] = true
	queued_instance["speed"] = bullet_props.speed
	queued_instance["vel"] = Vector2()
	queued_instance["interruption"] = pattern.on_interruption
	if bullet_props.has("groups"): queued_instance["groups"] = bullet_props.get("groups")
	if pattern.impulse > 0:
		queued_instance["impulse"] = pattern.impulse
		queued_instance["speed"] += pattern.impulse
	if Gravity != Vector2.ZERO:
		queued_instance["gravity"] = Gravity
		queued_instance["acc"] = Vector2.ZERO
	if pattern.wait_behavior > LATENCE.No:
		queued_instance["follows_parent"] = pattern.wait_behavior
	return queued_instance

func _object_init_groups(is_bullet_node:bool, bID:Node2D, queued_instance:Dictionary, bullet_props):
	if is_bullet_node: bID.b = queued_instance
	if bullet_props.has("overwrite_groups"):
		for g:String in bID.get_groups():
			bID.remove_group(g)
	for g:String in bullet_props.get("groups", []):
		bID.add_to_group(g)

func set_spawn_data(queued_instance:Dictionary, bullet_props:Dictionary, pattern:Pattern, i:int, ori_angle:float, pos:Vector2):
	var angle:float
	var forced_angle:float = ori_angle
	if not pattern.resource_name == "PatternOne" and not pattern.get("pattern_angle") == 0:
		forced_angle = pattern.get("pattern_angle")
		if pattern.pattern_angle_target != NodePath() and is_instance_valid(pattern.node_pattern_target):
			forced_angle = pos.angle_to_point(pattern.node_pattern_target.global_position)
		if pattern.pattern_angle_mouse:
			forced_angle = pos.angle_to_point(get_global_mouse_position())

	match pattern.resource_name:
		"PatternCircle":
			angle = get_spawn_angle_circle(pattern.angle_total, pattern.angle_decal, pattern.nbr-int(pattern.angle_total < 2*PI), i)
			queued_instance["spawn_pos"] = get_spawn_pos_circle(angle, forced_angle, pattern.radius, pattern.perspective)
			queued_instance["rotation"] = angle + bullet_props.angle + ori_angle
		"PatternLine":
			queued_instance["spawn_pos"] = get_spawn_pos_line(pattern.offset, pattern.center, forced_angle, pattern.nbr, i)
			queued_instance["rotation"] = bullet_props.angle + pattern.pattern_angle + ori_angle
		"PatternOne":
			queued_instance["spawn_pos"] = Vector2()
			queued_instance["rotation"] = bullet_props.angle + ori_angle
		"PatternCustomShape","PatternCustomPoints":
			queued_instance["spawn_pos"] = pattern.pos[i].rotated(forced_angle)
			queued_instance["rotation"] = bullet_props.angle + pattern.angles[i] + ori_angle
		"PatternCustomArea":
			queued_instance["spawn_pos"] = pattern.pos[randi()%pattern.pooling][i].rotated(forced_angle)
			queued_instance["rotation"] = bullet_props.angle + ori_angle

func get_spawn_positions(pattern:Pattern):
	if pattern.resource_name == "PatternOne": return Vector2()
	var res:Array[Vector2]
	var forced_angle = pattern.get("pattern_angle")
	match pattern.resource_name:
		"PatternCircle":
			for i:int in pattern.nbr:
				res.append(get_spawn_pos_circle(get_spawn_angle_circle(pattern.angle_total, pattern.angle_decal, pattern.nbr-int(pattern.angle_total < 2*PI), i), forced_angle, pattern.radius))
		"PatternLine":
			for i:int in pattern.nbr:
				res.append(get_spawn_pos_line(pattern.offset, pattern.center, forced_angle, pattern.nbr, i))
		"PatternCustomShape","PatternCustomPoints":
			for i:int in pattern.nbr: res.append(pattern.pos[i].rotated(forced_angle))
		"PatternCustomArea":
			for i:int in pattern.nbr: res.append(pattern.pos[randi()%pattern.pooling][i].rotated(forced_angle))
	return res

func get_spawn_rotations(pattern:Pattern, ori_angle:float=0, bullet_angle:float=0):
	if pattern.resource_name == "PatternOne": return Vector2()
	var res:Array[Vector2]
	var forced_angle = pattern.get("pattern_angle")
	match pattern.resource_name:
		"PatternCircle":
			for i:int in pattern.nbr:
				res.append(bullet_angle + ori_angle + get_spawn_angle_circle(pattern.angle_total, pattern.angle_decal, pattern.nbr-int(pattern.angle_total < 2*PI), i))
		"PatternLine":
			for i:int in pattern.nbr: res.append(bullet_angle + pattern.pattern_angle + ori_angle)
		"PatternCustomShape","PatternCustomPoints":
			for i:int in pattern.nbr: res.append(bullet_angle + pattern.angles[i] + ori_angle)
		"PatternCustomArea":
			for i:int in pattern.nbr: res.append(bullet_angle + ori_angle)
	return res

func get_spawn_angle_circle(angle_total:float, angle_decal:float, nbr:int, i:int):
	return (angle_total/nbr)*i + angle_decal

func get_spawn_pos_circle(angle:float, forced_angle:float, radius:float, perspective:float=0):
	return Vector2(cos(angle)*radius*perspective,sin(angle)*radius).rotated(forced_angle)

func get_spawn_pos_line(offset:Vector2, center:int, forced_angle:float, nbr:int, i:int):
	return Vector2(offset.x*4+offset.x*(-abs(center-i-1))-(nbr*offset.x)/2,
					offset.y/2+offset.y*i-(nbr*offset.y)/2).rotated(forced_angle)
#(-abs(center-i-1))

func _stop_spawn(process_id:int, spawner, local_reset_counter:int):
	if process_id in process_stop:
		process_stop.erase(process_id)
		return true
	if process_stop_all:
		if process_counter == 0: process_stop_all = false
		return true
	if spawner == null: return true
	if local_reset_counter != global_reset_counter: return true
	return false

func _pause_spawn(process_id:int):
	if process_id in process_pause:
		process_pause.erase(process_id)
		return true
	if process_pause_all:
		process_pause_all = false
		return true
	return false

### TRIGGER SPAWN ###

func spawn_list(spawner:Array, id:PackedStringArray, loops:int=1, shared_area:Array[String]=["0"], process_id:int=-1, cust_bullet:Dictionary={}):
	var local_reset_counter:int = global_reset_counter; var returned_stop = false
	var loop_len:int = id.size(); var spawner_len:int = spawner.size()-1; var area_len:int = shared_area.size()-1
	while loops != 0:
		for i:int in loop_len:
			returned_stop = await spawn(spawner[min(i,spawner_len)], id[i], shared_area[min(i,area_len)], process_id, cust_bullet)
			if returned_stop == true or _stop_spawn(process_id, spawner, local_reset_counter): return
		if loops > 0: loops -= 1

# spawner dict : {position, rotation, parent}
func spawn(spawner, id:String, shared_area:String="0", process_id:int=-1, cust_bullet:Dictionary={}):
	assert(arrayPatterns.has(id))
	assert(process_id != 0, "You set process to 0, which is forbidden")
	process_counter += 1
	var pattern:Pattern = arrayPatterns[id]
	if pattern.has_random == true:
		_spawn_random(spawner, id, pattern, shared_area, process_id)
		return
	var local_reset_counter:int = global_reset_counter
	var bullets:Array[Dictionary]
	var iter:int = pattern.iterations; var iter_nbr:int = 0
	var shared_area_node = $SharedAreas.get_node(shared_area)

	var skip_array:Array[PackedInt32Array]
	if pattern.get("skip_array"): skip_array = pattern.skip_array

	var pos:Vector2; var ori_angle:float;
	var bullet_props:Dictionary = cust_bullet; var skipped_bullet:int = 0
	var is_object:bool; var is_bullet_node:bool; var queued_instance:Dictionary; var bID; var new_shape
	var tw_endpos:Vector2; var parent = spawner
	while iter != 0:
		if _stop_spawn(process_id, spawner, local_reset_counter):
			process_counter -= 1
			return true
		if _pause_spawn(process_id):
			var pausing:int = 0
			while pausing not in [-1, process_id]: pausing = await Spawning.resume_process
		if spawner is Node2D:
			ori_angle = spawner.rotation
			pos = spawner.global_position
		elif spawner is Dictionary:
			pos = spawner["position"]
			ori_angle = spawner["rotation"]
			parent = spawner.get("parent", spawner)
		else: push_error("spawner isn't a Node2D or a bullet RID")

		bullet_props = _set_bullet_props(pattern.bullet, bullet_props)

		is_object = bullet_props.has("instance_id")
		is_bullet_node = (is_object and bullet_props.has("speed"))
		for i:int in pattern.nbr:
			if skip_array and i in skip_array[iter_nbr%skip_array.size()]:
				if pattern.skip_in_list: skipped_bullet += 1
				continue
			if cust_bullet.is_empty() and not pattern.bullet_list.is_empty():
				bullet_props = _set_bullet_props(pattern.bullet_list[(i-skipped_bullet)%pattern.bullet_list.size()])

			queued_instance = {}
			queued_instance["shared_area"] = shared_area_node
			queued_instance["props"] = bullet_props
			queued_instance["source_node"] = parent
			queued_instance["state"] = BState.Unactive
			new_shape = wake_from_pool(pattern.bullet, queued_instance, shared_area, is_object)
			bID = new_shape
			if not is_object:
				bID = new_shape[0]
				queued_instance["index"] = new_shape[2]
				queued_instance["anim"] = arrayAnim[bullet_props["anim_idle"]]
				queued_instance["culling_state"] = CULLINGSTATES.Onscreen
				queued_instance["colID"] = queued_instance["anim"][ANIM.COLLISION]
				queued_instance = create_bullet_instance_dict(queued_instance, bullet_props, pattern)
				if bullet_props["z_index"] != z_index: get_node("Drawers/"+str(bullet_props["z_index"])).bullets.append(queued_instance)
				shared_area_node.get_meta("Bullets")[new_shape[2]] = queued_instance
			elif is_bullet_node: queued_instance = create_bullet_instance_dict(queued_instance, bullet_props, pattern)

			set_spawn_data(queued_instance, bullet_props, pattern, i, ori_angle, pos)
			queued_instance["spawn_pos"] += shared_area_node.position

			if not bullet_props.get("fixed_rotation", false):
				set_angle(pattern, pos, queued_instance)
			else: queued_instance["rotation"] = 0

			if pattern.wait_tween_momentum > 0:
				tw_endpos = queued_instance["spawn_pos"]+pos+Vector2(pattern.wait_tween_length, 0).rotated(PI+queued_instance["rotation"])
				queued_instance["momentum_data"] = [pattern.wait_tween_momentum-1, tw_endpos, pattern.wait_tween_time]

			queued_instance["RID"] = bID
			bullets.append(queued_instance)
			poolBullets[bID] = queued_instance

			if is_object: _object_init_groups(is_bullet_node, bID, queued_instance, bullet_props)

		_plan_spawning(pattern, bullets)

		if iter > 0: iter -= 1
		iter_nbr += 1
		if pattern.max_layer > 0:
			for v:Vector2 in pattern.cooldown_layers:
				if iter_nbr%pattern.max_layer == v.x:
					await get_tree().create_timer(v.y, false, true).timeout
					break
				elif iter_nbr < v.x: break
		await get_tree().create_timer(pattern.cooldown_spawn, false, true).timeout
		if process_get == process_id: process_infos = [spawner, pattern, id, bullet_props]
	process_counter -= 1



func _plan_spawning(pattern:Pattern, bullets:Array[Dictionary]):
	var to_shoot:Array[Dictionary] = bullets.duplicate()
	if pattern.cooldown_next_spawn == 0:
		_spawn(bullets)
		if pattern.cooldown_stasis: return
		if pattern.cooldown_next_shoot == 0:
			if pattern.cooldown_shoot == 0: _shoot(to_shoot, true) #no add pos
			else: _plan_queue(to_shoot, pattern.cooldown_shoot)
		else:
			var idx:int
			for b:Dictionary in to_shoot:
				idx = to_shoot.find(b)
				if pattern.symmetric:
					match pattern.symmetry_type:
						SYMTYPE.Line: _plan_queue([b], pattern.cooldown_shoot+(abs(pattern.center-idx))*pattern.cooldown_next_shoot)
						SYMTYPE.ClosedShape: _plan_queue([b], pattern.cooldown_shoot+(min(idx-pattern.center,to_shoot.size()-(idx-pattern.center)))*pattern.cooldown_next_shoot)
				else: _plan_queue([b], pattern.cooldown_shoot+idx*pattern.cooldown_next_shoot)
	else:
		var idx:int
		unactive_spawn(bullets)
		for b:Dictionary in to_shoot:
			idx = to_shoot.find(b)
			if pattern.symmetric:
				match pattern.symmetry_type:
					SYMTYPE.Line: _plan_queue([b], abs(pattern.center-idx)*pattern.cooldown_next_spawn)
					SYMTYPE.ClosedShape:
						_plan_queue([b], min(idx-pattern.center,to_shoot.size()-(idx-pattern.center))*pattern.cooldown_next_spawn)
			else: _plan_queue([b], idx*pattern.cooldown_next_spawn)

		if pattern.cooldown_stasis: return
		if pattern.cooldown_next_shoot == 0 and pattern.cooldown_shoot > 0:
			_plan_queue(to_shoot, pattern.cooldown_next_spawn*(to_shoot.size())+pattern.cooldown_shoot)
		elif pattern.cooldown_next_shoot == 0: #no add pos
			for b:Dictionary in to_shoot:
				idx = to_shoot.find(b)
				if pattern.symmetric:
					match pattern.symmetry_type:
						SYMTYPE.Line: _plan_queue([b], pattern.cooldown_shoot+(abs(pattern.center-idx))*pattern.cooldown_next_shoot)
						SYMTYPE.ClosedShape: _plan_queue([b], pattern.cooldown_shoot+(min(idx-pattern.center,to_shoot.size()-(idx-pattern.center)))*pattern.cooldown_next_shoot)
				else: _plan_queue([b], idx*pattern.cooldown_next_spawn)
		elif pattern.cooldown_shoot == 0:
			for b:Dictionary in to_shoot:
				idx = to_shoot.find(b)
				if pattern.symmetric:
					match pattern.symmetry_type:
						SYMTYPE.Line: _plan_queue([b], pattern.cooldown_shoot+(abs(pattern.center-idx))*pattern.cooldown_next_shoot)
						SYMTYPE.ClosedShape: _plan_queue([b], pattern.cooldown_shoot+(min(idx-pattern.center,to_shoot.size()-(idx-pattern.center)))*pattern.cooldown_next_shoot)
				else: _plan_queue([b], idx*(pattern.cooldown_next_shoot+pattern.cooldown_next_spawn))
		else:
			for b:Dictionary in to_shoot:
				idx = to_shoot.find(b)
				if pattern.symmetric:
					match pattern.symmetry_type:
						SYMTYPE.Line: _plan_queue([b], pattern.cooldown_shoot+(abs(pattern.center-idx))*pattern.cooldown_next_shoot)
						SYMTYPE.ClosedShape: _plan_queue([b], pattern.cooldown_shoot+(min(idx-pattern.center,to_shoot.size()-(idx-pattern.center)))*pattern.cooldown_next_shoot)
				else: _plan_queue([b], pattern.cooldown_next_spawn*(to_shoot.size())+pattern.cooldown_shoot+idx*pattern.cooldown_next_shoot)
	
	bullets.clear()

func _plan_queue(bullets:Array[Dictionary], spawn_delay:float=0):
	var insert_index:int = poolTimes.bsearch(time+spawn_delay, false)
	poolTimes.insert(insert_index, time+spawn_delay)
	poolQueue.insert(insert_index, bullets)

func unactive_spawn(bullets:Array[Dictionary]):
	for B:Dictionary in bullets:
		#assert(poolBullets.has(b))
		if B["state"] >= BState.Moving: continue
		if B["source_node"] is RID: B["position"] = B["spawn_pos"] + poolBullets[B["source_node"]]["position"]
		elif B["source_node"] is Dictionary: B["position"] = B["spawn_pos"] + B["source_node"]["position"]
		else: B["position"] = B["spawn_pos"] + B["source_node"].global_position # warning: no idea what this case is

func _spawn(bullets:Array[Dictionary]):
	var props:Dictionary; var b
	for B:Dictionary in bullets:
		b = B["RID"]
		if not poolBullets.has(b):
			push_error("Warning: Bullet of ID "+str(b)+" is missing.")
			continue
		
		if B["state"] >= BState.Moving: continue
		if B["source_node"] is Dictionary: B["position"] = B["spawn_pos"] + B["source_node"]["position"]
		elif not is_instance_valid(B["source_node"]):
			_interrupt_bullet(B)
			continue
		else: B["position"] = B["spawn_pos"] + B["source_node"].global_position
		
		if b is Node2D: # scene spawning
			_spawn_object(b, B)
		
		props = B["props"]
		if b is RID or props.has("speed"):
			if not change_animation(B,"spawn"):
				B["state"] = BState.Spawning
			else: B["state"] = BState.Spawned
			if arrayAnim[props["anim_spawn"]][ANIM.SFX]: arrayAnim[props["anim_spawn"]][ANIM.SFX].play()
			
			init_special_variables(B,b)
			if props.get("homing_select_in_group",-1) == GROUP_SELECT.Nearest_on_spawn:
				target_from_options(B)
		else:
			poolBullets.erase(b)

func _spawn_object(b:Node2D, B:Dictionary):
	if b is CollisionObject2D:
		b.collision_layer = B["shared_area"].collision_layer
		b.collision_mask = B["shared_area"].collision_mask
	if B["source_node"] is Dictionary:
		B["source_node"]["source_node"].call_deferred("add_child", b)
		b.global_position = B["source_node"]["position"]-B["source_node"]["source_node"].position
		b.rotation += B["source_node"]["rotation"]
	else:
		b.global_position = B["spawn_pos"]
		b.rotation += B["rotation"]
		B["source_node"].call_deferred("add_child", b)

func use_momentum(pos:Vector2, B:Dictionary):
	B["position"] = pos

func _shoot(bullets:Array[Dictionary], ignore_interrupt:bool=false):
	var props:Dictionary; var b
	for B:Dictionary in bullets:
		b = B["RID"]
		if not poolBullets.has(b): continue
		if B["state"] == BState.Moving: continue
		props = B["props"]
		#if (not b is RID and not props.has("speed")): # no idea why this exist, uncomment if issue
			#poolBullets.erase(b)
			##get_node("Drawers/"+str(props["z_index"])).bullets.erase(B)
			#continue
		if B.has("source_node") and not is_instance_valid(B["source_node"]):
			_interrupt_bullet(B)
			if not ignore_interrupt: continue

		if B.has("momentum_data"):
			var tween = get_tree().create_tween()
			tween.tween_method(use_momentum.bind(B), B["position"], B["momentum_data"][1], B["momentum_data"][2]).set_trans(B["momentum_data"][0])

		B["state"] = BState.Moving

		if B.get("follows_parent", 0) > LATENCE.No: B.erase("follows_parent")
		if not props.has("curve"): B.erase("spawn_pos")
		else: B["spawn_pos"] = B["position"]

		if props.has("homing_target") or props.has("node_homing"):
			if props.get("homing_time_start",0) > 0:
				get_tree().create_timer(props["homing_time_start"], false).connect("timeout",Callable(self,"_on_Homing_timeout").bind(B))
			else: _on_Homing_timeout(B)
		if props.get("homing_select_in_group",-1) == GROUP_SELECT.Nearest_on_shoot:
			target_from_options(B)

		if b is RID:
			if not change_animation(B,"shoot"): B["state"] = BState.Shooting
			if arrayAnim[props["anim_shoot"]][ANIM.SFX]: arrayAnim[props["anim_shoot"]][ANIM.SFX].play()

func init_special_variables(b:Dictionary, rid):
	var bp = b["props"]
	if bp.has("a_speed_multi_iterations"):
		b['speed_multi_iter'] = bp["a_speed_multi_iterations"]
		b['speed_interpolate'] = float(0)
	if bp.has("scale_multi_iterations"):
		b['scale_multi_iter'] = bp["scale_multi_iterations"]
		b['scale_interpolate'] = float(0)
	if bp.has("spec_bounces"):
		b['bounces'] = bp["spec_bounces"]
	if bp.has("a_direction_equation") or bp.has("a_angular_equation"):
		b['curve'] = float(0)
		b['curveDir_index'] = float(0)
	if bp.has("spec_modulate_loop"): b["modulate_index"] = float(0)
	if bp.has("spec_rotating_speed"): b["rot_index"] = float(0)
	if bp.has("spec_trail_length"):
		b["trail"] = [b["position"]]
		b["trail_counter"] = float(0.0)
	if bp.has("homing_list"):
		b["homing_counter"] = int(0)
	if bp.get("homing_imprecision", Vector2(0,0)) != Vector2(0,0):
		b["homing_offset"] = Vector2(randf_range(-bp["homing_imprecision"].x,bp["homing_imprecision"].x), \
									randf_range(-bp["homing_imprecision"].y,bp["homing_imprecision"].y))
	if bp.has("curve"):
		b["curve_counter"] = float(0.0)
		if bp["a_curve_movement"] in [CURVE_TYPE.LoopFromStart,CURVE_TYPE.LoopFromEnd]:
			b["curve_start"] = bp["curve"].get_point_position(0)
	if bp.has("death_after_time"): b["death_counter"] = float(0.0)
	if bp.has("trigger_container"):
		b['trig_container'] = container(bp["trigger_container"])
		b["trigger_counter"] = int(0)
		var trig_types = b['trig_container'].getCurrentTriggers(b, rid)
		b['trig_types'] = trig_types
		b['trig_iter'] = {}
		if trig_types.has("TrigCol"): b["trig_collider"] = null
#		if trig_types.has("TrigPos"): b["trig_collider"] = null
		if trig_types.has("TrigSig"): b["trig_signal"] = null
		if trig_types.has("TrigTime"): b["trig_timeout"] = false
	if bp.has("depth_active"):
		b["depth"] = bp["depth_spawn"]
		b["depth_speed"] = bp["depth_speed"]


func create_minimal_bullet(bp:Dictionary, pattern:Pattern):
	var b:Dictionary = {}
	b["speed"] = bp.speed
	b["vel"] = Vector2()
	if pattern.impulse > 0:
		b["impulse"] = pattern.impulse
		b["speed"] += pattern.impulse
	if Gravity != Vector2.ZERO:
		b["gravity"] = Gravity
		b["acc"] = Vector2.ZERO

	if bp.has("a_speed_multi_iterations"):
		b['speed_multi_iter'] = bp["a_speed_multi_iterations"]
	b['speed_interpolate'] = float(0)
	if bp.has("a_direction_equation") or bp.has("a_angular_equation"):
		b['curve'] = float(0)
	b['curveDir_index'] = float(0)
	if bp.has("curve"):
		if bp["a_curve_movement"] in [CURVE_TYPE.LoopFromStart,CURVE_TYPE.LoopFromEnd]:
			b["curve_start"] = bp["curve"].get_point_position(0)
	b["curve_counter"] = float(0.0)
	return b

func get_trajectory_preview(props:BulletProps, pattern:Pattern, length:int, delay:float, origin:Node2D):
	if props.homing_type == props.TARGET_TYPE.ListNodes or props.homing_target:
		push_warning("Can't preview homing bullets.")
		return

	var res:Array[Array]
	var p:Dictionary = sanitize_bulletprops(props, "", null)
	var baseB:Dictionary; var B:Dictionary;
	baseB = create_minimal_bullet(p, pattern)
	for j:int in pattern.nbr:
		res.append([])
		B = baseB.duplicate()
		set_spawn_data(B, p, pattern, j, origin.rotation, origin.global_position)
		B["position"] = B["spawn_pos"]
		if not p.get("fixed_rotation", false):
			set_angle(pattern, origin.global_position, B)
		else: B["rotation"] = 0

		for i:int in length+1:
			B["speed_interpolate"] = delay*i
			move_speed(B, p)
			#B['curveDir_index'] = delay*i*(B["speed"]/100)
			move_equation(B, p, delay*i)
			move_gravity(B, p, 0.016, i*delay)
			move_impulse(B, i*delay)
			B["curve_counter"] = delay*i
			if props.get("curve"): move_curve(B, p)
			else:
				B["vel"] = Vector2(B["speed"], B.get("curve",0)).rotated(B["rotation"])
				B["position"] += B["vel"]*0.016*i*delay
			res[j].append(B["position"])
	return res

func get_BulletPattern_with_id(id:String, check_node:Node = get_tree().edited_scene_root):
	for n:Node in check_node.get_children():
		if n is BulletPattern and n.id == id: return n
		for next:Node in n.get_children():
			var res = get_BulletPattern_with_id(id, n)
			if res != null: return res

func get_SpawnPattern_with_id(id:String, check_node:Node = get_tree().edited_scene_root):
	for n:Node in check_node.get_children():
		if n is SpawnPattern and n.id == id: return n
		for next:Node in n.get_children():
			var res = get_SpawnPattern_with_id(id, n)
			if res != null: return res

func get_TriggerContainer_with_id(id:String, check_node:Node = get_tree().edited_scene_root):
	for n:Node in check_node.get_children():
		if n is TriggerContainer and n.id == id: return n
		for next:Node in n.get_children():
			var res = get_TriggerContainer_with_id(id, n)
			if res != null: return res








#§§§§§§§§§§§§§ MOVEMENT §§§§§§§§§§§§§


func move_scale(B:Dictionary, props:Dictionary):
	if B.get("scale_multi_iter",0) == 0: return

	B["scale_interpolate"] += _delta
	var _scale = props["scale"] * props["scale_multiplier"].sample(B["scale_interpolate"]/props["scale_multi_scale"])
	B["scale"] = Vector2(_scale,_scale)
	if B["scale_interpolate"]/props["scale_multi_scale"] >= 1 and props["scale_multi_iterations"] != -1:
		B["scale_multi_iter"] -= 1

# Function written by UN3X. Thank you
func move_trail(B:Dictionary, props:Dictionary):
	if not B.has("trail_counter"): return
	var _trailTotalDurance:float = props["spec_trail_length"]/B["speed"]
	var _trailNumSegments:float = _trailTotalDurance / props["spec_trail_smooth"]

	B["trail_counter"] += _delta
	if B["trail_counter"] >= props["spec_trail_smooth"]:
		B["trail_counter"] = 0
		if B["trail"].size() >= _trailNumSegments:
			B["trail"].pop_back()
		B["trail"].insert(0, B["position"])

func move_speed(B:Dictionary, props:Dictionary):
	if B.get("speed_multi_iter",0) == 0: return

	B["speed_interpolate"] += _delta
	B["speed"] = props["a_speed_multiplier"].sample(B["speed_interpolate"]/props["a_speed_multi_scale"])
	if B["speed_interpolate"]/props["a_speed_multi_scale"] >= 1 and props["a_speed_multi_iterations"] != -1:
		B["speed_multi_iter"] -= 1
		B["speed_interpolate"] = 0

	if abs(B["speed"]) < props.get("death_speed_under", 0): delete_bullet(B)

func move_equation(B:Dictionary, props:Dictionary, eq_scale:float=1):
	if props.get("a_direction_equation","") == "" and props.get("a_angular_equation","") == "": return
	B["curveDir_index"] += eq_scale*B["speed"]/100

	if props.get("a_direction_equation","") != "":
		if expression.parse(props["a_direction_equation"],["x"]) != OK: push_error(expression.get_error_text())
		B["curve"] = float(expression.execute([B["curveDir_index"]*0.05]))*100*eq_scale*(B["speed"]/100)

	if props.get("a_angular_equation","") != "":
		if expression.parse(props["a_angular_equation"],["x"]) != OK: push_error(expression.get_error_text())
		B["rotation"] += float(expression.execute([B["curveDir_index"]/50]))/50*eq_scale*(B["speed"]/100)

func _homing_at_signal(B:Dictionary, props:Dictionary):
	# when homing starts with a signal
	if start_homing_group.is_empty() or not props.has("homing_start_signal"): return
	if B.get("homing_target", null) != null: return
	if not props["homing_start_signal"] in start_homing_group: return
	start_homing_group.erase(props["homing_start_signal"])
	_on_Homing_timeout(B)

func homing_next(B:Dictionary, props:Dictionary):
	if B["homing_counter"] < props["homing_list"].size()-1:
		B["homing_counter"] += 1
		target_from_list(B)
	else:
		match props.get("homing_when_list_ends"):
			LIST_ENDS.Loop: B["homing_counter"] = 0
			LIST_ENDS.Stop: stop_homing(B)
			LIST_ENDS.Reverse:
				B["homing_counter"] = 0
				props["homing_list"].reverse()

func move_homing(B:Dictionary, props:Dictionary):
	_homing_at_signal(B, props)
	if B.get("homing_target", null) == null: return
	#setup
	var target_pos:Vector2
	if typeof(B["homing_target"]) == TYPE_OBJECT:
		if not is_instance_valid(B["homing_target"]): return
		target_pos = B["homing_target"].global_position + B.get("homing_offset", Vector2(0,0))
	else: target_pos = B["homing_target"]
	# reaches target
	var dist_to_target:float = B["position"].distance_to(target_pos)
	if dist_to_target < props["homing_range"].y:
		if props.has("homing_list"):
			homing_next(B, props)
		else: stop_homing(B)
		return
	elif dist_to_target > props["homing_range"].x:
		stop_homing(B)
		return
	# if target needs to enter detection range to be targeted
	if props.has("homing_detection_dist"):
		if dist_to_target < props["homing_detection_dist"]:
			B["target_detected"] = true
		elif B.get("target_detected", true): return

	# trajectory calcul
	B["vel"] += ((target_pos-B["position"])*B["speed"]-B["vel"]).normalized() * props["homing_steer"] * _delta
	B["rotation"] = B["vel"].angle()

func move_curve(B:Dictionary, props:Dictionary):
	var curve_length:float = props["curve"].get_baked_length()
	if B["curve_counter"]*B["speed"] >= curve_length: return

	B["position"] = B["spawn_pos"]+(props["curve"].sample_baked(B["curve_counter"]*B["speed"])-B.get("curve_start", Vector2.ZERO)).rotated(B["rotation"])
	B["curve_counter"] += _delta

	if B["curve_counter"]*B["speed"] < curve_length: return
	match props["a_curve_movement"]:
		CURVE_TYPE.LoopFromStart: B["curve_counter"] = 0
		CURVE_TYPE.LoopFromEnd:
			B["curve_counter"] = 0
			B["spawn_pos"] = B["position"]
		CURVE_TYPE.OnceThenDie: delete_bullet(B)
		CURVE_TYPE.OnceThenStay:
			B["rotation"] = props["curve"].sample_baked_with_rotation(curve_length).get_rotation()
			B.erase("curve_counter")
		CURVE_TYPE.OnceThenStop: pass

func move_gravity(B:Dictionary, props:Dictionary, d:float=_delta, time_sample:float=1):
	if Gravity == Vector2.ZERO: return
	if B["acc"].y < MAX_ACC or B["acc"].x < MAX_ACC: B["acc"] += B["gravity"]*time_sample
	B["position"] += B["acc"]*props["spec_weight"]*d*time_sample

func move_impulse(B:Dictionary, time_sample:float=1):
	if not B.has("impulse"): return
	B["impulse"] -= 1*time_sample
	B["speed"] -= 1*time_sample
	if B["impulse"] <= 0: B.erase("impulse")

func move_depth(B:Dictionary, props:Dictionary):
	if not B.has("depth"): return
	B["depth"] += B["depth_speed"]*_delta

	if B["depth"] < props["depth_min_max"].x or B["depth"] > props["depth_min_max"].y:
		if props["depth_bounce"]: B["depth_speed"] = -B["depth_speed"]
		else: delete_bullet(B)

func _interrupt_bullet(B):
	match B["interruption"]:
		INTERRUPT.Continue: B.erase("follows_parent")
		INTERRUPT.Shoot: _shoot([B["RID"]])
		INTERRUPT.Destroy: delete_bullet(B)

func wait_behavior(B:Dictionary):
	var source = B["source_node"]
	if not source is Dictionary and not is_instance_valid(source):
		_interrupt_bullet(B)
		return

	if B.get("follows_parent", 0) == LATENCE.No: return
	var rot:float;
	if B["follows_parent"] == LATENCE.Rotation: rot = source.rotation
	#elif B["follows_parent"] == LATENCE.Spin:
		#B["rotation"] #TODO

	# follows position
	if B["follows_parent"] == LATENCE.PosOnly:
		if source is Dictionary: B["position"] = B["spawn_pos"] + source["position"]
		else: B["position"] = source.global_position + B["spawn_pos"]
	# follows rotation
	else:
		if source is Dictionary: B["position"] = B["spawn_pos"].rotated(rot) + source["position"]
		else: B["position"] = B["spawn_pos"].rotated(rot) + source.global_position

func _update_culling():
	can_cull = false
	_cull_rate += _delta
	if _cull_rate > cull_culling_rate:
		can_cull = true
		_cull_rate = 0

func bullet_movement(B:Dictionary, props:Dictionary):
	# handle bullet states
	if B["state"] == BState.Unactive: return false
	if B["state"] == BState.Deleting: return true
	if B["state"] == BState.QueuedFree:
		_apply_movement(B, props)
		return false

	# kill bullet after time
	if B.has("death_counter"):
		B["death_counter"] += _delta
		if B["death_counter"] >= props["death_after_time"]:
			delete_bullet(B)
			_apply_movement(B, props)
			return false
	# check for culling offscreen bullets
	if B["RID"] is RID and can_cull and check_bullet_culling(B) == CULLINGSTATES.Culled: return false
	# spin
	if B.has("rot_index"): B["rot_index"] += props["spec_rotating_speed"]

	#scale curve
	move_scale(B, props)

	if B["state"] == BState.Spawned: wait_behavior(B)
	elif B["state"] == BState.Moving:
		# trails
		move_trail(B, props)
		# speed curve
		move_speed(B, props)
		# direction from math equation
		move_equation(B, props)
		# homing
		move_homing(B, props)
		# gravity
		move_gravity(B, props)
		# impulse
		move_impulse(B)
		# depth
		move_depth(B, props)
		# follow path2D
		if B.has("curve_counter"): move_curve(B, props)
		else:
			B["vel"] = Vector2(B["speed"], B.get("curve",0)).rotated(B["rotation"])
			B["position"] += B["vel"]*_delta

		if B.has("spawn_pos") and not props.has("curve"): B["position"] += B["spawn_pos"]

	# position triggers
	if B.has("trig_container") and B["trig_types"].has("TrigPos") \
		and (B["state"] == BState.Moving or not props["trigger_wait_for_shot"]) \
		and not check_trig_culling(B):
			B["trig_container"].checkTriggers(B, B["RID"])

	# homing on nearest anywhen
	if props.get("homing_select_in_group",-1) == GROUP_SELECT.Nearest_anywhen:
		target_from_options(B)

	if not B["RID"] is RID: _apply_node_movement(B, B["RID"], props)
	else:
		detect_bullet_approaching(B)
		_apply_movement(B, props)
	return true

func _apply_node_movement(B:Dictionary, b, props:Dictionary):
	if b.base_scale == null: b.base_scale = b.scale
	# move object scene
	b.global_position = B["position"]
	b.rotation = B["rotation"]
	b.scale = b.base_scale * B.get("scale", Vector2(props["scale"], props["scale"]))

func _apply_movement(B:Dictionary, props:Dictionary):
	if B.get("state", BState.Unactive) == BState.Unactive or B.is_empty(): return
	if not B["RID"] is RID: return

	var shared_rid:RID = B["shared_area"].get_rid()
	var bullet_index:int = B["index"]
	if bullet_index == -1: return
	# erase destroyed bullets
	if B["state"] == BState.QueuedFree:
		Phys.area_set_shape_disabled(shared_rid, bullet_index, true)
		poolBullets.erase(B["RID"])
		if props["z_index"] != z_index: get_node("Drawers/"+str(props["z_index"])).bullets.erase(B)
		return
	# freeze offscreen bullets
	if B.get("Frozen", false) == false and B["culling_state"] in [CULLINGSTATES.Frozen, CULLINGSTATES.Fake]:
		Phys.area_set_shape_disabled(shared_rid, bullet_index, true)
		B["frozen"] = true
		return
	# unfreeze
	elif B["culling_state"] == CULLINGSTATES.UnFrozen:
		Phys.area_set_shape_disabled(shared_rid, bullet_index, false)
		B["culling_state"] = CULLINGSTATES.Onscreen
		B["frozen"] = false

	# move shapes
	if not props.get("spec_no_collision", false):
		var transform_rotation:float = B["rotation"]
		if props.has("no_rotation"):
			transform_rotation = 0
		elif not props.has("spec_spin_only_sprite"): transform_rotation += B.get("rot_index", 0)
		Phys.area_set_shape_transform(shared_rid, bullet_index, \
										Transform2D(transform_rotation, \
													B.get("scale",Vector2(props["scale"],props["scale"])), \
													props.get("skew",0), \
													B["position"]))

	if B["shape_disabled"]:
		if props.get("spec_no_collision", false): return
		# handles depths
		if B.has("depth"):
			var active:bool = (B["depth"] < props["depth_active"].x and B["depth"] > props["depth_active"].y)
			if B["shape_disabled"] and active: Phys.area_set_shape_disabled(shared_rid, B["index"], false)
			if not B["shape_disabled"] and not active: Phys.area_set_shape_disabled(shared_rid, B["index"], true)
			B["shape_disabled"] = !active
		# active collision for new bullets
		else:
			Phys.area_set_shape_disabled(shared_rid, B["index"], false)
			B["shape_disabled"] = false




#§§§§§§§§§§§§§ DRAW BULLETS §§§§§§§§§§§§§

func get_texture_frame(b:Dictionary, spriteframes:SpriteFrames=textures):
	if not b.has("anim_counter"): return spriteframes.get_frame_texture(b["anim"][ANIM.TEXTURE], 0)
	else:
		b["anim_counter"] += _delta
		if b["anim_counter"] >= 1/b["anim_speed"]:
			b["anim_counter"] = 0
			b["anim_frame"] += 1
			if b["anim_frame"] >= b["anim_length"]:
				if b["state"] == BState.Shooting:
					b["state"] = BState.Moving
					change_animation(b, "idle")
				elif b["state"] == BState.Spawning:
					b["state"] = BState.Spawned
					change_animation(b, "waiting")
					if change_animation(b, "waiting"):
						b["state"] = BState.Shooting
						if change_animation(b, "shoot"):
							change_animation(b, "idle")
				elif b["state"] == BState.Spawned:
					b["state"] = BState.Shooting
					change_animation(b, "shoot")
				elif b["state"] == BState.Deleting:
					back_to_grave(b["props"]["__ID__"], b)

				if b.get("anim_loop", true): b["anim_frame"] = 0
				else: b["anim_frame"] = b["anim_length"]-1
		return spriteframes.get_frame_texture(b["anim"][ANIM.TEXTURE], b.get("anim_frame"))

func modulate_bullet(b:Dictionary, texture:Texture, depth_scale:float=1):
	var draw_color = b["props"]["spec_modulate"]
	if b["props"].has("spec_modulate_loop"):
		draw_color = draw_color.sample(b["modulate_index"])
		b["modulate_index"] = b["modulate_index"]+(_delta/b["props"]["spec_modulate_loop"])
		if b["modulate_index"] >= 1: b["modulate_index"] = 0
	else: draw_color = draw_color.get_color(0)
	draw_color.a = depth_scale

	draw_texture(texture,-texture.get_size()/2,draw_color)

func _draw():
	if Engine.is_editor_hint(): return

	for drawer:Node2D in $Drawers.get_children():
		if drawer.name == str(z_index): continue
		drawer.queue_redraw()

	var props:Dictionary
	for B:Dictionary in poolBullets.values():
		props = B["props"]
		if not bullet_movement(B, props): continue
		_draw_bullet(B, props)

func draw_trail(B:Dictionary, props:Dictionary):
	var _alphaSteps:float = 0; var _widthSteps:float = 0; var segments:float = B["trail"].size(); var grad:bool = false
	var _originalModulate:Color = props["spec_trail_modulate"]
	var _originalTrailWidth:float = props["spec_trail_width"]
	if props.has("spec_trail_gradient"): grad = true
	if grad: _originalModulate = props.get("spec_trail_gradient").sample(0)

	draw_set_transform_matrix(Transform2D(0,B["position"]))
	draw_line(Vector2.ZERO, B["trail"][0]-B["position"], _originalModulate, _originalTrailWidth)

	if props.has("spec_trail_fade_out"): _alphaSteps = _originalModulate.a/segments
	if props.has("spec_trail_thin_out"): _widthSteps = _originalTrailWidth/segments

	for l:float in segments-1:
		if grad:
			_originalModulate = props.get("spec_trail_gradient").sample((1/segments)*(l+1))
		_originalModulate.a -= _alphaSteps
		_originalTrailWidth -= _widthSteps
		draw_line(B["trail"][l]-B["position"], B["trail"][l+1]-B["position"], _originalModulate, _originalTrailWidth)

func _draw_bullet(B:Dictionary, props:Dictionary):
	if props.get("z_index", z_index) != z_index: return
	if B.get("culling_state", CULLINGSTATES.Onscreen) > CULLINGSTATES.Onscreen and B.get("culling_state") != CULLINGSTATES.Fake:
		return
	# handles trails
	if B.has("trail"): draw_trail(B, props)

	var depth_scale:float = 1
	if B.has("depth"):# and (props["depth_scaling"] or props["depth_fading"]):
		if B["depth"] < props["depth_active"].x:
			depth_scale = 1-((props["depth_active"].x-B["depth"])/(props["depth_active"].x-props["depth_min_max"].x))
		elif B["depth"] > props["depth_active"].y:
			depth_scale = 1-((B["depth"]-props["depth_active"].y)/(props["depth_min_max"].y-props["depth_active"].y))

	# bullet nodes don't need to be drawn, they can use sprites
	if B["RID"] is Node2D:
		#if props.has("depth_scaling"): b.scale = props.get("depth_scaling")
		#if props.has("depth_fading"): b.modulate.a = props.get("depth_fading")
		#if props.has("speed"): B["RID"].queue_redraw() #todo
		return

	if (B["state"] < BState.Spawning) \
		or (props.has("spec_modulate") and props.has("spec_modulate_loop") and \
		props["spec_modulate"].get_color(0).a == 0):
			return

	var texture:Texture = get_texture_frame(B)
	var draw_rotation:float
	if props.has("no_rotation"): draw_rotation = 0
	else: draw_rotation = B["rotation"]+B.get("rot_index",0)
	draw_set_transform_matrix(Transform2D(draw_rotation, \
								B.get("scale", Vector2(props["scale"]*B["anim"][ANIM.SCALE], props["scale"]*B["anim"][ANIM.SCALE]))*depth_scale, \
								B["anim"][ANIM.SKEW], B["position"]))

	if props.has("spec_modulate"):
		modulate_bullet(B, texture, depth_scale)
	else: draw_texture(texture,-texture.get_size()/2, Color(1,1,1,depth_scale))

# type = "idle","spawn","waiting","delete"
func change_animation(b:Dictionary, type:String):
	#if B is Node2D: return true
	var instantly:bool = false
	var anim_state:Array
	if type in ["spawn","shoot","idle","waiting","delete"]:
		anim_state = arrayAnim.get(b["props"].get("anim_"+type, ""), [])
		if b["props"]["anim_"+type] == b["props"]["anim_idle"]:
			instantly = true
	else: anim_state = arrayAnim[type]

	var anim_id:String = anim_state[ANIM.TEXTURE]

	b["anim"] = anim_state
	var frame_count:int = textures.get_frame_count(anim_id)
	if frame_count > 1:
		b["anim_length"] = frame_count
		b["anim_counter"] = 0
		b["anim_frame"] = 0
		b["anim_loop"] = textures.get_animation_loop(anim_id)
		b["anim_speed"] = textures.get_animation_speed(anim_id)
	elif b.has("anim_frame"):
		b.erase("anim_length")
		b.erase("anim_counter")
		b.erase("anim_loop")
		b.erase("anim_speed")
		instantly = true

	var col_id:Array = anim_state[ANIM.COLLISION]
	if not col_id.is_empty() and col_id != b.get("colID", col_id):
		b["colID"] = col_id
		var shared:Area2D
		var new_rid:RID = create_shape(shared, b["colID"]) # TODO cause shape accumulation ?
		b["RID"] = new_rid
		poolBullets[new_rid] = b
		shared.get_meta("Bullets").erase(b["index"])
		shared.get_meta("Bullets")[shared.get_meta("ShapeCount")-1] = b
		b["index"] = shared.get_meta("ShapeCount")-1
		back_to_grave(b["props"]["__ID__"], b)

	return instantly






#§§§§§§§§§§§§§ USEFUL FUCNTIONS / API §§§§§§§§§§§§§


### BULLETS

func instant_shoot(bullets:Array):
	_shoot(bullets)

func rid_to_bullet(rid):
	return poolBullets[rid]

func get_RID_from_index(source_area:RID, index:int) -> RID:
	return Phys.area_get_shape(source_area, index)


## Gravity

func impulse(B:Dictionary, force:int=0, angle:float=-1):
	if force > 0: B["impulse"] = force
	if angle > -1: B["rotation"] = angle

func change_gravity(B:Dictionary, gravity:Vector2=Vector2.ZERO):
	if gravity == Vector2.ZERO:
		B.erase("gravity")
		B.erase("acc")
	B["gravity"] = gravity
	B["acc"] = Vector2.ZERO

## CLEAR

func clear_all_bullets():
	for b:Dictionary in poolBullets.values(): delete_bullet(b, true)

# target_pos radius group, group_whitelist random
func clear_bullets_advanced(filters:Dictionary, shadow_clearing:bool=false):
	for b:Dictionary in poolBullets.values():
		if not filter_bullet(b, filters): continue
		delete_bullet(b, shadow_clearing)

func clear_random_bullets(percent:int=50, shadow_clearing:bool=false):
	for b:Dictionary in poolBullets.values():
		if not randi()%100 < percent: continue
		delete_bullet(b, shadow_clearing)

# TODO counts radius or not
func clear_bullets_within_dist(target_pos, shadow_clearing:bool=false, radius:float=STANDARD_BULLET_RADIUS):
	for b:Dictionary in poolBullets.values():
		if not b["position"].distance_to(target_pos) < radius: continue
		delete_bullet(b, shadow_clearing)

func clear_all_offscreen_bullets():
	for b:Dictionary in poolBullets.values():
		if b.get("culling_state", CULLINGSTATES.Onscreen) == CULLINGSTATES.Onscreen: continue
		delete_bullet(b, true)

func clear_bullets_in_group(group:String, whitelist:bool=false, shadow_clearing:bool=false):
	if !whitelist:
		for b:Dictionary in poolBullets.values():
			if not group in b["groups"]: continue
			delete_bullet(b, shadow_clearing)
	else:
		for b:Dictionary in poolBullets.values():
			if group in b["groups"]: continue
			delete_bullet(b, shadow_clearing)

func clear_bullets_in_groups(groups:Array[String], whitelist:bool=false, shadow_clearing:bool=false):
	for g:String in groups: clear_bullets_in_group(g, whitelist, shadow_clearing)

func clear_bullet_queue():
	poolTimes.clear()
	poolQueue.clear()

func delete_bullet(B:Dictionary, shadow_clearing:bool=false):
	#if not poolBullets.has(b): return #todo
	if !shadow_clearing and arrayAnim[B["props"]["anim_delete"]][ANIM.SFX]:
		arrayAnim[B["props"]["anim_delete"]][ANIM.SFX].play()

	if shadow_clearing or change_animation(B, "delete"):
		back_to_grave(B["props"]["__ID__"], B)
	else: B["state"] = BState.Deleting

## GET

func get_bullets_in_radius(origin:Vector2, radius:float):
	var res:Array[Dictionary]
	for b:Dictionary in poolBullets.values():
		if not b["position"].distance_to(origin) < radius: continue
		res.append(b)
	return res

func filter_bullets(filters:Dictionary, list:Array[Dictionary]=poolBullets.values(), use_rid:bool=false):
	var res:Array[Dictionary]
	for B:Dictionary in list:
		if not filter_bullet(B, filters): continue
		if use_rid: res.append(B["RID"])
		else: res.append(B)
	return res

func filter_bullet(B:Dictionary, filters:Dictionary):
	# returns false if the filter isn't met
	if filters.has("shared_area") and B["shared_area"] != filters["shared_area"]: return false
	if filters.has("state") and B["state"] != filters["state"]: return false
	if filters.has("target_pos") and B["position"].distance_to(filters["target_pos"]) > filters["radius"]:
		return false
	if filters.has("group"):
		if filters["group"] in B["groups"] and filters.has("whitelist"): return false
	if filters.has("percent") and randi()%100 < filters["percent"]: return false
	if filters.has("offscreen") and (B["culling_state"] != CULLINGSTATES.Onscreen) != filters["offscreen"]: return false
	return true

func get_random_bullet():
	return poolBullets.values().pick_random()

func get_random_bullet_set(size:int):
	var res:Array[Dictionary]
	for i:int in size:
		res.append(get_random_bullet())
	return res

func get_all_bullets():
	return poolBullets.values()

func get_offscreen_bullets():
	var res:Array[Dictionary]
	for b:Dictionary in poolBullets.values():
		if b.get("culling_state", CULLINGSTATES.Onscreen) == CULLINGSTATES.Onscreen: continue
		res.append(b)
	return res

func get_bullets_in_shared_area(shared_area:String):
	return get_shared_area(shared_area).get_meta("Bullets")
	#var res:Array[Dictionary]
	#var area:Area2D = get_shared_area(shared_area)
	#for i:int in area.get_meta("ShapeCount",0):
		#res.append(poolBullets[Phys.area_get_shape(area.get_rid(), i)])
	#return res

## Bullet Properties ##

func change_bullet_speed(B:Dictionary, speed:float):
	B["speed"] = speed

func change_bullet_bounces(B:Dictionary, bounces:int):
	B["bounces"] = bounces

func change_bullet_imprecision(B:Dictionary, offset:Vector2):
	B["homing_offset"] = offset

func change_property(type:String, id:String, prop:String, new_value):
	var res = call(type, id)
	match type:
		"pattern","container","trigger": res.set(prop, new_value)
		"bullet": res[prop] = new_value

func switch_property_of_bullet(b:Dictionary, new_props_id:String):
	b["props"] = bullet(new_props_id)

func switch_property_of_all(replaceby_id:String, replaced_id:String="__ALL__"):
	for b:Dictionary in poolBullets.values():
		if not (replaced_id == "__ALL__" or b["props"].hash() == bullet(replaced_id).hash()): continue
		b["props"] = bullet(replaceby_id)

### GROUPS ###

func add_group_to_bullet(b:Dictionary, group:String):
	if b.has("groups"): b["groups"].append(group)
	else: b["groups"] = [group]

func remove_group_from_bullet(b:Dictionary, group:String):
	if not b.has("groups"): return
	b["groups"].erase(group)

func clear_groups_from_bullet(b:Dictionary):
	b.erase("groups")

func is_bullet_in_group(b:Dictionary, group:String):
	if not b.has("groups"): return false
	return b["groups"].has(group)

func is_bullet_in_grouptype(b:Dictionary, grouptype:String):
	if not b.has("groups"): return false
	for g:String in b["groups"]:
		if not grouptype in g: continue
		return true

### SHARED AREA ###

func create_shared_area(id:String, layers:int, masks:int):
	var new_area:Area2D = Area2D.new()
	new_area.name = id
	new_area.collision_layer = layers
	new_area.collision_mask = masks
	$SharedAreas.add_child(new_area, true)

func get_shared_area_rid(shared_area_name:String):
	return $SharedAreas.get_node(shared_area_name).get_rid()

func get_shared_area(shared_area_name:String):
	return $SharedAreas.get_node(shared_area_name)

func change_shared_area(B:Dictionary, new_area:Area2D):
	# remove from old area
	var old_area:Area2D = B["shared_area"]
	var index:int = B["index"]
	var count:int = old_area.get_meta("ShapeCount")
	var old_bullets:Dictionary = old_area.get_meta("Bullets")
	Phys.area_remove_shape(old_area.get_rid(), index)
	old_area.set_meta("ShapeCount", count-1)

	# update shape indexes in old area
	var Brid:RID
	for i:int in count-(index+1):
		Brid = get_RID_from_index(old_area.get_rid(), index+1+i)
		poolBullets[Brid]["index"] -= 1
		old_bullets[index+i] = old_bullets[index+i+1]
	old_bullets.erase(count)

	# add to new area
	Phys.area_add_shape(new_area.get_rid(), B["RID"])
	count = new_area.get_meta("ShapeCount")
	B["index"] = count
	new_area.set_meta("ShapeCount", count+1)
	B["shared_area"] = new_area
	new_area.get_meta("Bullets")[count] = B

### RANDOMISATION ###

func random_remove(id:String, prop:String):
	var res = bullet(id)
	res.remove_at(prop)

func random_change(type:String, id:String, prop:String, new_value):
	var res = call_deferred(type, id)
	match type:
		"pattern": res.set(prop,new_value)
		"bullet": res[prop] = new_value

func random_set(type:String, id:String, value:bool):
	var res = call_deferred(type, id)
	match type:
		"pattern": res.has_random = value
		"bullet": res["has_random"] = value

### Spawn Processes ###

func process_kill(process:int):
	assert(process != 0, "You set process to 0, which is forbidden")
	if process in process_stop:
		push_warning("process "+str(process)+" already queued for stopping.")
		return
	process_stop.append(process)

func process_kill_list(processes:Array[int]):
	for p:int in processes: process_kill(p)

func process_kill_all():
	process_stop_all = true

func pause_process(process:int):
	assert(process != 0, "You set process to 0, which is forbidden")
	if process in process_pause:
		push_warning("process "+str(process)+" already queued for pausing.")
		return
	process_pause.append(process)

func pause_process_list(processes:Array[int]):
	for p:int in processes: pause_process(p)

func pause_all_processes():
	process_pause_all = true

func process_get_infos(process:int):
	assert(process != 0, "You set process to 0, which is forbidden")
	while process_get != 0: continue
	process_infos.clear()
	process_get = process
	while process_infos.is_empty(): continue
	process_get = 0
	return process_infos

### HOMING ###

func edit_special_target(var_name:String, path:Node2D):
	set_meta("ST_"+var_name, path) # set path to null to remove_at meta variable

func get_special_target(var_name:String):
	return get_meta("ST_"+var_name)

func stop_homing(B:Dictionary):
	B["homing_target"] = null#Vector2()

func start_homing(group:String):
	start_homing_group.append(group)

func _on_Homing_timeout(B:Dictionary):
	var props = B["props"]
	if not props.has("homing_mouse"):
		if props.has("homing_target") or props.has("node_homing"): B["homing_target"] = props["node_homing"]
		else: B["homing_target"] = props["homing_position"]
	if props["homing_duration"] > 0:
		get_tree().create_timer(props["homing_duration"], false).connect("timeout",Callable(self,"stop_homing").bind(B))
	if props.get("homing_select_in_group",-1) == GROUP_SELECT.Nearest_on_homing:
		target_from_options(B)
	elif props.get("homing_select_in_group",-1) == GROUP_SELECT.Random:
		target_from_options(B,true)
	elif not B["props"].get("homing_list",[]).is_empty(): target_from_list(B)

	if B.has("homing_offset") and B["homing_target"] is Vector2:
		B["homing_target"] += B["homing_offset"]

func target_from_options(B:Dictionary, random:bool=false):
	if B["props"].has("homing_group"): target_from_group(B, random)
	elif B["props"].has("homing_surface"): target_from_segments(B, random)
	elif B["props"].has("homing_mouse"): B["homing_target"] = get_global_mouse_position()

func target_from_group(B:Dictionary, random:bool=false):
	var all_nodes:Array[Node] = get_tree().get_nodes_in_group(B["props"]["homing_group"])
	if random:
		B["homing_target"] = all_nodes[randi()%all_nodes.size()]
		return
	var res:Node2D; var smaller_dist = INF; var curr_dist;
	for node:Node in all_nodes:
		curr_dist = B["position"].distance_to(node.global_position)
		if curr_dist < smaller_dist:
			smaller_dist = curr_dist
			res = node
	B["homing_target"] = res

func target_from_segments(B:Dictionary, random:bool=false):
	var dist:float = INF; var res:Vector2; var new_res:Vector2; var new_dist:float
	for p:int in B["homing_surface"].size():
		new_res = Geometry2D.get_closest_point_to_segment(B["position"], B["homing_surface"][p], B["homing_surface"][(p+1)%B["homing_surface"].size()])
		new_dist = B["position"].distance_to(new_res)
		if new_dist < dist or (random and randi()%2 == 0):
			dist = new_dist
			res = new_res
	B["homing_target"] = res

func target_from_list(B:Dictionary, do:bool=true):
	if not do: return
	B["homing_target"] = B["props"]["homing_list"][B["homing_counter"]]

func trig_timeout(b):
	if b == null: return
	if b is Node: b.trigger_timeout = true
	else:
		if check_trig_culling(b): return
		b["trig_timeout"] = true
	b.get("trig_container").checkTriggers(b, b["RID"])










#§§§§§§§§§§§§§ COLLISIONS §§§§§§§§§§§§§

func laser_collide(col_pos:Vector2, collider:Node, normal:Vector2, full_length:float, laser:LaserBeam):
	call_custom("laser_collide", [col_pos, collider, normal, full_length, laser])

func bullet_collide_area(area_rid:RID,area:Area2D,area_shape_index:int,local_shape_index:int,shared_area:Area2D) -> void:
	############## go to CUSTOM if you want to implement custom behavior
	CUSTOM.bullet_collide_area(area_rid, area, area_shape_index, local_shape_index, shared_area)

func bullet_collide_body(body_rid:RID,body:Node,body_shape_index:int,local_shape_index:int,shared_area:Area2D) -> void:
	var B:Dictionary
	if shared_area.get_parent() == $SharedAreas:
		B = shared_area.get_meta("Bullets")[local_shape_index]
	else: B = poolBullets[shared_area]

	############## go to CUSTOM if you want to implement custom behavior
	CUSTOM.bullet_collide_body(body_rid, body, body_shape_index, local_shape_index, shared_area, B)

	bullet_collided_body.emit(body, body_shape_index, B, local_shape_index, shared_area)

	if B.get("trig_types", []).has("TrigCol"):
		B["trig_collider"] = body
		B["trig_container"].checkTriggers(B, B["RID"])

	if Gravity != Vector2.ZERO: B["acc"] = Vector2.ZERO

	if B.get("bounces",0) != 0:
		bounce(B, shared_area)
		return
	else:
		for group:String in GROUP_BOUNCE:
			if not body.is_in_group(group): continue
			bounce(B, shared_area)
			return

	if body.is_in_group("Player"):
		delete_bullet(B)
	elif B["props"]["death_from_collision"]:
		delete_bullet(B)


var bounce_index:int = 0
var bounce_queue:Array = []
func bounce(B:Dictionary, shared_area:Area2D):
	#if not B["RID"] is RID: return #TODO support custom bullet nodes
	bounce_queue.append([B, shared_area, 0])

func _process_bounce(B:Dictionary, shared_area:Area2D, tries:int=0):
	var bouncy_node:CharacterBody2D = get_node("Bouncy/" + str(bounce_index))
	var bouncy_shape:CollisionShape2D = bouncy_node.get_node("CollisionShape2D")
	
	if B["RID"] is RID: bouncy_shape.shape = B["colID"][0]
	# if this fails, it's because you BulletNode doesn't have a CollisionShape2D named CollisionShape2D,
	# which is required to handle bounces
	else: bouncy_shape.shape = shared_area.get_node("CollisionShape2D").shape
		
	bouncy_node.collision_layer = shared_area.collision_layer
	bouncy_node.collision_mask = shared_area.collision_mask
	bouncy_node.global_position = B["position"]
	
	var current_index:int = bounce_index
	bounce_index = (bounce_index+1)%$Bouncy.get_child_count()
	_handle_bounce_collision(B, current_index, shared_area)

func _handle_bounce_collision(B:Dictionary, index:int, shared_area:Area2D, tries:int=0):
	var bouncy_node:CharacterBody2D = get_node("Bouncy/" + str(index))
	var collision:KinematicCollision2D = bouncy_node.move_and_collide(Vector2(0,0), true)

	if collision:
		B["vel"] = B["vel"].bounce(collision.get_normal())
		B["rotation"] = B["vel"].angle()
		B["bounces"] = B["bounces"]-1
	elif tries < 5: bounce_queue.append([B, shared_area, tries])

	bouncy_node.get_node("CollisionShape2D").shape = null
	bouncy_node.global_position = UNACTIVE_ZONE

func reset_bounce():
	for i:CharacterBody2D in $Bouncy.get_children(): i.global_position = UNACTIVE_ZONE





#§§§§§§§§§§§§§ CULLING §§§§§§§§§§§§§

func update_viewport():
	_viewport_refresher = 0
	#if cull_fixed_screen: return
	var c_trans:Transform2D = get_canvas_transform()
	viewrect = Rect2(-c_trans.get_origin()/c_trans.get_scale(), get_viewport_rect().size/c_trans.get_scale()).grow(cull_margin)

func detect_offscreen_bullet(bullet:Dictionary) -> bool:
	return not viewrect.has_point(bullet["position"])

func detect_bullet_approaching(bullet:Dictionary):
	if not (int(cull_faking_dist) > 0 and int(cull_unfaking_dist)): return false
	if not bullet["culling_state"] in [CULLINGSTATES.Onscreen, CULLINGSTATES.Fake]: return false
	if interest_list.is_empty(): return false

	var dist:float; var faraway_counter:int = 0
	for node:Node in interest_list:
		if not is_instance_valid(node): continue
		dist = bullet["position"].distance_to(node.global_position)
		if dist > cull_faking_dist: faraway_counter += 1
		elif bullet["culling_state"] == CULLINGSTATES.Fake and dist < cull_unfaking_dist:
			bullet["culling_state"] = CULLINGSTATES.UnFrozen
			return true
	if faraway_counter == interest_list.size():
		bullet["culling_state"] = CULLINGSTATES.Fake
	return false

func check_bullet_culling(B:Dictionary):
	var bcull:int = B["props"].get("death_culling_overwrite", CULLINGLVL.Full)
	var offscreen:bool = detect_offscreen_bullet(B)
	if not offscreen:
		if B["culling_state"] == CULLINGSTATES.Frozen:
			B["culling_state"] = CULLINGSTATES.UnFrozen
			return CULLINGSTATES.UnFrozen
		return CULLINGSTATES.Onscreen

	if bcull == CULLINGLVL.Inherit: B["culling_state"] = cull_technique
	else: B["culling_state"] = bcull
	if B["culling_state"] == CULLINGLVL.Full:
		delete_bullet(B, true)
		return CULLINGSTATES.Culled
	return B["culling_state"]

func check_trig_culling(B:Dictionary):
	if cull_trigger == false or B["props"].get("death_culling_overwrite", CULLINGLVL.Full) > CULLINGLVL.Anim:
		return false
	return detect_offscreen_bullet(B)






#§§§§§§§§§§§§§ RANDOMISATION §§§§§§§§§§§§§

func random_get_chances(target_value:float):
	return randf_range(0,1) < target_value

func random_get_choice(choice:Array):
	return choice[randi()%choice.size()]

# call : random_get_variation(base_prop value, v.x, v.y, v.z)
func random_get_variation(mean:float, variance:float, limit_down=0, limit_up=0):
	if limit_down != 0 and limit_up != 0:
		return min(max(RAND.randfn(mean,variance),limit_down), limit_up)
	elif limit_down != 0: return max(RAND.randfn(mean,variance),limit_down)
	elif limit_up != 0: return min(RAND.randfn(mean,variance),limit_up)
	else: return RAND.randfn(mean,variance)

func reroll(pattern:Pattern, prop:String, curr_value):
	if not pattern.random.get(prop+"_reroll"): return curr_value
	return r_get(pattern, prop)

func r_get(pattern:Pattern, prop:String):
	var res = pattern.get(prop)
	#if prop in ["offset_x", "offset_y"]: res = pattern.get("offset")
	if res == null: return 0
	var random_prop = pattern.random.get(prop+"_chances")
	# test if prop has a random chance of happening
	if random_prop and int(random_prop) > 0:
		res = random_get_chances(random_prop)
		return res
	# if available, pick a value from set of choices
	random_prop = pattern.random.get(prop+"_choice")
	if random_prop and not random_prop.is_empty():
		res = random_get_choice(random_prop)
	# if available, tweak the value
	random_prop = pattern.random.get(prop+"_variation")

	if random_prop and random_prop != Vector3():
		res = random_get_variation(res, random_prop.x, random_prop.y, random_prop.z)
	# returns final result
	if res == null: return 0
	return res



func create_random_props(original:Dictionary) -> Dictionary:
	var r_name:String; var res:Dictionary;
	var choice:Array; var variation:Vector3;

	for p:String in original.keys():
		r_name = match_rand_prop(p)
		if original.has(r_name+"_choice"):
			choice = original[r_name+"_choice"]
			variation = original.get(r_name+"_variation",Vector3(0,0,0))
			res[p] = random_get_variation(choice[randi()%choice.size()],variation.x,variation.y,variation.z)
		elif original.has(r_name+"_variation"):
			variation = original.get(r_name+"_variation",Vector3(0,0,0))
			res[p] = random_get_variation(original[p],variation.x,variation.y,variation.z)
		elif original.has(r_name+"_chance"):
			pass#res[p] = random_get_chances()
		else: res[p] = original.get(p)
	return res


func match_rand_prop(original:String) -> String:
	match original:
		"speed": return "r_speed"
		"scale": return "r_scale"
		"angle": return "r_angle"
		"groups": return "r_groups"
		"death_after_time": return "r_death_after"
		"anim_idle_texture": return "r_" #-----------------------
		"a_direction_equation": return "r_dir_equation"
		"curve": return "r_curve"
		"a_speed_multiplier": return "r_speed_multi_curve"
		"a_speed_multi_iterations": return "r_speed_multi_iter"
		"spec_bounces": return "r_bounce"
		"spec_modulate": return "r_modulate"
		"spec_rotating_speed": return "r_rotating"
		"trigger_container": return "r_trigger"
		"homing_target": return "r_homing_target"
		"homing_special_target": return "r_special_target"
		"homing_group": return "r_group_target"
		"homing_position": return "r_pos_target"
		"homing_steer": return "r_steer"
		"homing_duration": return "r_homing_dur"
		"homing_time_start": return "r_homing_delay"
		"scale_multiplier": return "r_scale_multi_curve"
		"scale_multi_iterations": return "r_scale_multi_iter"
		"": return "r_"
	return ""


############# random version of spawn functions #############

func _spawn_random(spawner, id:String, pattern:Pattern, shared_area:String="0", process_id:int=-1):
	var local_reset_counter:int = global_reset_counter
	var bullets:Array[Dictionary]
	var iter:int = r_get(pattern, "iterations"); var iter_nbr:int = 0
	var shared_area_node = $SharedAreas.get_node(shared_area)

	var pos:Vector2; var ori_angle:float; var is_object:bool; var is_bullet_node:bool
	var bullet_props:Dictionary; var queued_instance:Dictionary; var bID; var new_shape

	var r_props_id:String = r_get(pattern, "bullet"); var r_nbr:int = r_get(pattern, "nbr");
	var r_center:int = r_get(pattern, "center"); var r_cooldown:float = r_get(pattern, "cooldown_spawn");
	var r_angle:float = r_get(pattern, "forced_angle"); var r_radius:float = r_get(pattern, "radius");
	var r_angle_total:float = r_get(pattern, "angle_total"); var r_angle_decal:float = r_get(pattern, "angle_decal");
	var r_offx:float = r_get(pattern, "offset_x"); var r_offy:float = r_get(pattern, "offset_y");
	var r_sym:bool = r_get(pattern, "symmetry"); var r_cd_sh:float = r_get(pattern, "cooldown_shoot");
	var r_cd_n_sh:float = r_get(pattern, "cooldown_next_shoot"); var r_cd_n_sp:float = r_get(pattern, "cooldown_next_spawn");

	while iter != 0:
		if _stop_spawn(process_id, spawner, local_reset_counter): return
		if spawner is Node2D:
			ori_angle = spawner.rotation
			pos = spawner.global_position
		elif spawner is Dictionary:
			pos = spawner["position"]
			ori_angle = spawner["rotation"]
		else: push_error("spawner isn't a Node2D or a bullet RID")

		r_props_id = reroll(pattern, "bullet", r_props_id)
		r_nbr = reroll(pattern, "nbr", r_nbr)
		r_center = reroll(pattern, "center", r_center)
		r_cooldown = reroll(pattern, "cooldown_spawn", r_cooldown)
		r_cd_sh = reroll(pattern, "cooldown_shoot", r_cd_sh)
		r_cd_n_sp = reroll(pattern, "cooldown_next_spawn", r_cd_n_sp)
		r_cd_n_sh = reroll(pattern, "cooldown_next_shoot", r_cd_n_sh)
		r_angle = reroll(pattern, "angle", r_angle)
		r_radius = reroll(pattern, "radius", r_radius)
		r_angle_total = reroll(pattern, "angle_total", r_angle_total)
		r_angle_decal = reroll(pattern, "angle_decal", r_angle_decal)
		r_offx = reroll(pattern, "offset_x", r_offx)
		r_offy = reroll(pattern, "offset_y", r_offy)

		bullet_props = arrayProps[r_props_id]
		if bullet_props.get("has_random",false): bullet_props = create_random_props(bullet_props)

		is_object = bullet_props.has("instance_id")
		is_bullet_node = (is_object and bullet_props.has("speed"))
		for i:int in r_nbr:
			queued_instance = {}
			queued_instance["shared_area"] = shared_area_node
			queued_instance["props"] = bullet_props
			queued_instance["source_node"] = spawner
			queued_instance["state"] = BState.Unactive
			new_shape = wake_from_pool(r_props_id, queued_instance, shared_area, is_object)
			bID = new_shape
			if not is_object:
				bID = new_shape[0]
				queued_instance["index"] = new_shape[2]
				queued_instance["anim"] = arrayAnim[bullet_props["anim_idle"]]
				queued_instance["culling_state"] = CULLINGSTATES.Onscreen
				queued_instance["colID"] = queued_instance["anim"][ANIM.COLLISION]#bullet_props["first_collision"]
				queued_instance = create_bullet_instance_dict_random(queued_instance, bullet_props, pattern)
				if bullet_props["z_index"] != z_index: get_node("Drawers/"+str(bullet_props["z_index"])).bullets.append(queued_instance)
				shared_area_node.get_meta("Bullets")[new_shape[2]] = queued_instance
			elif is_bullet_node: queued_instance = create_bullet_instance_dict_random(queued_instance, bullet_props, pattern)

			set_spawn_data_random(r_nbr, r_center, queued_instance, bullet_props, pattern, i, ori_angle, \
									r_angle, r_radius, r_angle_total, r_angle_decal, r_offx, r_offy)

			if not bullet_props.get("fixed_rotation", false):
				set_angle(pattern, pos, queued_instance)
			else: queued_instance["rotation"] = 0

			if pattern.wait_tween_momentum > 0:
				var tw_endpos = queued_instance["spawn_pos"]+pos+Vector2(pattern.wait_tween_length, 0).rotated(PI+queued_instance["rotation"])
				queued_instance["momentum_data"] = [pattern.wait_tween_momentum-1, tw_endpos, pattern.wait_tween_time]

			queued_instance["RID"] = bID
			bullets.append(queued_instance)
			poolBullets[bID] = queued_instance

			if is_object:
				if is_bullet_node: bID.b = queued_instance

				if bullet_props.has("overwrite_groups"):
					for g:String in bID.get_groups():
						bID.remove_group(g)
				for g:String in bullet_props.get("groups", []):
					bID.add_to_group(g)

		_plan_spawning_random(r_center, pattern, bullets, r_sym, r_cd_sh, r_cd_n_sh, r_cd_n_sp)

		if iter > 0: iter -= 1
		iter_nbr += 1
		if pattern.max_layer > 0:
			for v:Vector2 in pattern.cooldown_layers:
				if iter_nbr%pattern.max_layer == v.x:
					await get_tree().create_timer(v.y, false, true).timeout
					break
				elif iter_nbr < v.x: break
		await get_tree().create_timer(r_cooldown, false, true).timeout
		#if local_reset_counter != global_reset_counter: return
		if process_get == process_id: process_infos = [spawner, pattern, id, bullet_props]

func set_angle_random(pattern:Pattern, pos:Vector2, queued_instance:Dictionary):
	if r_get(pattern, "forced_target") != NodePath():
		if pattern.forced_pattern_lookat: queued_instance["rotation"] = pos.angle_to_point(pattern.node_target.global_position)
		else: queued_instance["rotation"] = (pattern.node_target.global_position-queued_instance["spawn_pos"]).angle()
	elif pattern.forced_lookat_mouse:
		if pattern.forced_pattern_lookat: queued_instance["rotation"] = pos.angle_to_point(get_global_mouse_position())
		else: queued_instance["rotation"] = (pos+queued_instance["spawn_pos"]).angle_to_point(get_global_mouse_position())
	elif r_get(pattern, "forced_angle") != 0.0:
		queued_instance["rotation"] = r_get(pattern, "forced_angle")

func create_bullet_instance_dict_random(queued_instance:Dictionary, bullet_props:Dictionary, pattern:Pattern):
	queued_instance["shape_disabled"] = true
	#if r_props_id in no_culling_for: queued_instance["no_culling"] = true
	queued_instance["speed"] = bullet_props.speed
	queued_instance["vel"] = Vector2()
	if bullet_props.has("groups"): queued_instance["groups"] = bullet_props.get("groups")
	if pattern.wait_behavior > LATENCE.No: queued_instance["follows_parent"] = pattern.wait_behavior
	return queued_instance

func set_spawn_data_random(r_nbr:int, r_center:int, queued_instance:Dictionary, bullet_props:Dictionary, \
							pattern:Pattern, i:int, ori_angle:float, r_angle:float, r_radius:float, \
							r_angle_total:float, r_angle_decal:float, r_offx:float, r_offy:float):
	var angle:float
	#var r_angle:float = r_get(pattern, "pattern_angle")
	match pattern.resource_name:
		"PatternCircle":
			#var r_radius:float = r_get(pattern, "radius")
			angle = get_spawn_angle_circle(r_angle_total, r_angle_decal, r_nbr-int(r_angle_total < 2*PI), i)
			#angle = (r_angle_total/r_nbr)*i + r_angle_decal
			queued_instance["spawn_pos"] = get_spawn_pos_circle(angle, r_angle, r_radius)
			queued_instance["rotation"] = angle + bullet_props.angle + ori_angle
		"PatternLine":
			#var r_offx:float = r_get(pattern, "offset_x")
			#var r_offy:float = r_get(pattern, "offset_y")
			queued_instance["spawn_pos"] = get_spawn_pos_line(Vector2(r_offx, r_offy), r_center, r_angle, r_nbr, i)
			queued_instance["rotation"] = bullet_props.angle + r_angle + ori_angle
		"PatternOne":
			queued_instance["spawn_pos"] = Vector2()
			queued_instance["rotation"] = bullet_props.angle + ori_angle
		"PatternCustomShape","PatternCustomPoints":
			queued_instance["spawn_pos"] = pattern.pos[i]
			queued_instance["rotation"] = bullet_props.angle + pattern.angles[i] + ori_angle
		"PatternCustomArea":
			queued_instance["spawn_pos"] = pattern.pos[randi()%pattern.pooling][i]
			queued_instance["rotation"] = bullet_props.angle + ori_angle

#r_get(pattern, "")
func _plan_spawning_random(r_center:int, pattern:Pattern, bullets:Array[Dictionary], \
							r_sym:bool, r_cd_sh:float, r_cd_n_sh:float, r_cd_n_sp:float):
	var to_shoot:Array[Dictionary] = bullets.duplicate()
	if r_cd_n_sp == 0:
		_spawn(bullets)
		if pattern.cooldown_stasis: return
		if r_cd_n_sh == 0:
			if r_cd_sh == 0: _shoot(to_shoot) #no add pos
			else: _plan_queue(to_shoot, r_cd_sh)
		else:
			var idx:int
			for b:Dictionary in to_shoot:
				idx = to_shoot.find(b)
				if r_sym:
					match pattern.symmetry_type:
						SYMTYPE.Line: _plan_queue([b], r_cd_sh+(abs(r_center-idx))*r_cd_n_sh)
						SYMTYPE.ClosedShape: _plan_queue([b], r_cd_sh+(min(idx-r_center,to_shoot.size()-(idx-r_center)))*r_cd_n_sh)
				else: _plan_queue([b], r_cd_sh+idx*r_cd_n_sh)
	else:
		var idx:int
		unactive_spawn(bullets)
		for b:Dictionary in to_shoot:
			idx = to_shoot.find(b)
			if r_sym:
				match pattern.symmetry_type:
					SYMTYPE.Line: _plan_queue([b], abs(r_center-idx)*r_cd_n_sp)
					SYMTYPE.ClosedShape:
						_plan_queue([b], min(idx-r_center,to_shoot.size()-(idx-r_center))*r_cd_n_sp)
			else: _plan_queue([b], idx*r_cd_n_sp)
		
		if pattern.cooldown_stasis: return
		if r_cd_n_sh == 0 and r_cd_sh > 0:
			_plan_queue(to_shoot, r_cd_n_sp*(to_shoot.size())+r_cd_sh)
		elif r_cd_n_sh == 0: #no add pos
			for b:Dictionary in to_shoot:
				idx = to_shoot.find(b)
				if r_sym:
					match pattern.symmetry_type:
						SYMTYPE.Line: _plan_queue([b], r_cd_sh+(abs(r_center-idx))*r_cd_n_sh)
						SYMTYPE.ClosedShape: _plan_queue([b], r_cd_sh+(min(idx-r_center,to_shoot.size()-(idx-r_center)))*r_cd_n_sh)
				else: _plan_queue([b], idx*r_cd_n_sp)
		elif r_cd_sh == 0:
			for b:Dictionary in to_shoot:
				idx = to_shoot.find(b)
				if r_sym:
					match pattern.symmetry_type:
						SYMTYPE.Line: _plan_queue([b], r_cd_sh+(abs(r_center-idx))*r_cd_n_sh)
						SYMTYPE.ClosedShape: _plan_queue([b], r_cd_sh+(min(idx-r_center,to_shoot.size()-(idx-r_center)))*r_cd_n_sh)
				else: _plan_queue([b], idx*(r_cd_n_sh+r_cd_n_sp))
		else:
			for b:Dictionary in to_shoot:
				idx = to_shoot.find(b)
				if r_sym:
					match pattern.symmetry_type:
						SYMTYPE.Line: _plan_queue([b], r_cd_sh+(abs(r_center-idx))*r_cd_n_sh)
						SYMTYPE.ClosedShape: _plan_queue([b], r_cd_sh+(min(idx-r_center,to_shoot.size()-(idx-r_center)))*r_cd_n_sh)
				else: _plan_queue([b], r_cd_n_sp*(to_shoot.size())+r_cd_sh+idx*r_cd_n_sh)
	
	bullets.clear()

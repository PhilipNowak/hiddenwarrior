extends Node2D

enum ANIM{TEXTURE, COLLISION, SFX, SCALE, SKEW}
enum CULLINGSTATES {Onscreen=-1, Invisible=0, Frozen=1, UnFrozen=-2, Culled=2, Fake=3}
enum BState{Unactive, Spawning, Spawned, Shooting, Moving, Deleting, QueuedFree}

var bullets:Array

func _draw() -> void:
	for B:Dictionary in bullets:
		_draw_bullet(B, B["props"])


func _draw_bullet(B:Dictionary, props:Dictionary):
	if B.get("culling_state", CULLINGSTATES.Onscreen) > CULLINGSTATES.Onscreen and B.get("culling_state") != CULLINGSTATES.Fake:
		return
	# handles trails
	if B.has("trail"): draw_trail(B, props)
	
	var depth_scale:float = 1
	if B.has("depth"):
		if B["depth"] < props["depth_active"].x:
			depth_scale = 1-((props["depth_active"].x-B["depth"])/(props["depth_active"].x-props["depth_min_max"].x))
		elif B["depth"] > props["depth_active"].y:
			depth_scale = 1-((B["depth"]-props["depth_active"].y)/(props["depth_min_max"].y-props["depth_active"].y))
	
	if (B["state"] < BState.Spawning) \
		or (props.has("spec_modulate") and props.has("spec_modulate_loop") and \
		props["spec_modulate"].get_color(0).a == 0):
			return
	
	var texture:Texture = Spawning.get_texture_frame(B)
	var draw_rotation:float
	if props.has("no_rotation"): draw_rotation = 0
	else: draw_rotation = B["rotation"]+B.get("rot_index",0)
	draw_set_transform_matrix(Transform2D(draw_rotation, \
								B.get("scale", Vector2(props["scale"]*B["anim"][ANIM.SCALE], props["scale"]*B["anim"][ANIM.SCALE]))*depth_scale, \
								B["anim"][ANIM.SKEW], B["position"]))
	
	if props.has("spec_modulate"):
		modulate_bullet(B, texture, depth_scale)
	else: draw_texture(texture,-texture.get_size()/2, Color(1,1,1,depth_scale))


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


func modulate_bullet(b:Dictionary, texture:Texture, depth_scale:float=1):
	var draw_color = b["props"]["spec_modulate"]
	if b["props"].has("spec_modulate_loop"):
		draw_color = draw_color.sample(b["modulate_index"])
		b["modulate_index"] = b["modulate_index"]+(Spawning._delta/b["props"]["spec_modulate_loop"])
		if b["modulate_index"] >= 1: b["modulate_index"] = 0
	else: draw_color = draw_color.get_color(0)
	draw_color.a = depth_scale
	
	draw_texture(texture,-texture.get_size()/2,draw_color)

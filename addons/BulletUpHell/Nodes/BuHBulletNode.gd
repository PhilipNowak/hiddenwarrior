extends Area2D

@export_placeholder("ID") var ID:String
@export var ignore_children:Array[String] = []

var textures:Array[Dictionary]
var b:Dictionary;

var base_scale:Vector2


func _draw():
	var texture:Texture2D
	for entry:Dictionary in textures:
		if not entry["enabled"]: continue
		draw_set_transform_matrix(Transform2D(entry["rotation"]+self.global_rotation, entry["scale"]+self.scale, \
												entry["skew"]+self.skew, self.global_position))
		
		texture = Spawning.get_texture_frame(b, entry["texture"])
		if b["props"].has("spec_modulate"):
			Spawning.modulate_bullet(b, texture)
		else: draw_texture(texture, entry["position"], entry["modulate"])

func other_area_shape_entered(area_rid:RID, area:Area2D, area_shape_index:int, local_shape_index:int):
	area_shape_entered.emit(area_rid, area, area_shape_index, local_shape_index)
	
func other_body_shape_entered(body_rid:RID, body:Area2D, body_shape_index:int, local_shape_index:int):
	body_shape_entered.emit(body_rid, body, body_shape_index, local_shape_index)

func _ready():
	if ID == "": push_warning("ID missing in node "+String(get_path()))
	name = ID
	
	for child:Node in get_children():
		if child.name in ignore_children: continue
		
		if child is AnimatedSprite2D:
			var entry:Dictionary
			entry["enabled"] = child.visible
			entry["position"] = child.position + child.offset
			entry["rotation"] = child.rotation
			entry["scale"] = child.scale
			entry["skew"] = child.skew
			entry["texture"] = child.sprite_frames
			if child.flip_h == true or child.flip_v == true:
				push_warning("Use negative scale to flip a BulletNode's sprite, not flip_h or flip_v")
			entry["modulate"] = child.modulate
			textures.append(entry)
	
	area_shape_entered.connect(Spawning.bullet_collide_area.bind(self))
	body_shape_entered.connect(Spawning.bullet_collide_body.bind(self))
	
	base_scale = scale
	

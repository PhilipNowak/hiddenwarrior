extends Node
class_name customFunctions

###
## here, you can write custom logic to attach to BuHSpawner.gd
## just create a function, and call then call it from BuHSpawner.gd using CUSTOM.<yourfunction>
## it is better than writing custom logic in BuHSpawner.gd
## because your code would be overwritten at each plugin update
###



func laser_collide(col_pos:Vector2, collider:Node, normal:Vector2, full_length:float, laser:LaserBeam):
	## you can add custom properties to a laser by using metadata
	pass

func bullet_collide_body(body_rid:RID,body:Node,body_shape_index:int,local_shape_index:int,shared_area:Area2D, B:Dictionary) -> void:
	## you can use B["props"]["damage"] to get the bullet's damage
	## you can use B["RID"] to get the bullet's RID
	## you can use B["props"]["<your custom data name>"] to get the bullet's custom data
	
	pass


func bullet_collide_area(area_rid:RID,area:Area2D,area_shape_index:int,local_shape_index:int,shared_area:Area2D) -> void:
	############## uncomment if you want to use the standard behavior below ##############
	## you can use B["props"]["damage"] to get the bullet's damage
	## you can use B["RID"] to get the bullet's RID
	## you can use B["props"]["<your custom data name>"] to get the bullet's custom data
	#var B:Dictionary
	#if shared_area.get_parent() == $SharedAreas:
		#B = shared_area.get_meta("Bullets")[local_shape_index]
	#else: B = poolBullets[shared_area]
	
	############## emit signal
#	Spawning.bullet_collided_area.emit(area,area_shape_index,B,local_shape_index,shared_area)
	
	############## uncomment to manage trigger collisions with area collisions
#	if B["trig_types"].has("TrigCol"):
#		B["trig_collider"] = area
#		B["trig_container"].checkTriggers(B)
	pass

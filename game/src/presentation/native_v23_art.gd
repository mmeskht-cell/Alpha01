extends RefCounted
## Replaceable provisional art profile. Public geometry only. No game commands.
const Clock=preload("res://src/domain/business_clock.gd")
const SCENES=preload("res://assets/art/profiles/native_scene_placeholders.tres")
const ROOM=preload("res://assets/art/native_v23/room.png")
const COUNTER=preload("res://assets/art/native_v23/counter.png")
const CUSTOMER=preload("res://assets/art/native_v23/g01.png")
const LAMP=preload("res://assets/art/native_v23/lamp.png")
const AMBER=preload("res://assets/art/native_v23/amber_reflection.png")
const RADIO_COUNTER=preload("res://assets/art/native_v23/radio_counter.png")
## Temporary single-view sprite; replace with the approved top-view illustration later.
const RADIO_PROFILE=preload("res://assets/art/profiles/radio_inspection_placeholder.tres")
const ITEMS=preload("res://assets/art/profiles/native_item_placeholders.tres")
const Profile=preload("res://src/presentation/item_visual_profile.gd")
# Compatibility alias for stock display and existing read-only references.
const RADIO_INSPECTION=preload("res://assets/art/native_v23/radio_front.png")
const WINDOWS=[preload("res://assets/art/native_v23/window_0.png"),preload("res://assets/art/native_v23/window_1.png"),preload("res://assets/art/native_v23/window_2.png"),preload("res://assets/art/native_v23/window_3.png"),preload("res://assets/art/native_v23/window_4.png"),preload("res://assets/art/native_v23/window_5.png")]
const COLD=[preload("res://assets/art/native_v23/cold_0.png"),preload("res://assets/art/native_v23/cold_1.png"),preload("res://assets/art/native_v23/cold_2.png"),preload("res://assets/art/native_v23/cold_3.png"),preload("res://assets/art/native_v23/cold_4.png"),preload("res://assets/art/native_v23/cold_5.png")]
static func scene_texture(key:String)->Texture2D:
	return SCENES.texture_for(key)

static func timed_texture(group:String,index:int)->Texture2D:
	return scene_texture(group+"."+str(clampi(index,0,5)))

static func tool_texture(id:String)->Texture2D:
	return SCENES.tool_for(id)

static func time_index(view:Dictionary)->int:
	if view.get("phase","")=="workshop":
		return 5
	var elapsed:int=clampi(posmod(int(view.get("minute",0)),Clock.DAY_MINUTES),0,Clock.BUSINESS_MINUTES)
	return clampi(roundi(float(elapsed)/120.0),0,5)
static func regions()->Dictionary:
	return RADIO_PROFILE.regions
static func art(inspecting:bool)->Texture2D:
	return RADIO_PROFILE.texture if inspecting else RADIO_COUNTER

## A single resource supplies item art to counter, inspection and storage.
static func item_profile(id:String,role:String)->Profile:
	return ITEMS.profile_for(id,role)

static func stock_texture(row:Dictionary)->Texture2D:
	var profile:Profile=item_profile(str(row.get("id","")),"stock")
	return profile.texture if profile!=null else null

## Dedicated authored office/storage space layers, sharing only the exterior view.
const OFFICE_ROOM=preload("res://assets/art/native_v23/rooms/office_room.png")
const OFFICE_FOREGROUND=preload("res://assets/art/native_v23/rooms/office_foreground.png")
const OFFICE_AMBER=preload("res://assets/art/native_v23/rooms/office_amber.png")
const OFFICE_LAMP=preload("res://assets/art/native_v23/rooms/office_lamp.png")
const STOCK_ROOM=preload("res://assets/art/native_v23/rooms/stock_room.png")
const STOCK_FOREGROUND=preload("res://assets/art/native_v23/rooms/stock_foreground.png")
const STOCK_AMBER=preload("res://assets/art/native_v23/rooms/stock_amber.png")
const STOCK_LAMP=preload("res://assets/art/native_v23/rooms/stock_lamp.png")

static func space_preview(kind:String,view:Dictionary,minimum:Vector2)->Control:
	var scene:=Control.new()
	scene.name=kind+"_art_scene"
	scene.custom_minimum_size=minimum
	scene.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var index:int=time_index(view)
	scene.set_meta("time_index",index)
	# Explicit typed assignment avoids the untyped ternary array conversion at runtime.
	var space:String="office" if kind=="office" else "stock"
	var layers:Array[Texture2D]=[]
	layers.append(timed_texture("window",index))
	for role:String in ["room","foreground","amber","lamp"]:
		layers.append(scene_texture(space+"."+role))
	var names:Array[String]=["window","room","foreground","amber","lamp"]
	for j:int in range(layers.size()):
		var layer:=TextureRect.new()
		layer.name=kind+"_"+names[j]+"_layer"
		layer.texture=layers[j]
		layer.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
		scene.add_child(layer)
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return scene

extends Resource
## Provisional visual layers only. No domain state or commands.
@export var textures:Dictionary={}
@export var tool_icons:Dictionary={}
@export var provisional:bool=true

func texture_for(key:String)->Texture2D:
	return textures.get(key) as Texture2D

func tool_for(id:String)->Texture2D:
	return tool_icons.get(id) as Texture2D

extends Resource
## Provisional artwork and visible, normalized interaction geometry ONLY.
## No game authority or observation result is stored here.
@export var texture:Texture2D
@export var regions:Dictionary={}
# Optional visible detail crops that need not be large pointer targets.
# Presentation only; this cannot create an authoritative observation.
@export var crop_regions:Dictionary={}
@export var provisional:bool=true

func valid(require_regions:bool=true)->bool:
	if texture==null or texture.get_width()<=0 or texture.get_height()<=0 or (require_regions and regions.is_empty()):
		return false
	for mapping:Dictionary in [regions,crop_regions]:
		for key:Variant in mapping:
			if not key is String or not mapping[key] is Rect2:
				return false
			var rect:Rect2=mapping[key]
			if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x<=0.0 or rect.size.y<=0.0:
				return false
			if not Rect2(0,0,1,1).encloses(rect):
				return false
	return true

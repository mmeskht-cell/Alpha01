extends RefCounted
## New isolated F3 source; never changes a preexisting SKU, visit or wallet.
const Base=preload("res://src/content/b3_spatial_week_seed.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Trial=preload("res://src/domain/b3_f3_composite_trial.gd")

static func content(seed_value:int)->Dictionary:
	var src:Dictionary=Base.content(seed_value)
	if src.is_empty(): return {}
	src.alpha_profile["battery_market"]="regional_late_v2"
	src.alpha_profile["f3_composite_trial"]=1
	var root:Dictionary=Objects.definition({"def_id":Trial.MODEL,"category":"civilian_electronics","localization_key":"item.civil_receiver","render_key":"placeholder_none","width":3,"height":2})
	root.merge({"kind":"composite","tag":Trial.MODEL,"weight":2,"required_tags":[Trial.PART_A,Trial.PART_B],"footprints":{"0":[2,1],"1":[2,1],"2":[3,2]},"recombine":true,"restorable":true,"restore_cost":{"VKC":5,"USD":0}},true)
	for id:String in [Trial.PART_A,Trial.PART_B]:
		var part:Dictionary=Objects.definition({"def_id":id,"category":"civilian_electronics","localization_key":"item.civil_module_a" if id==Trial.PART_A else "item.civil_module_b","render_key":"placeholder_none","width":1,"height":1})
		part.tag=id
		src.defs[id]=part
	src.defs[Trial.MODEL]=root
	var items:Dictionary=src.state.items
	items[Trial.ROOT]=Objects.fresh_item(Trial.MODEL,"G12","G12_grid",6,4,"f3_receiver_01")
	items[Trial.ROOT].functional=false
	for row:Array in [["F3R01_A",Trial.PART_A,true],[Trial.BAD,Trial.PART_B,false]]:
		items[row[0]]=Objects.fresh_item(row[1],"G12","",-1,-1,"f3_origin_"+str(row[0]))
		items[row[0]].parent_id=Trial.ROOT
		items[row[0]].functional=row[2]
	items[Trial.SPARE]=Objects.fresh_item(Trial.PART_B,"G12","G12_grid",9,5,"f3_spare_01")
	for id:String in Trial.VISITS:
		var r:Array=Trial.VISITS[id]
		var rows:Array=src.alpha_profile.days[int(r[0])-1]
		var actor:String=r[2] if r[3]=="player" else r[3]
		if rows.size()>=10 or rows.any(func(row:Dictionary)->bool:return row.actor_id==actor) or src.state.visits.has(id): return {}
		src.state.visits[id]={"scope":{"visit_id":id,"kind":"ordinary","purpose":"purchase" if r[3]=="player" else "sale","completed":false,"required_ids":[]},"seller":r[2],"buyer":r[3],"prices":{r[1]:{"VKC":r[4],"USD":0}},"opens":(int(r[0])-1)*1440,"expires":(int(r[0])-1)*1440+600,"allow_inspection":true}
		rows.append({"id":id,"actor_id":actor,"kind":"regular","purpose_key":"alpha.purpose.trade","contact_offer":false})
	return src

extends RefCounted
## Generic inventory-consistency checks on a trusted projection of active objects.
## Projection only: NOT a second registry or new persistent schema.
## Empty parent_id/container_id means no relationship. Attached children do not
## occupy a grid. A composite root may be stored inside an atomic container.
const Rules = preload("res://src/domain/value_rules.gd")
const MAX_ACTIVE: int = 128
const FIELDS: Array = ["kind", "parent_id", "container_id", "owner_id", "custodian_id", "container_capable", "locked"]

static func validate(nodes: Variant) -> Dictionary:
	if not nodes is Dictionary or nodes.size() > MAX_ACTIVE:
		return {"ok": false, "error": "relation_shape"}
	for item_id: Variant in nodes:
		var node: Variant = nodes[item_id]
		if not Rules.identifier(item_id) or not Rules.keys(node, FIELDS):
			return {"ok": false, "error": "relation_node"}
		if node.kind not in ["atomic", "composite"] or not Rules.identifier(node.owner_id) or not Rules.identifier(node.custodian_id):
			return {"ok": false, "error": "relation_identity"}
		if not node.parent_id is String or not node.container_id is String or not node.container_capable is bool or not node.locked is bool:
			return {"ok": false, "error": "relation_field"}
		if node.container_capable and node.kind != "atomic":
			return {"ok": false, "error": "relation_container_kind"}
		if not node.parent_id.is_empty() and not node.container_id.is_empty():
			return {"ok": false, "error": "relation_double_location"}
		if node.container_capable and (not node.parent_id.is_empty() or not node.container_id.is_empty()):
			return {"ok": false, "error": "relation_nested_container"}
		if not node.parent_id.is_empty() and (not Rules.identifier(node.parent_id) or not nodes.has(node.parent_id) or node.parent_id == item_id):
			return {"ok": false, "error": "relation_parent_ref"}
		if not node.container_id.is_empty() and (not Rules.identifier(node.container_id) or not nodes.has(node.container_id) or node.container_id == item_id):
			return {"ok": false, "error": "relation_container_ref"}
	# All rows have now passed shape checks. Relationship constraints limit depth.
	for item_id: Variant in nodes:
		var node: Dictionary = nodes[item_id]
		if not node.parent_id.is_empty():
			var parent: Dictionary = nodes[node.parent_id]
			if node.kind != "atomic" or parent.kind != "composite" or not parent.parent_id.is_empty():
				return {"ok": false, "error": "relation_parent_depth"}
			if parent.owner_id != node.owner_id or parent.custodian_id != node.custodian_id:
				return {"ok": false, "error": "relation_parent_custody"}
		if not node.container_id.is_empty():
			var box: Dictionary = nodes[node.container_id]
			if not box.container_capable or not box.parent_id.is_empty() or not box.container_id.is_empty():
				return {"ok": false, "error": "relation_container_depth"}
			if box.owner_id != node.owner_id or box.custodian_id != node.custodian_id:
				return {"ok": false, "error": "relation_container_custody"}
	return {"ok": true}

## Preview the exact IDs involved in selling/discarding a single independent item.
## Not an authorization: caller still validates state, phase, protected ancestors,
## positions, costs, visit/contract and command revision before atomic commit.
## No filled container sale/discard. No attached child sale/discard.
static func disposition_family(nodes: Variant, root_id: Variant, actor: Variant) -> Dictionary:
	var checked: Dictionary = validate(nodes)
	if not checked.ok:
		return checked
	if not Rules.identifier(root_id) or not Rules.identifier(actor) or not nodes.has(root_id):
		return {"ok": false, "error": "relation_root"}
	var root: Dictionary = nodes[root_id]
	if not root.parent_id.is_empty():
		return {"ok": false, "error": "relation_not_root"}
	if root.owner_id != actor or root.custodian_id != actor or root.locked:
		return {"ok": false, "error": "relation_protected"}
	if not root.container_id.is_empty():
		var box: Dictionary = nodes[root.container_id]
		if box.locked:
			return {"ok": false, "error": "relation_protected"}
	var ids: Array = [root_id]
	for item_id: Variant in nodes:
		var node: Dictionary = nodes[item_id]
		if node.container_id == root_id:
			return {"ok": false, "error": "relation_filled_container"}
		if node.parent_id == root_id:
			if node.locked or node.owner_id != actor or node.custodian_id != actor:
				return {"ok": false, "error": "relation_protected"}
			ids.append(item_id)
	ids.sort()
	return {"ok": true, "item_ids": ids}

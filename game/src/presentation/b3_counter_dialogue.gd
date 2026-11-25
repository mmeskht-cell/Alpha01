extends RefCounted
## B3 speech uses only the public NPC projection and the public trade direction.
## No item truth, private notes, hidden prices, random wallet/intent inference.

static func subject(slot: String) -> String:
	match slot:
		"wear_detail": return "사용 흔적"
		"display_damage_detail": return "표면 손상"
		"casing_detail": return "외장 상태"
		"material_detail": return "재질"
		"batch_detail": return "표식"
		"function_detail","condition_detail","basic_function_v1": return "작동 상태"
	return ""

static func line(context: Dictionary, we_buy: bool) -> String:
	var latest: Dictionary = context.get("latest_spoken",{})
	var offer: Dictionary = context.get("current_offer",{})
	var topic := subject(str(latest.get("slot","")))
	match str(latest.get("kind","")):
		"challenge":
			return "그 %s 말씀이군요. 제가 다시 확인해 보겠습니다."%topic if not topic.is_empty() else "그렇습니까? 다시 확인해 보겠습니다."
		"withdraw":
			return "아, %s에 대한 말씀은 취소하시는 거군요."%topic if not topic.is_empty() else "알겠습니다. 그 말씀은 취소하시는 거군요."
		"reaffirm":
			return "%s에 대해서는 아까 말씀대로라는 거죠?"%topic if not topic.is_empty() else "그 말씀은 여전히 유효하다는 거죠?"
	if not offer.is_empty():
		if offer.get("response")=="accepted":
			return "좋습니다. 그 가격에 넘기죠." if we_buy else "좋아요. 그 가격이면 사겠습니다."
		if offer.get("response")!="declined": return ""
		var evidence: Array = offer.get("public_slots",[])
		var remembered := false
		if evidence.is_empty():
			evidence = offer.get("active_slots",[])
			remembered = not evidence.is_empty()
		for slot: Variant in evidence:
			topic = subject(str(slot))
			if topic.is_empty(): continue
			if remembered: return "아까 %s 얘기는 기억합니다. 그래도 그 가격은 어렵군요."%topic
			return "%s 말씀은 알겠습니다. 그래도 그 가격은 좀 어렵군요."%topic
		if not offer.get("withdrawn_slots",[]).is_empty():
			return "아까 그 말씀은 취소하셨잖아요. 그 가격은 어렵겠습니다."
		return "그 돈에 넘기기는 좀 아깝군요." if we_buy else "그 가격은 제게 좀 부담스럽습니다."
	var prior: Dictionary = context.get("prior",{})
	match str(prior.get("outcome","")):
		"traded": return "지난번에 거래했었죠. 다시 들렀습니다."
		"commission_delivered": return "지난번 부탁은 잘 처리해 주셨죠."
		"service_delivered": return "지난번 맡긴 물건은 잘 받았습니다."
	var old: Dictionary = prior.get("offer",{})
	if old.get("response")=="declined": return "지난번에는 가격이 맞지 않았었죠."
	if old.get("response")=="accepted": return "지난번에는 가격만 정하고 끝났었죠."
	return "이 물건 좀 봐주시겠어요?" if we_buy else "이 물건, 살 수 있을까요?"

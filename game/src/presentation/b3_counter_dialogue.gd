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

## Stable expression variants only; not personality stats or economic modifiers.
## The empty actor ID retains the original canonical test phrases.
static func voice(actor_id: String) -> int:
	if actor_id.is_empty() or actor_id in ["ian","marcus"]: return 0
	return actor_id.sha256_text().left(6).hex_to_int()%3

static func phrase(actor_id: String, variants: Array[String]) -> String:
	return variants[voice(actor_id)]

static func line(context: Dictionary, we_buy: bool, actor_id: String = "") -> String:
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
			return phrase(actor_id,["좋습니다. 그 가격에 넘기죠.","됐습니다. 그 가격에 팔죠.","그럼 그렇게 합시다."]) if we_buy else phrase(actor_id,["좋아요. 그 가격이면 사겠습니다.","그 가격이면 됐습니다. 살게요.","알겠습니다. 그걸로 주세요."])
		if offer.get("response")!="declined": return ""
		var evidence: Array = offer.get("public_slots",[])
		var remembered := false
		if evidence.is_empty():
			evidence = offer.get("active_slots",[])
			remembered = not evidence.is_empty()
		for slot: Variant in evidence:
			topic = subject(str(slot))
			if topic.is_empty(): continue
			if remembered: return phrase(actor_id,["아까 %s 얘기는 기억합니다. 그래도 그 가격은 어렵군요.","%s 얘기는 들었습니다. 그래도 가격은 안 맞네요.","아까 %s 말씀하셨죠. 그래도 그 가격은 좀 그렇습니다."])%topic
			return phrase(actor_id,["%s 말씀은 알겠습니다. 그래도 그 가격은 좀 어렵군요.","%s 때문이라구요? 그래도 그 가격은 어렵습니다.","%s 얘기는 알겠는데, 그 가격은 좀 그렇네요."])%topic
		if not offer.get("withdrawn_slots",[]).is_empty():
			return "아까 그 말씀은 취소하셨잖아요. 그 가격은 어렵겠습니다."
		return phrase(actor_id,["그 돈에 넘기기는 좀 아깝군요.","그 값에는 못 넘기겠습니다.","조금 더 받을 수는 없을까요?"]) if we_buy else phrase(actor_id,["그 가격은 제게 좀 부담스럽습니다.","그 가격에는 사기 어렵습니다.","조금만 낮춰주실 수 없나요?"])
	var prior: Dictionary = context.get("prior",{})
	match str(prior.get("outcome","")):
		"traded": return phrase(actor_id,["지난번에 거래했었죠. 다시 들렀습니다.","지난번에 여기서 거래했죠. 또 왔습니다.","안녕하세요. 지난번 거래 기억하시죠?"])
		"commission_delivered": return "지난번 부탁은 잘 처리해 주셨죠."
		"service_delivered": return "지난번 맡긴 물건은 잘 받았습니다."
	var old: Dictionary = prior.get("offer",{})
	if old.get("response")=="declined": return "지난번에는 가격이 맞지 않았었죠."
	if old.get("response")=="accepted": return "지난번에는 가격만 정하고 끝났었죠."
	return phrase(actor_id,["이 물건 좀 봐주시겠어요?","이것 좀 사주시겠습니까?","안녕하세요. 물건 좀 팔려고요."]) if we_buy else phrase(actor_id,["이 물건, 살 수 있을까요?","이거 팔고 계시는 거죠?","안녕하세요. 이걸 좀 사고 싶은데요."])

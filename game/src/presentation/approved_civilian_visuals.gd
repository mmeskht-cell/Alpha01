extends RefCounted
## Candidate presentation keys only. Never assign a gameplay definition here.
const ROOT = "res://assets/art/items/approved_civilian_v01/"
const LABELS = {
	"medical_01_field_bandage": {"ko":"야전 붕대","en":"Field Bandage"},
	"medical_02_first_aid_kit": {"ko":"구급 키트","en":"First Aid Kit"},
	"medical_03_painkillers": {"ko":"진통제","en":"Painkillers"},
	"medical_04_antiseptic": {"ko":"소독제","en":"Antiseptic"},
	"medical_05_syringe_kit": {"ko":"주사기 세트","en":"Syringe Kit"},
	"medical_06_soap": {"ko":"비누","en":"Soap"},
	"medical_07_matches": {"ko":"성냥","en":"Matches"},
	"medical_08_candles": {"ko":"양초","en":"Candles"},
	"medical_09_tooth_powder": {"ko":"치분","en":"Tooth Powder"},
	"medical_10_water_tablets": {"ko":"정수제","en":"Water Tablets"},
	"utility_01_field_radio": {"ko":"휴대 라디오","en":"Field Radio"},
	"utility_02_flashlight": {"ko":"손전등","en":"Flashlight"},
	"utility_03_aa_batteries": {"ko":"AA 건전지","en":"AA Batteries"},
	"utility_04_power_bank": {"ko":"보조배터리","en":"Power Bank"},
	"utility_05_wrench": {"ko":"조절식 스패너","en":"Adjustable Wrench"},
	"utility_06_pliers": {"ko":"펜치","en":"Pliers"},
	"utility_07_electrical_tape": {"ko":"절연테이프","en":"Electrical Tape"},
	"utility_08_multimeter": {"ko":"멀티미터","en":"Multimeter"},
	"utility_09_recorder": {"ko":"녹음기","en":"Recorder"},
	"utility_10_control_module": {"ko":"전자제어 모듈","en":"Electronic Control Module"}
}

static func available(key: String) -> bool:
	if not LABELS.has(key):
		return false
	return ResourceLoader.exists(ROOT+key+"_128.png","Texture2D") and ResourceLoader.exists(ROOT+key+"_256.png","Texture2D")

static func texture_for(key: String, role: String, back: bool=false) -> Texture2D:
	if back or role not in ["stock","counter","inspection"] or not available(key):
		return null
	var suffix: String = "_128.png" if role=="stock" else "_256.png"
	return ResourceLoader.load(ROOT+key+suffix,"Texture2D") as Texture2D

static func available_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for key: String in LABELS:
		if available(key):
			keys.append(key)
	return keys

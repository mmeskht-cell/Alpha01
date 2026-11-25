extends SceneTree
## Isolated arithmetic and provenance contract. Not a live session test.
const Quote = preload("res://src/presentation/b3_ratio_offer.gd")
var checks := 0
var failures := 0

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _initialize() -> void:
	var known := {"estimate":{"VKC":{"low":180,"high":220}}}
	var original := known.duplicate(true)
	var b := Quote.basis(known,"VKC")
	check(b.amount==200 and b.source=="appraisal_range","midpoint of known appraisal band")
	check(Quote.amount(b,500)==100 and Quote.amount(b,550)==110,"ratio amounts")
	check(Quote.amount(b,1000)==200 and Quote.amount(b,1200)==240,"above and below appraisal")
	check(Quote.shift(b,500,50)==550,"five point adjustment")
	check(Quote.amount(b,475)==95 and Quote.shift(b,475,1)>475,"fine adjustment")
	check(Quote.basis(known,"USD").is_empty(),"no implicit currency conversion")
	check(Quote.basis({},"VKC").is_empty(),"missing data stays missing")
	check(Quote.basis({},"VKC",{"amount":100,"currency":"VKC","kind":"hidden_quote","source":"visit"}).is_empty(),"private quote rejected")
	var p := Quote.basis({},"USD",{"amount":2,"currency":"USD","kind":"personal_provisional","source":"player"})
	check(p.source=="personal_provisional" and Quote.amount(p,500)==1,"provisional estimate separately labelled")
	check(Quote.amount(p,0)==0 and Quote.amount(p,-10)==0,"invalid ratio rejected")
	var shifted := Quote.shift(p,500,50)
	check(Quote.amount(p,shifted)==2,"low value skips duplicate rounded price")
	check(Quote.amount({"amount":999999999,"currency":"VKC"},1010)==0,"bounded amount")
	var catalog := {"currency":"VKC","source_key":"test_public","slots":[{"effect":"base","candidates":[{"id":"radio","value":200}]},{"id":"appearance_id","effect":"percent","candidates":[{"id":"visible_wear","value":80}]}]}
	check(Quote.catalog_basis(catalog,{"id":"radio","value":200},"moderate","VKC").amount==160,"public factor follows private judgment")
	check(Quote.catalog_basis(catalog,{"id":"radio","value":200},"unknown","VKC").amount==200,"unknown condition remains unadjusted reference")
	check(Quote.catalog_basis(catalog,{"id":"other","value":200},"moderate","VKC").is_empty(),"noncatalog model rejected")
	check(known==original,"pure input")
	print("B3_RATIO_OFFER: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)

extends Button


# Called when the node enters the scene tree for the first time.
func _ready():
	print("quit button ready as fuck")


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func _pressed():
	print("Button pushy")
	get_tree().quit();

extends Control

# Patreon supporter data
const SUPPORTERS = {
    "MantaGuardians": [
        "Kai",
        "Buoy"
    ],
    "OceanVoyagers": [
        "cinnaroll",
        "Tamanegi-K'",
        "Alcor",
        "darkcyanblade",
        "redpandarolo",
        "teamvista",
        "Aether8781",
        "Cabbidachi",
        "pikatrue",
        "A.J.",
        "diao ferret",
        "Nathaniel",
        "Safranil",
        "Frost",
        "Alex",
        "Bon",
        "Syrras",
        "AYY",
        "Feathers",
        "Nexo",
        "Jakiepour",
        "Martin",
        "Maisey"
    ],
    "WaveRiders": [
        "Jonsean",
        "Darvin",
        "Toothymcfang",
        "Quippersnapper",
        "Brian Holme",
        "jeyrolami",
        "darMP",
        "xtradeep",
        "Larry Koopa",
        "Jodrik",
        "Green Aurora",
    ]
}

# Tier colors (hex codes)
const TIER_COLORS = {
    "MantaGuardians": Color("#9573cb"),  # Purple
    "OceanVoyagers": Color("#1e847a"),   # Teal
    "WaveRiders": Color("#8be4f9")       # Light blue
}

# Font sizes for each tier (height in pixels)
const TIER_FONT_SIZES = {
    "MantaGuardians": 32,  # Largest - increased from 24
    "OceanVoyagers": 26,   # Medium - increased from 20
    "WaveRiders": 16       # Smallest - kept the same
}

func _ready():
    _populate_supporters()

# Helper function to create a row of supporters
func _create_supporter_row(container, supporters: Array, color: Color, font_size: int):
    for supporter in supporters:
        var label = Label.new()
        label.text = supporter
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.modulate = color
        label.add_theme_font_size_override("font_size", font_size)
        label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        label.custom_minimum_size = Vector2(120, 0)  # Consistent width for proper spacing
        
        container.add_child(label)

func _populate_supporters():
    # Use a single RichTextLabel for all supporters with tier-specific formatting
    var supporters_text = ""
    
    # Add Manta Guardians with large text and purple color
    supporters_text += "[b][color=#9573cb][font_size=32]Manta Guardians[/font_size][/color][/b]\n"
    for i in range(SUPPORTERS["MantaGuardians"].size()):
        supporters_text += "[color=#9573cb][font_size=32]" + SUPPORTERS["MantaGuardians"][i] + "[/font_size][/color]"
        if i < SUPPORTERS["MantaGuardians"].size() - 1:
            supporters_text += "    "  # 4 spaces between names
    
    supporters_text += "\n\n"  # Double newline for separation
    
    # Add Ocean Voyagers with large text and teal color
    supporters_text += "[b][color=#1e847a][font_size=32]Ocean Voyagers[/font_size][/color][/b]\n"
    for i in range(SUPPORTERS["OceanVoyagers"].size()):
        supporters_text += "[color=#1e847a][font_size=26]" + SUPPORTERS["OceanVoyagers"][i] + "[/font_size][/color]"
        if i < SUPPORTERS["OceanVoyagers"].size() - 1:
            supporters_text += "    "  # 4 spaces between names
    
    supporters_text += "\n\n"  # Double newline for separation
    
    # Add Wave Riders with large text and light blue color
    supporters_text += "[b][color=#8be4f9][font_size=32]Wave Riders[/font_size][/color][/b]\n"
    for i in range(SUPPORTERS["WaveRiders"].size()):
        supporters_text += "[color=#8be4f9][font_size=16]" + SUPPORTERS["WaveRiders"][i] + "[/font_size][/color]"
        if i < SUPPORTERS["WaveRiders"].size() - 1:
            supporters_text += "    "  # 4 spaces between names
    
    # Create and populate the RichTextLabel
    var rich_text = RichTextLabel.new()
    rich_text.bbcode_enabled = true
    rich_text.text = supporters_text
    rich_text.scroll_active = false
    rich_text.fit_content = true
    
    # Clear existing content and add the new RichTextLabel
    var supporters_section = $ScrollContainer/VBoxContainer/SupportersSection
    for child in supporters_section.get_children():
        if child != $ScrollContainer/VBoxContainer/SupportersSection/SupportersTitle:
            child.queue_free()
    
    supporters_section.add_child(rich_text)

func _get_or_create_container(parent_path: String, container_name: String):
    var parent = get_node(parent_path)
    var existing_container = parent.get_node_or_null(container_name)
    
    if existing_container:
        return existing_container
    
    # Create new container if it doesn't exist
    var new_container = HFlowContainer.new()
    new_container.name = container_name
    parent.add_child(new_container)
    return new_container

func _clear_container_children(container):
    for child in container.get_children():
        child.queue_free()

func _on_back_pressed():
    # Go back to main menu
        get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

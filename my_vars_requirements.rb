# Rally Connection parameters
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "topsecret"
$wsapi_version                   = "1.43"
$my_workspace                    = "My Workspace"
$my_project                      = "My Project"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_name               = "hhc.xml"
$caliber_id_field_name           = 'CaliberID'
$caliber_image_directory         = "/images"
$max_import_count                = 100000

# Runtime preferences
$html_mode                       = true
$preview_mode                    = true

# Flag to set in @rally_story_hierarchy_hash if Requirement has no Parent
$no_parent_id                    = "-9999"

# Output parameters
$my_output_file                  = "caliber_requirements.csv"
$requirement_fields              =  %w{id hierarchy name project description validation purpose pre_condition basic_course post_condition exceptions remarks}

# JDF Project setting
$jdf_zeus_control_project        = "JDF-Zeus_Control-project"
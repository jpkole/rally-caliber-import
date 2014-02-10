# Rally Connection parameters
$my_base_url                     = "https://audemo.rallydev.com/slm"
$my_username                     = "paul@acme.com"
$my_password                     = "RallyON!"
$wsapi_version                   = "1.43"
$my_workspace                    = "JPKole_Caliber"
$my_project                      = "JPKole_JDF_Hera"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_name               = "../from-ftp-site/heraTC_and_REQ/heraTC_and_REQ.xml"
$caliber_id_field_name           = 'Externalreference'
$caliber_image_directory         = "../from-ftp-site/ImageCache"
$max_import_count                = 999

# Runtime preferences
$html_mode                       = true
$preview_mode                    = false

# Flag to set in @rally_story_hierarchy_hash if Requirement has no Parent
$no_parent_id                    = "-9999"

# Output parameters
$my_output_file                  = "caliber_requirements.csv"
$requirement_fields              =  %w{id hierarchy name project description validation purpose pre_condition basic_course post_condition exceptions remarks}

# JDF_Hera data set ----
$description_field_hash_01_jdf_hera = {
	'Caliber Purpose'         => 'caliber_purpose',
	'Pre-condition'           => 'pre_condition',
	'Basic course'            => 'basic_course',
	'Post-condition'          => 'post_condition',
	'Exceptions'              => 'exceptions',
	'Remarks'                 => 'remarks',
	'Description'             => 'description',
	'Validation'              => 'validation',
	'Input'                   => 'input',
	'Output'                  => 'output'
}
$description_field_hash_02_jdf_next = {}
$description_field_hash_03_jdf_next = {}
$description_field_hash_04_jdf_next = {}
$description_field_hash_05_jdf_next = {}

$description_field_hash		= $description_field_hash_01_jdf_hera

# Rally Connection parameters
$my_base_url                     = "https://audemo.rallydev.com/slm"
$my_username                     = "paul@acme.com"
$my_password                     = "RallyON!"
$wsapi_version                   = "1.43"
$my_workspace                    = "Caliber"
$my_project                      = "JDF_Hera"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_name               = "../from-ftp-site/heraTC_and_REQ/heraTC_and_REQ.xml"
#$caliber_file_name               = "../from-marks-dropbox/hhc.xml"
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
$description_field_hash_jdf_hera = {
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
$description_field_hash_jdf_next2 = {}
$description_field_hash_jdf_next3 = {}
$description_field_hash_jdf_next4 = {}
$description_field_hash_jdf_next5 = {}

$description_field_hash		= $description_field_hash_jdf_hera

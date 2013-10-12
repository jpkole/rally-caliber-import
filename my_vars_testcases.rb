# Rally Connection parameters
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "topsecret"
$wsapi_version                   = "1.43"
$my_workspace                    = "My Workspace"
$my_project                      = "My Project"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_name               = "jdf_testcase_zeuscontrol.xml"
$caliber_id_field_name           = 'CaliberID'
$caliber_weblink_field_name      = 'CaliberTCParentLink'
$caliber_image_directory         = "/images"

# Runtime preferences
$max_import_count                = 100000
$html_mode                       = true
$preview_mode                    = false

# Flag to set in @rally_testcase_hierarchy_hash if Requirement has no Parent
$no_parent_id                    = "-9999"

# Output parameters
$my_output_file                  = "caliber_testcases.csv"

$testcase_fields                 =  %w{id hierarchy name project source purpose pre_condition testing_course post_condition machine_type software_load content_status remarks validation description include testing_status test_running}

# Output fields to store a CSV
# allowing lookup of TestCase OID by Caliber TestCase ID
# (needed for traces import)
$testcase_oid_output_csv            = "testcase_oids_by_testcaseid.csv"
$testcase_oid_output_fields         =  %w{testcase_id ObjectID}

# JDF Project setting
$caliber_project                 = "JDF-Zeus_Control-project"
$jdf_zeus_control_project        = "JDF-Zeus_Control-project"
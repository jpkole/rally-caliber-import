# Rally Connection parameters
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "rally_caliber@johndeere.com"
$my_password                     = "!!nrlad1804"
$my_wsapi_version                = "1.43"
$my_workspace                    = "JDF Tampere"
$my_project                      = "Caliber2Rally_Hera"

$my_base_url                     = "https://audemo.rallydev.com/slm"
$my_username                     = "paul@acme.com"
$my_password                     = "RallyON!"
$my_wsapi_version                = "1.43"
$my_workspace                    = "Integrations"
$my_project                      = "JPKole_JDF_Tnavi-4"

$max_attachment_length           = 5000000

# Caliber parameters

# JDF_zeuscontrol project:
# (proof of concept project)                                                                    # Order of import:
# --------------------------                                                                    # ---------------------
#$caliber_file_req               = "../from-marks-dropbox/hhc.xml"                               # 01-Requirements
#$caliber_file_req_traces        = "../from-marks-dropbox/hhc_traces.xml"                        # 02-Requirement-Traces
#$caliber_file_tc                = "../from-marks-dropbox/jdf_testcase_zeuscontrol.xml"          # 03-Testcases
#$caliber_file_tc_traces         = "../from-marks-dropbox/jdf_testcase_traces_zeuscontrol.xml"   # 04-Testcases-Traces
#$caliber_image_directory        = "../from-marks-dropbox/images"

$caliber_file_req               = "../from-ftp-site/fetch1/heraTC_and_REQ/heraTC_and_REQ.xml"   # 01-Requirements
$caliber_file_req_traces        = "../from-ftp-site/fetch1/heraTC_and_REQ/heratrace.xml"        # 02-Requirement-Traces
$caliber_file_tc                = "../from-ftp-site/fetch1/heraTC_and_REQ/heraTC_and_REQ.xml"   # 03-Testcases
$caliber_file_tc_traces         = "../from-ftp-site/fetch1/heraTC_and_REQ/heratrace.xml"        # 04-Testcases-Traces
$caliber_image_directory        = "../from-ftp-site/fetch1/ImageCache"

$caliber_file_req               = "../from-ftp-site/fetch2/tnavi2014.xml"                       # 01-Requirements
$caliber_file_req_traces        = "../from-ftp-site/fetch2/TNavitrace.xml"                      # 02-Requirement-Traces
$caliber_file_tc                = ""                                                            # 03-Testcases
$caliber_file_tc_traces         = ""                                                            # 04-Testcases-Traces
$caliber_image_directory        = "../from-ftp-site/fetch2/ImageCache"

# Custom fields in Rally: on User Story
$caliber_id_field_name          = "CaliberID"           # US - type String
$caliber_req_traces_field_name  = "Externalreference"   # US - type Text

# Custom fields in Rally: on TestCase
$caliber_id_field_name          = "CaliberID"           # TC - type String
$caliber_weblink_field_name     = "CaliberTCParent"     # TC - type Weblink
$caliber_tc_traces_field_name   = "Externalreference"   # TC - type Text

$max_import_count               = 5000

# Runtime preferences
$html_mode                      = true
$preview_mode                   = false

# Flag to set in @rally_story_hierarchy_hash if Requirement has no Parent
$no_parent_id                   = "-9999"

# CSV file & fields to allow lookup of ...
$csv_requirements               = "s1-requirements.csv"
$csv_requirement_fields         =  %w{id hierarchy name project description validation purpose pre_condition basic_course post_condition exceptions remarks}

# CSV file & fields to allow lookup of Story OID by Caliber Requirement Name (needed for traces import).
$csv_story_oids_by_req          = "s1-story_oids_by_reqname.csv"
$csv_story_oids_by_req_fields   =  %w{FmtID  ObjectID  CaliberID  reqname}

# CSV file & fields to allow lookup of ...
$csv_testcases                  = "s3-testcases.csv"
$csv_testcase_fields            =  %w{id hierarchy name project source purpose pre_condition testing_course post_condition machine_type software_load content_status remarks validation description include testing_status test_running}

# CSV file & fields to allow lookup of TestCase OID by Caliber TestCase ID (needed for traces import).
$csv_testcase_oid_output        = "s3-testcase_oids_by_testcaseid.csv"
$csv_testcase_oid_output_fields =  %w{testcase_id ObjectID FormattedID testcase_name}

# Log files
$cal2ral_req_log                = "s1-requirements.log"
$cal2ral_req_traces_log         = "s2-requirement_traces.log"
$cal2ral_tc_log                 = "s3-testcases.log"
$cal2ral_tc_traces_log          = "s4-testcase_traces.log"

# JDF_Hera data set ----
$description_field_hash_01_jdf_hera = {
        'Caliber Purpose'       => 'caliber_purpose',
        'Pre-condition'         => 'pre_condition',
        'Basic course'          => 'basic_course',
        'Post-condition'        => 'post_condition',
        'Exceptions'            => 'exceptions',
        'Remarks'               => 'remarks',
        'Description'           => 'description',
        'Validation'            => 'validation',
        'Input'                 => 'input',
        'Output'                => 'output'
}
$description_field_hash_02_jdf_next = {}
$description_field_hash_03_jdf_next = {}
$description_field_hash_04_jdf_next = {}
$description_field_hash_05_jdf_next = {}

$description_field_hash         = $description_field_hash_01_jdf_hera

#the end#
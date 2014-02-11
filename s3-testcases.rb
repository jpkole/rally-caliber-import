#!/usr/bin/env ruby

require 'base64'
require 'csv'
require 'nokogiri'
require 'uri'
require 'rally_api'
require 'logger'
require './caliber_helper.rb'
require './multi_io.rb'
require 'debugger'

# Rally Connection parameters
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "topsecret"
$wsapi_version                   = "1.43"
$my_workspace                    = "My Workspace"
$my_project                      = "My Project"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_tc                 = "jdf_testcase_zeuscontrol.xml"
$caliber_id_field_name           = 'CaliberID'
$caliber_weblink_field_name      = 'CaliberTCParentLink'
$caliber_image_directory         = "/images"

# Runtime preferences
$max_import_count                = 100000
$html_mode                       = true
$preview_mode                    = false

# Flag to set in @rally_testcase_hierarchy_hash if Requirement has no Parent
$no_parent_id                    = "-9999"

if $my_delim == nil then $my_delim = "\t" end

# Load (and maybe override with) my personal/private variables from a file...
my_vars = "./my_vars.rb"
if FileTest.exist?( my_vars ) then 
    print "Sourcing #{my_vars}...\n"
    require my_vars
else
    print "File #{my_vars} not found...\n"
end


# HTML Mode vs. XML Mode
# The following is needed to preserve newlines in formatting of UDAValues when
# Imported into Rally. Caliber export uses newlines in UDAValue attributes as formatting.
# When importing straight XML, the newlines are ignored completely
# Rally (and Nokogiri, really) needs markup. This step replaces newlines with <br>
# And reads the resulting input as HTML rather than XML
caliber_file = File.open($caliber_file_tc, 'rb')
caliber_content = caliber_file.read
caliber_content_html = caliber_content.gsub("\n", "&lt;br/&gt;\n")

if $html_mode then
    caliber_data = Nokogiri::HTML(caliber_content_html, 'UTF-8') do | config |
        config.strict
    end
else
    caliber_data = Nokogiri::XML(File.open($caliber_file_tc), 'UTF-8') do | config |
        config.strict
    end
end

# set preview mode
if $preview_mode then
    $import_to_rally                 = false
    $stitch_hierarchy                = false
    $import_images_flag              = false
else
    $import_to_rally                 = true
    $stitch_hierarchy                = true
    $import_images_flag              = true
end

# The following are all value attributes inside the <Requirement> tag itself.
# Example:
# <Requirement
#      index="0"
#      hierarchy="1"
#      id="20023"
#      name="Operating harvester head"
#      description="&lt;html&gt;&lt;body&gt;&lt;/html&gt;"
#      validation=""
#      type="JDF Requirement (REQ)"
#      owner=""
#      status="Submitted"
#      priority="Essential"
#      version="1.12"
#      tag="REQ20023"
#      name_tag="Operating harvester headREQ20023">

# Tags of interest
$report_tag                              = "Report"
$requirement_type_tag                    = "ReqType"
$requirement_tag                         = "Requirement"
$uda_values_tag                          = "UDAValues"
$uda_value_tag                           = "UDAValue"

# These are the value tags to look/parse for once on the <Requirement> tag
$requirement_name                        = "name"
$requirement_hierarchy                   = "hierarchy"
$requirement_id                          = "id"
$requirement_validation                  = "validation"

# In HTML mode, the tags are all lowercase so downcase them
if $html_mode then
    $report_tag                          = $report_tag.downcase
    $requirement_type_tag                = $requirement_type_tag.downcase
    $requirement_tag                     = $requirement_tag.downcase
    $uda_values_tag                      = $uda_values_tag.downcase
    $uda_value_tag                       = $uda_value_tag.downcase
end

# Caliber TestCases are just a flavor of a Caliber Requirement
# with some different UDAValues
# The following are all types of <UDAValue> records on <Requirement>
# Example:
# <UDAValues>
# <UDAValue id="27" req_id="22590" name="JDF Source [So]" value="Juha Järvenpää"/>
# <UDAValue id="28" req_id="22590" name="JDF Purpose [Pu]" value="Cabin levelling cylinders positions are measured with separate position sensors."/>
# <UDAValue id="29" req_id="22590" name="JDF Pre-condition [Pr]" value="A. No active DTCs related to cabin levelling cylinders position sensors."/>
# <UDAValue id="30" req_id="22590" name="JDF Project" value="6.0"/>
# <UDAValue id="31" req_id="22590" name="JDF Post-condition [Po]" value="none"/>
# <UDAValue id="32" req_id="22590" name="JDF Machine Type" value="Base machine"/>
# <UDAValue id="33" req_id="22590" name="JDF Software Load" value="3"/>
# <UDAValue id="34" req_id="22590" name="JDF Content Status" value="3. Test Specified"/>
# <UDAValue id="35" req_id="22590" name="JDF Remarks [Re]" value=""/>
# <UDAValue id="36" req_id="22590" name="JDF Testing Course [Te]" value="See validation"/>
# <UDAValue id="37" req_id="22590" name="JDF Include" value="FALSE"/>
# <UDAValue id="38" req_id="22590" name="JDF Testing Status" value="4. Test OK"/>
# <UDAValue id="39" req_id="22590" name="JDF Test Running" value="UNDEFINED"/>
# </UDAValues>

# These are the value fields to look/parse for once on the <UDAValues> tag
$uda_value_name_source                   = "JDF Source [Pu]"
$uda_value_name_purpose                  = "JDF Purpose [Pu]"
$uda_value_name_pre_condition            = "JDF Pre-condition [Pr]"
$uda_value_name_project                  = "JDF Project"
$uda_value_name_post_condition           = "JDF Post-condition [Po]"
$uda_value_name_machine_type             = "JDF Machine Type"
$uda_value_name_software_load            = "JDF Software Load"
$uda_value_name_content_status           = "JDF Content Status"
$uda_value_name_remarks                  = "JDF Remarks [Re]"
$uda_value_name_testing_course           = "JDF Testing Course [Te]"
$uda_value_name_include                  = "JDF Include"
$uda_value_name_testing_status           = "JDF Testing Status"
$uda_value_name_test_running             = "JDF Test Running"

# Record template hash for a requirement from Caliber
# Hash fields are in same order as CSV output format

$caliber_testcase_record_template = {
    'id'                    => 0,
    'hierarchy'             => 0,
    'tag'                   => "",
    'name'                  => "",
    'project'               => "",
    'source'                => "",
    'purpose'               => "",
    'pre_condition'         => "",
    'testing_course'        => "",
    'post_condition'        => "",
    'machine_type'          => "",
    'software_load'         => "",
    'content_status'        => "",
    'remarks'               => "",
    'validation'            => "",
    'description'           => "",
    'include'               => "",
    'testing_status'        => "",
    'test_running'          => ""
}

$description_field_hash = {
    'Source [So]'             => 'source',
    'Purpose [Pu]'            => 'purpose',
    'Pre-condition [Pr]'      => 'pre_condition',
    'Testing Course [Te]'     => 'testing_course',
    'Post-condition [Po]'     => 'post_condition',
    'Remarks [Re]'            => 'remarks',
    'Validation'              => 'validation',
    'Description'             => 'description'
}

begin

#==================== Connect to Rally and Import Caliber data ====================

    #Setting custom headers
    $headers                            = RallyAPI::CustomHttpHeader.new()
    $headers.name                       = "Caliber Testcase Importer"
    $headers.vendor                     = "Rally Technical Services"
    $headers.version                    = "0.50"

    config                  = {:base_url => $my_base_url}
    config[:username]       = $my_username
    config[:password]       = $my_password
    config[:workspace]      = $my_workspace
    config[:project]        = $my_project
    config[:version]        = $wsapi_version
    config[:headers]        = $headers

    @rally = RallyAPI::RallyRestJson.new(config)

    # Instantiate Logger
    log_file = File.open($cal2ral_tc_log, "a")
    log_file.sync = true
    @logger = Logger.new MultiIO.new(STDOUT, log_file)

    @logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL

    # Report vars
    @logger.info "Running #{$PROGRAM_NAME} with the following settings:
                $my_base_url                    = #{$my_base_url}
                $my_username                    = #{$my_username}
                $my_workspace                   = #{$my_workspace}
                $my_project                     = #{$my_project}
                $caliber_file_name              = #{$caliber_file_name}
                $caliber_image_directory        = #{$caliber_image_directory}
                $caliber_id_field_name          = #{$caliber_id_field_name}
		$caliber_weblink_field_name     = #{$caliber_weblink_field_name}
                $max_import_count               = #{$max_import_count}
                $my_output_file                 = #{$my_output_file}
  		$csv_testcase_fields            = #{$csv_testcase_fields}
                $import_to_rally                = #{$import_to_rally}
                $stitch_hierarchy               = #{$stitch_hierarchy}
                $import_images_flag             = #{$import_images_flag}
                $csv_testcase_oid_output        = #{$csv_testcase_oid_output}
                $csv_testcase_oid_output_fields = #{$csv_testcase_oid_output_fields}"

    # Initialize Caliber Helper
    @caliber_helper = CaliberHelper.new(@rally, $caliber_project, $caliber_id_field_name,
        $description_field_hash, $caliber_image_directory, @logger, $caliber_weblink_field_name)

    # Output CSV of TestCase data
    testcase_csv = CSV.open($csv_testcases, "wb", {:col_sep => $my_delim})
    testcase_csv << $csv_testcase_fields

    # Output CSV of TestCase OID's by Caliber Requirement Name
    testcase_oid_csv    = CSV.open($csv_testcase_oid_output, "wb", {:col_sep => $my_delim})
    testcase_oid_csv    << $csv_testcase_oid_output_fields

    # The following are used for the post-run web-linking
    # Hash of TestCase keyed by Caliber Requirement Hierarchy ID
    @rally_testcase_hierarchy_hash = {}

    # The following are used for the post-run import of images for
    # Caliber TestCases whose description contains embedded images
    @rally_testcases_with_images_hash = {}

    # Hash of Parent Hierarchy ID's keyed by Self Hierarchy ID
    @caliber_parent_hash = {}

    # Read through caliber file and store requirement records in array of requirement hashes
    import_count = 0
    caliber_data.search($report_tag).each do | report |
        report.search($requirement_type_tag).each do | req_type |
            req_type.search($requirement_tag).each do | testcase |

                # Data - holds output for CSV
                testcase_data                        = []
                testcase_oid_data                    = []

                # Store fields that derive from Project and Requirement objects
                this_testcase                        = {}
                this_testcase['project']             = report['project']
                this_testcase['hierarchy']           = testcase['hierarchy']
                this_testcase['id']                  = testcase['id']
                this_testcase['tag']                 = testcase['tag']
                this_testcase['name']                = testcase['name'] || ""

                # process_description_body pulls HTML content out of <html><body> tags
                this_testcase['description']         = @caliber_helper.process_description_body(testcase['description'] || "")
                this_testcase['validation']          = @caliber_helper.process_description_body(testcase['validation'] || "")

                # Store Caliber ID, HierarchyID, Project and Name in variables for convenient logging output
                testcase_id                                  = testcase['id']
                testcase_tag                                 = testcase['tag']
                testcase_hierarchy                           = testcase['hierarchy']
                testcase_project                             = testcase['project']
                testcase_name                                = testcase['name']

                @logger.info "Started Reading Caliber TestCase ID: #{testcase_id}; Hierarchy: #{testcase_hierarchy}; Project: #{testcase_project}"

                # Loop through UDAValue records and cache fields from them
                # There are many UDAValue records per testcase and each is different
                # So assign to values of interest via case statement

                testcase.search($uda_values_tag).each do | uda_values |
                    uda_values.search($uda_value_tag).each do | uda_value |
                        uda_value_name = uda_value['name']
                        uda_value_value = uda_value['value'] || ""
                        case uda_value_name
                            when $uda_value_name_source
                                this_testcase['source']             = uda_value_value
                            when $uda_value_name_purpose
                                this_testcase['purpose']            = uda_value_value
                            when $uda_value_name_pre_condition
                                this_testcase['pre_condition']      = uda_value_value
                            when $uda_value_name_testing_course
                                this_testcase['testing_course']     = uda_value_value
                            when $uda_value_name_post_condition
                                this_testcase['post_condition']     = uda_value_value
                            when $uda_value_name_remarks
                                this_testcase['remarks']            = uda_value_value
                            when $uda_value_name_machine_type
                                this_testcase['machine_type']       = uda_value_value
                            when $uda_value_name_software_load
                                this_testcase['software_load']      = uda_value_value
                            when $uda_value_name_content_status
                                this_testcase['content_status']     = uda_value_value
                            when $uda_value_name_include
                                this_testcase['include']            = uda_value_value
                            when $uda_value_name_testing_status
                                this_testcase['testing_status']     = uda_value_value
                            when $uda_value_name_test_running
                                this_testcase['test_running']       = uda_value_value
                        end
                    end
                end

                @logger.info "    Finished Reading Caliber TestCase ID: #{testcase_id}; Hierarchy: #{testcase_hierarchy}; Project: #{testcase_project}"

                # Dummy testcase used only when testing
                # Includes our required fields
                testcase = {
                    "ObjectID"       => 12345678910,
                    "FormattedID"    => "TC1234",
                    "Method"         => "Automated",
                    "Type"           => "Functional",
                    "Name"           => "My TestCase",
                    "Description"    => "My Description",
                    "_ref"           => "/testcase/12345678910"
                }

                # Import to Rally
                if $import_to_rally then
                    testcase = @caliber_helper.create_testcase_from_caliber(this_testcase)
                end

                # Save the TestCase OID and associated it to the Caliber Hierarchy ID for later use
                # in stitching
                @rally_testcase_hierarchy_hash[testcase_hierarchy] = testcase

                # Get the Parent hierarchy ID for this Caliber Requirement
                parent_hierarchy_id = @caliber_helper.get_parent_hierarchy_id(this_testcase)
                @logger.info "    Parent Hierarchy ID: #{parent_hierarchy_id}"

                # Store the requirements Parent Hierarchy ID for use in stitching
                @caliber_parent_hash[testcase_hierarchy] = parent_hierarchy_id

                # store a hash containing:
                # - Caliber description field
                # - Array of caliber image file objects in TestCase hash
                #
                # For later use in post-processing run to import images
                # This allows us to import the images onto Rally stories by OID, and
                # Update the Rally TestCase Description-embedded images that have Caliber
                # file URL attributes <img src="file:\\..." with a new src with a relative URL
                # to a Rally attachment, once created

                # Count embedded images inside Caliber description
                caliber_image_count = @caliber_helper.count_images_in_caliber_description(this_testcase['description'])

                if caliber_image_count > 0 then
                    description_with_images = this_testcase['description']
                    image_file_objects, image_file_ids = @caliber_helper.get_caliber_image_files(description_with_images)
                    caliber_image_data = {
                        "files"       => image_file_objects,
                        "ids"         => image_file_ids,
                        "description" => description_with_images,
                        "ref"         => testcase["_ref"]
                    }
                    @rally_testcases_with_images_hash[testcase["ObjectID"].to_s] = caliber_image_data
                end

                # Record testcase data for CSV output
                this_testcase.each_pair do | key, value |
                    testcase_data << value
                end

                # Post-pend to CSV
                testcase_csv << CSV::Row.new($csv_testcase_fields, testcase_data)

                # Output testcase OID and Caliber tag name
                # So we can use this information later when importing traces
                testcase_oid_data << testcase_tag
                testcase_oid_data << testcase["ObjectID"]
                testcase_oid_data << testcase_name
                # Post-pend to CSV
                testcase_oid_csv  << CSV::Row.new($csv_testcase_oid_output_fields, testcase_oid_data)

                # Circuit-breaker for testing purposes
                if import_count < $max_import_count then
                    import_count += 1
                else
                    break
                end
            end
        end
    end

    # Only import into Rally if we're not in "preview_mode" for testing
    if $preview_mode then
        @logger.info "Finished Processing Caliber TestCases for import to Rally. Total TestCases Processed: #{import_count}."
    else
        @logger.info "Finished Importing Caliber TestCases to Rally. Total TestCases Created: #{import_count}."
    end

    # Run the hierarchy stitching service
    if $stitch_hierarchy then
        @caliber_helper.post_import_testcase_hierarchy_linker(@caliber_parent_hash,
            @rally_testcase_hierarchy_hash)
    end

    # Run the image import service
    # Necessary to run the image import as a post-TestCase creation service
    # Because we have to have an Artifact in Rally to attach _to_.
    if $import_images_flag
        @caliber_helper.import_images(@rally_testcases_with_images_hash)
    end
end

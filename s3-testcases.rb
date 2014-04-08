#!/usr/bin/env ruby

require 'base64'
require 'csv'
require 'nokogiri'
require 'uri'
require 'rally_api'
require 'logger'
require './caliber_helper.rb'
require './multi_io.rb'
require 'benchmark'
require 'debugger'
@jpwantsdebugger=true

if $my_delim == nil then $my_delim = "\t" end

# Load (and maybe override with) my personal/private variables from a file...
my_vars = "./my_vars.rb"
if FileTest.exist?( my_vars ) then 
    print "Sourcing #{my_vars}...\n"
    require my_vars
else
    print "File #{my_vars} not found; skipping require...\n"
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
$tag_Report                 = "Report"
$tag_ReqType                = "ReqType"
$tag_Requirement            = "Requirement"
$tag_UDAValues              = "UDAValues"
$tag_UDAValue               = "UDAValue"

# These are the value tags to look/parse for once on the <Requirement> tag
$requirement_name           = "name"
$requirement_hierarchy      = "hierarchy"
$requirement_id             = "id"
$requirement_validation     = "validation"

# In HTML mode, the tags are all lowercase so downcase them
if $html_mode then
    $tag_Report             = $tag_Report.downcase
    $tag_ReqType            = $tag_ReqType.downcase
    $tag_Requirement        = $tag_Requirement.downcase
    $tag_UDAValues          = $tag_UDAValues.downcase
    $tag_UDAValue           = $tag_UDAValue.downcase
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
#$uda_value_name_software_load            = "JDF Software Load"
#$uda_value_name_content_status           = "JDF Content Status"
$uda_value_name_remarks                  = "JDF Remarks [Re]"
$uda_value_name_testing_course           = "JDF Testing Course [Te]"
#$uda_value_name_include                  = "JDF Include"
#$uda_value_name_testing_status           = "JDF Testing Status"
#$uda_value_name_test_running             = "JDF Test Running"

$description_field_hash = {
    'Source [So]'             => 'source',
    'Purpose [Pu]'            => 'purpose',
    'Pre-condition [Pr]'      => 'pre_condition',
    'Testing Course [Te]'     => 'testing_course',
    'Validation'              => 'validation',
    'Description'             => 'description',
    'Post-condition [Po]'     => 'post_condition',
    'Remarks [Re]'            => 'remarks'
}

bm_time = Benchmark.measure {

#==================== Connect to Rally and Import Caliber data ====================

    # Instantiate Logger
    log_file = File.open($cal2ral_tc_log, "a")
    log_file.sync = true
    @logger = Logger.new MultiIO.new(STDOUT, log_file)

    @logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL

    if $preview_mode then
        @logger.info "----PREVIEW MODE----"
    end
   
    # Report vars
    @logger.info "Running #{$PROGRAM_NAME} with the following settings:
                $my_base_url                     = #{$my_base_url}
                $my_username                     = #{$my_username}
                $my_wsapi_version                = #{$my_wsapi_version}
                $my_workspace                    = #{$my_workspace}
                $my_project                      = #{$my_project}
                $max_attachment_length           = #{$max_attachment_length}
		        $max_description_length          = #{$max_description_length}
                $caliber_file_req                = #{$caliber_file_req}
                $caliber_file_req_traces         = #{$caliber_file_req_traces}
                $caliber_file_tc                 = #{$caliber_file_tc}
                $caliber_file_tc_traces          = #{$caliber_file_tc_traces}
                $caliber_image_directory         = #{$caliber_image_directory}
                $caliber_id_field_name           = #{$caliber_id_field_name}
                $caliber_weblink_field_name      = #{$caliber_weblink_field_name}
                $caliber_req_traces_field_name   = #{$caliber_req_traces_field_name}
                $caliber_tc_traces_field_name    = #{$caliber_tc_traces_field_name}
                $max_import_count                = #{$max_import_count}
                $html_mode                       = #{$html_mode}
                $preview_mode                    = #{$preview_mode}
                $csv_requirements                = #{$csv_requirements}
                $csv_story_oids_by_req           = #{$csv_story_oids_by_req}
                $csv_story_oids_by_req_fields    = #{$csv_story_oids_by_req_fields}
                $csv_testcases                   = #{$csv_testcases}
                $csv_testcase_oid_output         = #{$csv_testcase_oid_output}
                $csv_testcase_oid_output_fields  = #{$csv_testcase_oid_output_fields}
                $cal2ral_req_log                 = #{$cal2ral_req_log}
                $cal2ral_req_traces_log          = #{$cal2ral_req_traces_log}
                $cal2ral_tc_log                  = #{$cal2ral_tc_log}
                $cal2ral_tc_traces_log           = #{$cal2ral_tc_traces_log}
"

    # Set up custom headers for Rally connection
    $headers                    = RallyAPI::CustomHttpHeader.new()
    $headers.name               = "Caliber Testcase Importer"
    $headers.vendor             = "Rally Technical Services"
    $headers.version            = "0.50"

    config = {  :base_url       => $my_base_url,
                :username       => $my_username,
                :password       => $my_password,
                :workspace      => $my_workspace,
                :project        => $my_project,
                :version        => $my_wsapi_version,
                :headers        => $headers}

    @logger.info "Initiating connection to Rally at #{$my_base_url}..."
    @rally = RallyAPI::RallyRestJson.new(config)
 
    # Initialize Caliber Helper
    @caliber_helper = CaliberHelper.new(@rally, $caliber_project, $caliber_id_field_name,
        $description_field_hash, $caliber_image_directory, @logger, $caliber_weblink_field_name)

    # HTML Mode vs. XML Mode
    # The following is needed to preserve newlines in formatting of UDAValues when
    # Imported into Rally. Caliber export uses newlines in UDAValue attributes as formatting.
    # When importing straight XML, the newlines are ignored completely
    # Rally (and Nokogiri, really) needs markup. This step replaces newlines with <br>
    # And reads the resulting input as HTML rather than XML
    @logger.info "Opening for reading: XML data file '#{$caliber_file_tc}'"
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

    # Output CSV of TestCase data
    @logger.info "CSV file creation of #{$csv_testcases}..."
    testcase_csv = CSV.open($csv_testcases, "wb", {:col_sep => $my_delim})
    testcase_csv << $csv_testcase_fields

    # Output CSV of TestCase OID's by Caliber Requirement Name
    @logger.info "CSV file creation of #{$csv_testcase_oid_output}..."
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

    tags_report = caliber_data.search($tag_Report)
    tags_report.each_with_index do | this_Report, indx_Report | #{
        @logger.info "<Report ...> tag #{indx_Report+1} of #{tags_report.length}: project=\"#{this_Report['project']}\" date=\"#{this_Report['date']}\""

        tags_reqtype = this_Report.search($tag_ReqType)
        tags_reqtype.each_with_index do | this_ReqType, indx_ReqType | #{

            if this_ReqType['name'] == "JDF Test Case (TC)" then
                @logger.info "    <ReqType ...> tag #{indx_ReqType+1} of #{tags_reqtype.length}: name=\"#{this_ReqType['name']}\" sort_by=\"#{this_ReqType['sort_by']}\""
            else
                @logger.info "    Ignoring <ReqType ...> tag with name=\"#{this_ReqType['name']}\""
                next           
            end
            
            total_tc = 0
            tags_requirement = this_ReqType.search($tag_Requirement)
                tags_requirement.each_with_index do | this_Requirement, indx_Requirement | #{

                @logger.info "        <Requirement ...> tag #{indx_Requirement+1} of #{tags_requirement.length}: index=\"#{this_Requirement['index']}\"\ id=\"#{this_Requirement['id']}\" tag=\"#{this_Requirement['tag']}\" hierarchy=\"#{this_Requirement['hierarchy']}\" name=\"#{this_Requirement['name']}\""

                # Data - holds output for CSV
                testcase_data                        = []
                testcase_oid_data                    = []

                # Store fields that derive from Project and Requirement objects
                this_testcase                        = {}
                this_testcase['project']             = this_Report['project']
                this_testcase['hierarchy']           = this_Requirement['hierarchy']
                this_testcase['id']                  = this_Requirement['id']
                this_testcase['tag']                 = this_Requirement['tag']
                this_testcase['name']                = this_Requirement['name'] || ""

                # process_description_body pulls HTML content out of <html><body> tags
                this_testcase['description']         = @caliber_helper.process_description_body(this_Requirement['description'] || "")
                this_testcase['validation']          = @caliber_helper.process_description_body(this_Requirement['validation'] || "")

                # Store Caliber ID, HierarchyID, Project and Name in variables for convenient logging output
                testcase_id                          = this_Requirement['id']
                testcase_tag                         = this_Requirement['tag']
                testcase_hierarchy                   = this_Requirement['hierarchy']
                testcase_project                     = this_Report['project']
                testcase_name                        = this_Requirement['name']

                #@logger.info "Started Reading Caliber TestCase ID: #{testcase_id}; Hierarchy: #{testcase_hierarchy}; Project: #{testcase_project}"

                # Loop through UDAValue records and cache fields from them
                # There are many UDAValue records per testcase and each is different
                # So assign to values of interest via case statement

                this_Requirement.search($tag_UDAValues ).each_with_index do | this_UDAValues, indx_UDAValues | #{
                    this_UDAValues.search($tag_UDAValue).each_with_index do | this_UDAValue, indx_UDAValue | #{
                        uda_value_name = this_UDAValue['name']
                        uda_value_value = this_UDAValue['value'] || ""
                        uda_stat="used   "
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
                            #when $uda_value_name_software_load
                            #    this_testcase['software_load']      = uda_value_value
                            #when $uda_value_name_content_status
                            #    this_testcase['content_status']     = uda_value_value
                            #when $uda_value_name_include
                            #    this_testcase['include']            = uda_value_value
                            #when $uda_value_name_testing_status
                            #    this_testcase['testing_status']     = uda_value_value
                            #when $uda_value_name_test_running
                            #    this_testcase['test_running']       = uda_value_value
                            else
                                uda_stat="ignored"
                        end
                        @logger.info "            <UDAValue ...> tag #{indx_UDAValue+1} of #{this_UDAValues.children.count}: #{uda_stat} name='#{uda_value_name}'"

                    end #} end of "this_UDAValues.search($tag_UDAValue).each_with_index do | this_UDAValue, indx_UDAValue |"

                end #} end of "this_Requirement.search($tag_UDAValues ).each do | this_UDAValues |"

                #@logger.info "    Finished Reading Caliber TestCase ID: #{testcase_id}; Hierarchy: #{testcase_hierarchy}; Project: #{testcase_project}"

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
                    total_tc = total_tc + 1
                    @logger.info "            Created Rally TestCase #{total_tc} of #{tags_requirement.length}:  FmtID=#{testcase.FormattedID}; OID=#{testcase.ObjectID}; from Caliber Requirement id=#{this_Requirement['id']}"
                end

                # Save the TestCase OID and associated it to the Caliber Hierarchy ID for later use
                # in stitching
                @rally_testcase_hierarchy_hash[testcase_hierarchy] = testcase

                # Get the Parent hierarchy ID for this Caliber Requirement
                parent_hierarchy_id = @caliber_helper.get_parent_hierarchy_id(this_testcase)
                #@logger.info "    Parent Hierarchy ID: #{parent_hierarchy_id}"

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

                if caliber_image_count < 1 then
                    @logger.info "            No images found for this Requirement."
                else
                    description_with_images = this_testcase['description']
                    image_file_objects, image_file_ids, image_file_titles = @caliber_helper.get_caliber_image_files(description_with_images)
                    caliber_image_data = {
                        "files"         => image_file_objects,
                        "ids"           => image_file_ids,
                        "titles"        => image_file_titles,
                        "description"   => description_with_images,
                        "fmtid"         => testcase["FormattedID"],
                        "ref"           => testcase["_ref"]
                    }
                    @logger.info "            Adding #{caliber_image_count} images to hash for later processing; id(s)=#{image_file_titles}."
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
                testcase_oid_data << testcase["FormattedID"]
                testcase_oid_data << testcase_name
                # Post-pend to CSV
                testcase_oid_csv  << CSV::Row.new($csv_testcase_oid_output_fields, testcase_oid_data)

                # Circuit-breaker for testing purposes
                if import_count < $max_import_count-1 then
                    import_count += 1
                else
                    @logger.info "Stopping import; 'import_count' reached #{import_count+1} ($max_import_count)"
                    break
                end

            end #} end of "this_ReqType.search($tag_Requirement).each_with_index do | this_Requirement, indx_Requirement |"

        end #} end of "tags_reqtype.each_with_index do | this_ReqType, indx_ReqType |"

    end #} end of "tags_report.each_with_index do | this_Report, indx_Report |"

    # Only import into Rally if we're not in "preview_mode" for testing
    if $preview_mode then
        @logger.info "Finished Processing Caliber TestCases for import to Rally. Total TestCases Processed: #{import_count}."
    else
        @logger.info "Finished Importing Caliber TestCases to Rally. Total TestCases Created: #{import_count}."
    end

    # Run the hierarchy stitching service
    if $stitch_hierarchy then
        @caliber_helper.post_import_testcase_hierarchy_linker(@caliber_parent_hash, @rally_testcase_hierarchy_hash)
    end

    # Run the image import service
    # Necessary to run the image import as a post-TestCase creation service
    # Because we have to have an Artifact in Rally to attach _to_.
    if $import_images_flag
        @caliber_helper.import_images(@rally_testcases_with_images_hash)
    end

    @logger.show_msg_stats

}

@logger.info ""
@logger.info "This script (#{$PROGRAM_NAME}) is finished; benchmark time in seconds:"
@logger.info "  --User--   -System-   --Total-  --Elapsed-"
@logger.info bm_time.to_s

exit (0)

#the end#

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
    $import_to_rally            = false
    $stitch_hierarchy           = false
    $import_images_flag         = false
else
    $import_to_rally            = true
    $stitch_hierarchy           = true
    $import_images_flag         = true
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

# These are the value tags to look/parse for once on the <Requirement> tag
$requirement_hierarchy      = "hierarchy"
$requirement_id             = "id"
$requirement_name           = "name"
$requirement_validation     = "validation"

# Tags of interest
$tag_Report                 = "Report"
$tag_ReqType                = "ReqType"
$tag_Requirement            = "Requirement"
$tag_UDAValues              = "UDAValues"
$tag_UDAValue               = "UDAValue"

# In HTML mode, the tags are all lowercase so downcase them
if $html_mode then
    $tag_Report             = $tag_Report.downcase
    $tag_ReqType            = $tag_ReqType.downcase
    $tag_Requirement        = $tag_Requirement.downcase
    $tag_UDAValues          = $tag_UDAValues.downcase
    $tag_UDAValue           = $tag_UDAValue.downcase
end

# The following are all types of <UDAValue> records on <Requirement>
# Example:
# <UDAValue id="4241" req_id="20023" name="JDF Purpose [Pu]" value="This is not a requirement but a chapter title."/>
# <UDAValue id="4242" req_id="20023" name="JDF Basic Course [Ba]" value="Operating harvester head involves
# - closing harvester head
# - opening harvester head
# "/>
# <UDAValue id="4243" req_id="20023" name="JDF Post-condition [Po]" value="None."/>
# <UDAValue id="4244" req_id="20023" name="JDF Exceptions [Ex]" value="None."/>
# <UDAValue id="4245" req_id="20023" name="JDF Machine Type" value="Harvester"/>
# <UDAValue id="4246" req_id="20023" name="JDF Input [In]" value="None."/>
# <UDAValue id="4247" req_id="20023" name="JDF Project" value="5.0"/>
# <UDAValue id="4248" req_id="20023" name="JDF Content Status" value="5. Approved"/>
# <UDAValue id="4249" req_id="20023" name="JDF Delivery Status" value="UNDEFINED"/>
# <UDAValue id="4250" req_id="20023" name="JDF Output [Ou]" value="None."/>
# <UDAValue id="4251" req_id="20023" name="JDF Open Issues" value=""/>
# <UDAValue id="4252" req_id="20023" name="JDF Remarks [Re]" value="None."/>
# <UDAValue id="4253" req_id="20023" name="JDF Requirement Class" value="High level"/>
# <UDAValue id="4254" req_id="20023" name="JDF Source [So]" value="PAi &amp; Ilari V"/>
# <UDAValue id="4255" req_id="20023" name="JDF Pre-condition [Pr]" value="None."/>
# <UDAValue id="4256" req_id="20023" name="JDF Software Load" value="3"/>
# </UDAValues>

# These are the value fields to look/parse for once on the <UDAValues> tag
#$uda_value_name_purpose        = "JDF Purpose [So]"        #01
 $uda_value_name_purpose        = "JDF Purpose [Pu]"        #02
 $uda_value_name_pre_condition  = "JDF Pre-condition [Pr]"  #03
 $uda_value_name_basic_course   = "JDF Basic Course [Ba]"   #04
 $uda_value_name_post_condition = "JDF Post-condition [Po]" #05
 $uda_value_name_exceptions     = "JDF Exceptions [Ex]"     #06
 $uda_value_name_remarks        = "JDF Remarks [Re]"        #09
 $uda_value_name_input          = "JDF Input [In]"          #07
 $uda_value_name_output         = "JDF Output [Ou]"         #08
#$uda_value_name_project        = "JDF Project"             #10
#$uda_value_name_software       = "JDF Software Load"       #11
#$uda_value_name_content        = "JDF Content Status"      #12
#$uda_value_name_delivery       = "JDF Delivery Status"     #13
#$uda_value_name_requirement    = "JDF Requirement Class"   #14
#$uda_value_name_machine_type   = "JDF Machine Type"        #15
 $uda_value_name_open_issues    = "JDF Open Issues"         #16

$description_field_hash         = {
        'Caliber Purpose'       => 'caliber_purpose',
        'Pre-condition'         => 'pre_condition',
        'Basic course'          => 'basic_course',
        'Post-condition'        => 'post_condition',
        'Exceptions'            => 'exceptions',
        'Description'           => 'description'
}

$description_field_hash_ZeusCtl = {
        'Validation'            => 'validation',
        'Input'                 => 'input',
        'Output'                => 'output'
}

$notes_field_hash         = {
        'Remarks'               => 'remarks'
}

bm_time = Benchmark.measure {

#==================== Connect to Rally and Import Caliber data ====================

    # Instantiate Logger
    log_file = File.open($cal2ral_req_log, "a")
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
    $headers.name               = "Caliber Requirement Importer"
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
        $description_field_hash, $caliber_image_directory, @logger, nil)

    # Output CSV of Requirement data
    @logger.info "CSV file creation of #{$csv_requirements}..."
    requirements_csv = CSV.open($csv_requirements, "wb", {:col_sep => $my_delim})
    requirements_csv << $csv_requirement_fields

    # Output CSV of Story OID's by Caliber Requirement Name
    @logger.info "CSV file creation of #{$csv_story_oids_by_req}..."
    story_oid_csv    = CSV.open($csv_story_oids_by_req, "wb", {:col_sep => $my_delim})
    story_oid_csv    << $csv_story_oids_by_req_fields

    # HTML Mode vs. XML Mode
    # The following is needed to preserve newlines in formatting of UDAValues when
    # Imported into Rally. Caliber export uses newlines in UDAValue attributes as formatting.
    # When importing straight XML, the newlines are ignored completely
    # Rally (and Nokogiri, really) needs markup. This step replaces newlines with <br>
    # And reads the resulting input as HTML rather than XML
    @logger.info "Opening for reading: XML data file '#{$caliber_file_req}'"
    caliber_file = File.open($caliber_file_req, 'rb')
    caliber_content = caliber_file.read

    caliber_content_html = caliber_content.gsub("\n", "&lt;br/&gt;\n")

    if $html_mode then
        caliber_data = Nokogiri::HTML(caliber_content_html, 'UTF-8') do | config |
            config.strict
        end
    else
        caliber_data = Nokogiri::XML(File.open($caliber_file_req), 'UTF-8') do | config |
            config.strict
        end
    end

    # The following are used for the post-run stitching
    # Hash of User Stories keyed by Caliber Requirement Hierarchy ID
    @rally_story_hierarchy_hash = {}

    # The following are used for the post-run import of images for
    # Caliber requirements whose description contains embedded images
    @rally_stories_with_images_hash = {}

    # Hash of Requirement Parent Hierarchy ID's keyed by Self Hierarchy ID
    @caliber_parent_hash = {}

    # Read through caliber file and store requirement records in array of requirement hashes
    import_count = 0

    tags_report = caliber_data.search($tag_Report)
    tags_report.each_with_index do | this_Report, indx_Report | #{
        @logger.info "<Report ...> tag #{indx_Report+1} of #{tags_report.length}: project=\"#{this_Report['project']}\" date=\"#{this_Report['date']}\""

        tags_reqtype = this_Report.search($tag_ReqType)
        tags_reqtype.each_with_index do | this_ReqType, indx_ReqType | #{

            if this_ReqType['name'] == "JDF Requirement (REQ)" then
                @logger.info "    <ReqType ...> tag #{indx_ReqType+1} of #{tags_reqtype.length}: name=\"#{this_ReqType['name']}\" sort_by=\"#{this_ReqType['sort_by']}\""
            else
                @logger.warn "*** Ignoring <ReqType ...> tag with name=\"#{this_ReqType['name']}\""
                next           
            end
            
            total_us = 0
        tags_requirement = this_ReqType.search($tag_Requirement)
            tags_requirement.each_with_index do | this_Requirement, indx_Requirement | #{
                @logger.info "        <Requirement ...> tag #{indx_Requirement+1} of #{tags_requirement.length}: index=\"#{this_Requirement['index']}\"\ id=\"#{this_Requirement['id']}\" tag=\"#{this_Requirement['tag']}\" hierarchy=\"#{this_Requirement['hierarchy']}\" name=\"#{this_Requirement['name']}\""

                # Data - holds output for CSV
                requirement_data = []
                story_oid_data   = []

                # Store fields that derive from Project and Requirement objects
                current_req                    = {}
                current_req['project']         = this_Report['project']
                current_req['hierarchy']       = this_Requirement['hierarchy']
                current_req['id']              = this_Requirement['id']
                current_req['name']            = this_Requirement['name'] || ""

                # process_description_body pulls HTML content out of <html><body> tags
                current_req['description']     = @caliber_helper.process_description_body(this_Requirement['description'] || "")
                #current_req['validation']      = this_Requirement['validation'] || ""

                # Store Caliber ID, HierarchyID, Project and Name in variables for convenient logging output
                req_id                              = current_req['id']
                req_hierarchy                       = current_req['hierarchy']
                req_project                         = current_req['project']
                req_name                            = current_req['name']


                # Loop through UDAValue records and cache fields from them
                # There are many UDAValue records per requirement and each is different
                # So assign to values of interest via case statement
                this_Requirement.search($tag_UDAValues).each_with_index do | uda_values, indx_values |

                    uda_values.search($tag_UDAValue).each_with_index do | uda_value, indx_value |
                        uda_value_name = uda_value['name']
                        uda_value_value = uda_value['value'] || ""
                        uda_stat="used   "
                        case uda_value_name
                            when $uda_value_name_purpose
                                current_req['caliber_purpose']    = uda_value_value
                            when $uda_value_name_pre_condition
                                current_req['pre_condition']      = uda_value_value
                            when $uda_value_name_basic_course
                                current_req['basic_course']       = uda_value_value
                            when $uda_value_name_post_condition
                                current_req['post_condition']     = uda_value_value
                            when $uda_value_name_exceptions
                                current_req['exceptions']         = uda_value_value
                            when $uda_value_name_remarks
                                current_req['remarks']            = uda_value_value
                            when $uda_value_name_open_issues
                                current_req['open_issues']        = uda_value_value
                            when $uda_value_name_input
                                current_req['input']              = uda_value_value
                            when $uda_value_name_output
                                current_req['output']             = uda_value_value
                            else
                                uda_stat="ignored"
                        end
                        @logger.info "            <UDAValue ...> tag #{indx_value+1} of #{uda_values.children.count}: #{uda_stat} name='#{uda_value_name}'"
                    end
                end

                # Dummy story used only when testing
                story = {
                    "ObjectID"       => 12345678910,
                    "FormattedID"    => "US1234",
                    "Name"           => "My Story",
                    "Description"    => "My Description",
                    "_ref"           => "/hierarchicalrequirement/12345678910"
                }

                # Import to Rally
                if $import_to_rally then
                    story = @caliber_helper.create_story_from_caliber(current_req)
            total_us = total_us + 1
                    @logger.info "            Created Rally UserStory #{total_us} of #{tags_requirement.length}: FmtID=#{story.FormattedID}; OID=#{story.ObjectID}; from Caliber Requirement id=#{this_Requirement['id']}"
                end

                # Save the Story OID and associate it to the Caliber Hierarchy ID for later use in stitching
                @rally_story_hierarchy_hash[req_hierarchy] = story
            

                # Get the Parent hierarchy ID for this Caliber Requirement
                parent_hierarchy_id = @caliber_helper.get_parent_hierarchy_id(current_req)

                # Store the requirements Parent Hierarchy ID for use in stitching
                @caliber_parent_hash[req_hierarchy] = parent_hierarchy_id

                # store a hash containing:
                # - Caliber description field
                # - Array of caliber image file objects in Story hash
                #
                # For later use in post-processing run to import images
                # This allows us to import the images onto Rally stories by OID, and
                # Update the Rally Story Description-embedded images that have Caliber
                # file URL attributes <img src="file:\\..." with a new src with a relative URL
                # to a Rally attachment, once created

                # Count embedded images inside Caliber description
                caliber_image_count = @caliber_helper.count_images_in_caliber_description(current_req['description'])

                if caliber_image_count < 1 then
                    @logger.info "            No images found for this Requirement."
                else
                    #description_with_images = current_req['description']
                    description_with_images = story.elements[:description]  # jp chasing bug
                    image_file_objects, image_file_ids, image_file_titles = @caliber_helper.get_caliber_image_files(description_with_images)
                    caliber_image_data = {
                        "files"         => image_file_objects,
                        "ids"           => image_file_ids,
                        "titles"        => image_file_titles,
                        "description"   => description_with_images,
                        "fmtid"         => story["FormattedID"],
                        "ref"           => story["_ref"]
                    }
                    @logger.info "            Adding #{caliber_image_count} images to hash for later processing; id(s)=#{image_file_titles}"
                    @rally_stories_with_images_hash[story["ObjectID"].to_s] = caliber_image_data
                end

                # Record requirement data for CSV output
                current_req.each_pair do | key, value |
                    requirement_data << value
                end

                # Post-pend to CSV
                requirements_csv << CSV::Row.new($csv_requirement_fields, requirement_data)

                # Output story OID and Caliber requirement name
                # So we can use this information later when importing traces
                story_oid_data << story["FormattedID"]
                story_oid_data << story["ObjectID"]
                story_oid_data << req_id
                story_oid_data << req_name

                # Post-pend to CSV
                story_oid_csv  << CSV::Row.new($csv_story_oids_by_req_fields, story_oid_data)

                # Circuit-breaker for testing purposes
                if import_count < $max_import_count-1 then
                    import_count += 1
                else
                    @logger.info "Stopping import; 'import_count' reached #{import_count+1} ($max_import_count)"
                    break
                end

            end #} end of "tags_requirement.search($tag_Requirement).each_with_index do | this_Requirement, indx_Requirement |"

        end #} end of "tags_reqtype.each_with_index do | this_ReqType, indx_ReqType |"

    end #} end of "tags_report.each_with_index do | this_Report, indx_Report |"

    # Only import into Rally if we're not in "preview_mode" for testing
    if $preview_mode then
        @logger.info "Finished Processing Caliber Requirements for import to Rally. Total Stories Processed: #{import_count}."
    else
        @logger.info "Finished importing Caliber Requirements; total Rally User Stories created: #{import_count}."
    end

    # Run the hierarchy stitching service
    if $stitch_hierarchy then
        @caliber_helper.post_import_hierarchy_stitch(@caliber_parent_hash, @rally_story_hierarchy_hash)
    end

    # Run the image import service
    # Necessary to run the image import as a post-Story creation service
    # Because we have to have an Artifact in Rally to attach _to_.
    if $import_images_flag
        @caliber_helper.import_images(@rally_stories_with_images_hash)
    end

    @logger.show_msg_stats

}

@logger.info ""
@logger.info "This script (#{$PROGRAM_NAME}) is finished; benchmark time in seconds:"
@logger.info "  --User--   -System-   --Total-  --Elapsed-"
@logger.info bm_time.to_s

exit (0)

#the end#

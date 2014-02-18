#!/usr/bin/env ruby

require 'base64'
require 'csv'
require 'nokogiri'
require 'uri'
require 'rally_api'
require 'logger'
require './multi_io.rb'
require 'debugger'
@jpwantsdebugger=true

# Rally Connection parameters
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "topsecret"
$my_wsapi_version                = "1.43"
$my_workspace                    = "My Workspace"
$my_project                      = "My Project"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_req_traces         = "hhc_traces.xml"
$caliber_req_traces_field_name   = 'Externalreference'

# Runtime preferences
$max_import_count                = 100000
$preview_mode                    = false

if $my_delim == nil then $my_delim = "\t" end

# Load (and maybe override with) my personal/private variables from a file...
my_vars = "./my_vars.rb"
if FileTest.exist?( my_vars ) then
        print "Sourcing #{my_vars}...\n"
        require my_vars
else
        print "File #{my_vars} not found...\n"
end


# set preview mode
if $preview_mode then
    $import_to_rally                 = false
else
    $import_to_rally                 = true
end

# The following are all attributes inside the Traces file itself.
# Example:
# <Report date="6.9.2013">
# <Traceability name="Tilting up when opening" columns="45">
# <Trace name="" type="-1" col="0"/>
# <Trace name="Opening harvester head" type="2" col="1"/>
# <Trace name="Manual fell or reference cut" type="-1" col="2"/>
# <Trace name="Auto cut mode 1" type="-1" col="3"/>
# <Trace name="Manual harvesting by saw" type="-1" col="4"/>
# </Traceability>
# </Report>

# Tags of interest
$report_tag         = "Report"

# The name attribute of the Traceability tag is the name of the
# Caliber Requirement to which this set of Traces corresponds
$traceability_tag   = "Traceability"
$trace_tag          = "Trace"

def cache_story_oid(header, row)
    req_name        = row[header[0]].strip  # Name
    story_oid       = row[header[1]].strip  # Rally ObjectID
    story_fid       = row[header[2]].strip  # Rally FormattedID
    caliber_id      = row[header[3]].strip  # Caliber ID

    if !req_name.eql? nil then
        @story_oid_by_reqname[req_name] = [story_oid.to_s, story_fid.to_s, caliber_id.to_s]
    end
end

def create_traces_text_from_traces_array(traces_array)
    rally_host = $my_base_url.split("/")[-2]
    detail_url_prefix = "https://#{rally_host}/#/detail/userstory"
    traces_markup = '<p><b>Caliber TRACES</b></p><br/>'
    trace_counter = 1
    traces_array.each do | this_trace |
        story_oid = @story_oid_by_reqname[this_trace]
            if !story_oid.nil? then
                this_trace_name = this_trace
                story_url_detail = "#{detail_url_prefix}/#{story_oid}"
                this_trace = "<a href=\"#{story_url_detail}\">#{this_trace_name}</a>"
            end
        
            traces_markup += trace_counter.to_s + ". "
            traces_markup += this_trace
            traces_markup += '<br/>'
            trace_counter += 1
        end 
    return traces_markup
end

# Take Caliber traces array, process and combine field data and import into corresponding Rally Story
def update_story_with_caliber_traces(story_oid, req_name, traces_text)

    #@logger.info "    Updating Rally Story ObjectID: #{story_oid} with Caliber Traces from Requirement: #{req_name}"

    update_fields                                 = {}
    update_fields[$caliber_req_traces_field_name] = traces_text
    begin
        @rally.update("hierarchicalrequirement", story_oid, update_fields)
        #@logger.info "    Successfully Imported Caliber Traces for Rally Story: ObjectID #{story_oid}."
    rescue => ex
        @logger.error "Error occurred attempting to Import Caliber Traces to Rally Story: ObjectID #{story_oid}."
        @logger.error ex.message
        @logger.error ex.backtrace
    end
end

begin

#==================== Connect to Rally and Import Caliber data ====================

    # Instantiate Logger
    log_file = File.open($cal2ral_req_traces_log, "a")
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
                $no_parent_id                    = #{$no_parent_id}
                $csv_requirements                = #{$csv_requirements}
                $csv_requirement_fields          = #{$csv_requirement_fields}
                $csv_story_oids_by_req           = #{$csv_story_oids_by_req}
                $csv_story_oids_by_req_fields    = #{$csv_story_oids_by_req_fields}
                $csv_testcases                   = #{$csv_testcases}
                $csv_testcase_fields             = #{$csv_testcase_fields}
                $csv_testcase_oid_output         = #{$csv_testcase_oid_output}
                $csv_testcase_oid_output_fields  = #{$csv_testcase_oid_output_fields}
                $cal2ral_req_log                 = #{$cal2ral_req_log}
                $cal2ral_req_traces_log          = #{$cal2ral_req_traces_log}
                $cal2ral_tc_log                  = #{$cal2ral_tc_log}
                $cal2ral_tc_traces_log           = #{$cal2ral_tc_traces_log}
                $description_field_hash          = #{$description_field_hash}"

    # Set up custom headers for Rally connection
    $headers                    = RallyAPI::CustomHttpHeader.new()
    $headers.name               = "Caliber Requirement Traces Importer"
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

    @logger.info "Opening for reading XML data file #{$caliber_file_req_traces}..."
    caliber_data = Nokogiri::XML(File.open($caliber_file_req_traces), 'UTF-8') do | config |
        config.strict
    end

    # Hash to provide a lookup from Caliber reqname -> Rally Story OID
    @story_oid_by_reqname = {}

    # Read in cached reqname -> Story OID mapping from file
    @logger.info "CSV file reading/caching requirement-name --> Story-OID mapping from #{$csv_story_oids_by_req}..."
    input  = CSV.read($csv_story_oids_by_req,  {:col_sep => $my_delim})

    header = input.first #ignores first line
    rows   = []
    (1...input.size).each { |i| rows << CSV::Row.new(header, input[i])}
    @logger.info "    Found #{rows.length} rows of data"
    number_processed = 0

    # Proceed through rows in input CSV and store reqname -> story OID lookup in a hash
    @logger.info "    Building a CSV hash of Rally UserStory ObjectID's by Caliber Requirement Name (for traces import)..."
    rows.each do |row|
        cache_story_oid(header, row)
        number_processed += 1
    end

    # Read through caliber file and store requirement records in array of requirement hashes
    import_count = 0
    #caliber_data.search($report_tag).each do | report |
        #report.search($traceability_tag).each do | traceability |

    #caliber_data.search("JDrequestTraces").each_with_index do | report, indx_report |
        #@logger.info "Processing <JDrequestTraces> tag #{indx_report+1}..."

        #report.search("JDrequest").each_with_index do | traceability, indx_trace |
            #@logger.info "    Processing <JDrequest> tag #{indx_trace+1}..."

        JDrequests = caliber_data.xpath("JDrequestTraces/JDrequest")

        JDrequests.each_with_index do |r, indx_r|
            trace_JDid   = r.at_xpath('JDid').text
            trace_JDname = r.at_xpath('JDname').text

            @logger.info "Processing Trace #{indx_r+1}; JDid=#{trace_JDid}; JDname='#{trace_JDname}'"
        
            trace_array     = []
            story_oid       = @story_oid_by_reqname[trace_JDname][0]    # Rally ObjectID
            story_fid       = @story_oid_by_reqname[trace_JDname][1]    # Rally FormattedID
            caliber_id      = @story_oid_by_reqname[trace_JDname][2]    # Caliber ID

            if story_oid.nil? then
                @logger.warn "    Can't find Rally UserStory; FormattedID=#{story_fid}; ObjectID=#{story_oid}. Skipping import of this trace."
                next
            else
                @logger.info "    Found Rally UserStory; FormattedID=#{story_fid}; ObjectID=#{story_oid}"
            end

            #traceability.search($trace_tag).each do | this_trace |
            #    trace_name                             = this_trace['name']
            #    if !trace_name.eql?("") then
            #        trace_array.push(trace_name)
            #    end
            #end

            if !trace_JDname.eql?("") then
                trace_array.push(trace_JDname)
            end

            # Create traces text for import to rally
            traces_text = create_traces_text_from_traces_array(trace_array)

            if $preview_mode then
                @logger.info "    Rally Story ObjectID: #{story_oid} needs updated with #{trace_array.length} Caliber Traces from Requirement: #{trace_JDname}"
            else
                update_story_with_caliber_traces(story_oid, trace_JDname, traces_text)
                #@logger.info "    Updating Rally Story ObjectID: #{story_oid} with Caliber Traces from Requirement: #{req_name}"
                @logger.info "    Successfully Imported Caliber Traces for Rally UserStory."
            end

            # Circuit-breaker for testing purposes
            if import_count < $max_import_count then
                import_count += 1
            else
                break
            end
        end
    
    # Only import into Rally if we're not in "preview_mode" for testing
    if $preview_mode then
        @logger.info "Finished Processing Caliber Requirement Traces for import to Rally."
        @logger.info "Total Traces Processed: #{import_count}."
    else
        @logger.info "Finished Importing Caliber Requirement Traces to Rally."
        @logger.info "Total Traces Created: #{import_count}."
    end

end
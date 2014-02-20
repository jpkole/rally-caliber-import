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
$caliber_file_tc_traces         = "jdf_testcase_traces_zeuscontrol.xml"
$caliber_tc_traces_field_name   = 'Externalreference'

# Runtime preferences
$max_import_count               = 100000
$preview_mode                   = false

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
    $import_to_rally        = false
else
    $import_to_rally        = true
end

# The following are all attributes inside the Traces file itself.
# Example:
# <JDrequestTraces>
#   <JDrequest>
#     <JDid>TC19444</JDid>
#     <JDname>MANUAL CABIN LEVELLING</JDname>
#     <JDtracefrom>
#     </JDtracefrom>
#     <JDtraceto>
#     </JDtraceto>
#   </JDrequest>
#   <JDrequest>
#     <JDid>TC19445</JDid>
#     <JDname>Manual cabin levelling (x,y directions)</JDname>
#     <JDtracefrom>
#       <JDtrace>
#         <JDtraceId>REQ18781</JDtraceId>
#         <JDtraceName>Manual cabin levelling (x,y directions)</JDtraceName>
#       </JDtrace>
#     </JDtracefrom>
#     <JDtraceto>
#       <JDtrace>
#         <JDtraceId>TC27376</JDtraceId>
#         <JDtraceName>Manual Cabin Levelling; Steer Prevent Switch Pre-condition</JDtraceName>
#       </JDtrace>
#     </JDtraceto>
#   </JDrequest>
# </JDrequestTraces>


# Tags of interest
$jdrequesttraces_tag        = "JDrequestTraces"

# The name attribute of the Traceability tag is the name of the
# Caliber Requirement to which this set of Traces corresponds
$jdrequest_tag              = "JDrequest"

# This contains the Caliber ID of the testcase to which we want to associate the traces.
$jdid_tag                   = "JDid"
$jdname_tag                 = "JDname"

# Traces From/To
$jdtracefrom_tag            = "JDtracefrom"
$jdtraceto_tag              = "JDtraceto"

# Trace
$jdtrace_tag                = "JDtrace"

#TraceID
$jdtraceid_tag              = "JDtraceId"
$jdtracename_tag            = "JDtraceName"

def cache_testcase_oid(header, row)
    testcase_id             = row[header[0]].strip
    testcase_oid            = row[header[1]].strip
    testcase_fid            = row[header[2]].strip
    testcase_name           = row[header[3]].strip

    if !testcase_id.eql? nil then
        @testcase_oid_by_caliber_testcase_id[testcase_id] = testcase_oid.to_s
    end
    if !testcase_name.eql? nil then
        @testcase_name_by_caliber_testcase_id[testcase_id] = testcase_name
    end

end

def cache_story_oid(header, row)
    story_fid               = row[header[0]].strip
    story_oid               = row[header[1]].strip
    req_id                  = row[header[2]].strip
    req_name                = row[header[3]].strip

    if !req_id.eql? nil then
        @story_oid_by_reqid[req_id] = story_oid.to_s
    end
    if !req_name.eql? nil then
        @req_name_by_reqid[req_id] = req_name
    end
end

def create_traces_markup_from_traces_array(traces_array) #{

    rally_host = $my_base_url.split("/")[-2]
    story_detail_url_prefix    = "https://#{rally_host}/#/detail/userstory"
    testcase_detail_url_prefix = "https://#{rally_host}/#/detail/testcase"
    traces_markup = '<p><b>Caliber TRACES</b></p><br/>'
    trace_counter = 1

    traces_array.each do | this_traceid |

        is_testcase = this_traceid.match(/^TC/)
        is_requirement = this_traceid.match(/^REQ/)

        if !is_testcase.nil? then
            testcase_oid = @testcase_oid_by_caliber_testcase_id[this_traceid]

            if testcase_oid.nil? then
                @logger.warn "No Rally TestCase ObjectID found for Caliber TestCase ID: #{this_traceid} - skipping linkage of this Trace."
                this_trace = @testcase_name_by_caliber_testcase_id[this_traceid] || this_traceid
            else
                @logger.info "Rally TestCase ObjectID: #{testcase_oid} found for Caliber TestCase ID: #{this_traceid} - linking Trace to TestCase: #{testcase_oid}"
                this_trace_name = @testcase_name_by_caliber_testcase_id[testcase_oid] || this_traceid

                detail_url = "#{testcase_detail_url_prefix}/#{testcase_oid}"
                this_trace = "<a href=\"#{detail_url}\">#{this_trace_name}</a>"
            end
            traces_markup += trace_counter.to_s + ". "
            traces_markup += this_trace
            traces_markup += '<br/>'
            trace_counter += 1
        end

        if !is_requirement.nil? then
            story_oid = @story_oid_by_reqid[this_traceid]
            if story_oid.nil? then
                @logger.warn "No Rally Story ObjectID found for Caliber Requirement ID: #{this_traceid} - skipping linkage of this Trace."
                this_trace = @req_name_by_reqid[this_traceid] || this_traceid
            else
                @logger.info "Rally Story ObjectID: #{story_oid} found for Caliber Requirement ID: #{this_traceid} - linking Trace to Story: #{story_oid}"
                this_trace_name = @req_name_by_reqid[this_traceid] || this_traceid

                detail_url = "#{story_detail_url_prefix}/#{story_oid}"
                this_trace = "<a href=\"#{detail_url}\">#{this_trace_name}</a>"
            end
            traces_markup += trace_counter.to_s + ". "
            traces_markup += this_trace
            traces_markup += '<br/>'
            trace_counter += 1
        end
    end
    return traces_markup
end #} end of "def create_traces_markup_from_traces_array(traces_array)"

# Take Caliber traces array, process and combine field data and import into corresponding Rally Story
def update_testcase_with_caliber_traces(testcase_oid, testcase_id, traces_text)

    @logger.info "Updating Rally TestCase ObjectID: #{testcase_oid} with Traces from Caliber TestCase: #{testcase_id}"

    update_fields                                = {}
    update_fields[$caliber_tc_traces_field_name] = traces_text
    begin
        @rally.update("testcase", testcase_oid, update_fields)
        @logger.info "    Successfully Imported Caliber Traces for Rally TestCase: ObjectID #{testcase_oid}"
    rescue => ex
        @logger.error "Error occurred attempting to Import Caliber Traces to Rally Story: ObjectID #{testcase_oid}"
        @logger.error ex.message
        @logger.error ex.backtrace
    end
end

begin

#==================== Connect to Rally and Import Caliber data ====================

    # Instantiate Logger
    log_file = File.open($cal2ral_tc_traces_log, "a")
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
    $headers.name               = "Caliber Testcase Traces Importer"
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

    ############################
    # Hash to provide a lookup from Caliber TestCase ID -> Rally TestCase OID
    @testcase_oid_by_caliber_testcase_id = {}
    @testcase_name_by_caliber_testcase_id ={}

    @logger.info "Opening for reading XML data file #{$caliber_file_tc_traces}..."
    caliber_data = Nokogiri::XML(File.open($caliber_file_tc_traces), 'UTF-8') do | config |
        config.strict
    end

    # Read in cached reqname -> Story OID mapping from file
    @logger.info "CSV file reading/caching of Caliber-Testcase-ID --> Rally-ObjectID from #{$csv_testcase_oid_output}..."
    input  = CSV.read($csv_testcase_oid_output,  {:col_sep => $my_delim})

    header = input.first #ignores first line
    rows   = []
    (1...input.size).each { |i| rows << CSV::Row.new(header, input[i])}
    @logger.info "    Found #{rows.length} rows of data"
    number_processed = 0

    # Proceed through rows in input CSV and store reqname -> story OID lookup in a hash
    rows.each do |row|
        cache_testcase_oid(header, row)
        number_processed += 1
    end

    ############################
    # Reading in the CSV that maps Caliber reqids to rally story oids
    # Hash to provide a lookup from Caliber reqname -> Rally Story OID
    @story_oid_by_reqid = {}
    @req_name_by_reqid = {}

    # Read in cached reqname -> Story OID mapping from file
    @logger.info "CSV file reading/caching of reqname --> story-OID from #{$csv_story_oids_by_req}..."
    input  = CSV.read($csv_story_oids_by_req,  {:col_sep => $my_delim})

    header = input.first #ignores first line
    rows   = []
    (1...input.size).each { |i| rows << CSV::Row.new(header, input[i])}
    @logger.info "    Found #{rows.length} rows of data"
    number_processed = 0

    # Proceed through rows in input CSV and store reqname -> story OID lookup
    # in a hash
    rows.each do |row|
        cache_story_oid(header, row)
        number_processed += 1
    end

    ##############################
    # Read through caliber file and store trace records in array of testcase hashes
    import_count = 0
    caliber_data.search($jdrequesttraces_tag).each_with_index do | request_traces, indx_req_traces |
        @logger.info "Processing #{$jdrequesttraces_tag} tag #{indx_req_traces+1}..."

        request_traces.search($jdrequest_tag).each_with_index do | jd_request, indx_request |
            @logger.info "    Processing #{$jdrequest_tag} tag #{indx_request+1}..."

            this_testcase_id = ""
            jd_request.search($jdid_tag).each do | jd_id |
                this_testcase_id = jd_id.text
            end

            this_testcase_name = ""
            jd_request.search($jdname_tag).each do | jd_name |
                this_testcase_name = jd_name.text
            end

            traces_array = []

            jd_request.search($jdtraceto_tag).each_with_index do | jd_traceto, indx_traceto |
                @logger.info "        Searching #{$jdtraceto_tag} tag #{indx_traceto+1}..."
    
                ##### #####
                # Find all <JDtraceto>'s
                jd_traceto.search($jdtrace_tag).each_with_index do | jd_trace, indx_trace |                 

                    this_traceid    = jd_trace.search($jdtraceid_tag).first.text
                    this_tracename  = jd_trace.search($jdtracename_tag).first.text

                    @logger.info "            Found #{$jdtrace_tag} tag #{indx_trace+1}; JDid=#{this_traceid}; JDname='#{this_tracename}'"

                    is_testcase_or_requirement = this_traceid.match(/^(TC|REQ)/)
    
                    if !is_testcase_or_requirement.nil? then
                        traces_array.push(this_traceid)
                    else
                        @logger.info "ERROR: Trace was neither for TC or REQ..."
                    end
                end
            end

            ##### #####
            # Find all <JDtracefrom>'s
            jd_request.search($jdtracefrom_tag).each_with_index do | jd_tracefrom, indx_tracefrom |
                @logger.info "        Searching #{$jdtracefrom_tag} tag #{indx_tracefrom+1}..."

                jd_tracefrom.search($jdtrace_tag).each_with_index do | jd_trace, indx_trace |
                    this_traceid    = jd_trace.search($jdtraceid_tag).first.text
                    this_tracename  = jd_trace.search($jdtracename_tag).first.text
                    @logger.info "            Found #{$jdtrace_tag} tag #{indx_trace+1}; JDid=#{this_traceid}; JDname='#{this_tracename}'"

                    is_testcase_or_requirement = this_traceid.match(/^(TC|REQ)/)
                    if !is_testcase_or_requirement.nil? then
                        traces_array.push(this_traceid)
                    else
                        @logger.info "ERROR: Trace was neither for TC or REQ..."
                    end
                end
            end

            ##### #####
            # Create traces text for import to rally
            if traces_array.length > 0 then
                traces_text = create_traces_markup_from_traces_array(traces_array)
            end

            if $preview_mode then
                @logger.info "Rally TestCase needs updated with #{traces_array.length} Caliber Traces from TestCase: #{this_testcase_id}"
            else
                testcase_oid = @testcase_oid_by_caliber_testcase_id[this_testcase_id]
                if !testcase_oid.nil?
                    update_testcase_with_caliber_traces(testcase_oid, this_testcase_id, traces_text)
                else
                    @logger.error "Rally TestCase OID for Caliber ID=#{this_testcase_id} not found for importing traces."
                end
            end

            # Circuit-breaker for testing purposes
            if import_count < $max_import_count then
                import_count += 1
            else
                break
            end
        end
    end

    # Only import into Rally if we're not in "preview_mode" for testing
    if $preview_mode then
        @logger.info "Finished Processing Caliber TestCase Traces for import to Rally. Total Traces Processed: #{import_count}."
    else
        @logger.info "Finished Importing Caliber Traces to Rally. Total Traces Processed: #{import_count}."
    end

end

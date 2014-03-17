#!/usr/bin/env ruby

require 'base64'
require 'csv'
require 'nokogiri'
require 'uri'
require 'rally_api'
require 'logger'
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

# set preview mode
if $preview_mode then
    $import_to_rally        = false
else
    $import_to_rally        = true
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
    story_fid       = row[header[0]].strip  # Rally FormattedID
    story_oid       = row[header[1]].strip  # Rally ObjectID
    caliber_id      = row[header[2]].strip  # Caliber ID
    req_name        = row[header[3]].strip  # Caliber Req Name

    if !req_name.eql? nil then
        @story_fidoidcid_by_reqname[req_name] = [story_fid.to_s, story_oid.to_s, caliber_id.to_s]
    end

    @story_fidoid_by_reqid[caliber_id] = [story_fid.to_s, story_oid.to_s]

    if !req_name.eql? nil then
        @req_name_by_reqid[caliber_id] = req_name
    end
end


def create_traces_text_from_traces_array(traces_array)
    rally_host = $my_base_url.split("/")[-2]
    detail_url_prefix = "https://#{rally_host}/#/detail/userstory"
    traces_markup = '<p><b>Caliber TRACES</b></p><br/>'
    trace_counter = 1

    traces_array.each do | this_trace |
        story_oid = @story_fidoid_by_reqid[this_trace][1]
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
                @logger.info "    Rally TestCase OID=#{testcase_oid} found for Caliber TestCase ID: #{this_traceid} - linking Trace to TestCase: #{testcase_oid}"
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
            story_fid, story_oid = @story_fidoid_by_reqid[this_traceid.sub("REQ", "")]

            if story_oid.nil? then
                @logger.warn "        *** No Rally Story ObjectID found for Caliber Requirement ID: #{this_traceid} - skipping linkage of this Trace."
                this_trace = @req_name_by_reqid[this_traceid] || this_traceid
            else
                @logger.info "        Linking Trace JDtraceId=#{this_traceid} to Rally UserStory: FmtID=#{story_fid} OID=#{story_oid}"
                this_trace_name = @req_name_by_reqid[this_traceid.sub("REQ", "")] || this_traceid

                detail_url = "#{story_detail_url_prefix}/#{story_oid}"
                this_trace = "<a href=\"#{detail_url}\">#{this_traceid}  #{this_trace_name}</a>"
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
def update_story_with_caliber_traces(story_oid, req_name, traces_text)
    update_fields                                 = {}
    update_fields[$caliber_req_traces_field_name] = traces_text

    begin
        @rally.update("hierarchicalrequirement", story_oid, update_fields)
    rescue => ex
        @logger.error "Error occurred attempting to Import Caliber Traces to Rally Story: OID=#{story_oid}."
        @logger.error ex.message
        @logger.error ex.backtrace
    end
end

bm_time = Benchmark.measure {

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
    @story_fidoidcid_by_reqname = {}
    @story_fidoid_by_reqid = {}
    @req_name_by_reqid = {}

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

    # Process traces
    import_count = 0
    tags_jdrequesttraces = caliber_data.search($jdrequesttraces_tag)
    tags_jdrequesttraces.each_with_index do | request_traces, indx_req_traces |
        @logger.info "Processing <#{$jdrequesttraces_tag}> tag #{indx_req_traces+1} of #{tags_jdrequesttraces.length}..."

        tags_jdrequest = request_traces.search($jdrequest_tag)
        tags_jdrequest.each_with_index do | jd_request, indx_request |

            this_req_id = ""
            jd_request.search($jdid_tag).each do | jd_id |
                this_req_id = jd_id.text
            end

            this_req_name = ""
            jd_request.search($jdname_tag).each do | jd_name |
                this_req_name = jd_name.text
            end

            @logger.info "    Processing <#{$jdrequest_tag}> tag #{indx_request+1} of #{tags_jdrequest.length}; JDid=#{this_req_id}"

            story_fid, story_oid, story_cid = @story_fidoidcid_by_reqname[this_req_name]

            if story_oid.nil? then
                @logger.warn "        Can't find Rally UserStory: JDname=#{this_req_name}... skipping import of this trace."
                next
            else
                @logger.info "        Hashed Rally UserStory: FmtID=#{story_fid}; OID=#{story_oid} for JDname='#{this_req_name}'"
            end

            traces_array = []

            ##### #####
            # Find all <JDtraceto>'s    
            tags_jdtraceto = jd_request.search($jdtraceto_tag)
            tags_jdtraceto.each_with_index do | jd_traceto, indx_traceto |
                @logger.info "        Searching <#{$jdtraceto_tag}> tag #{indx_traceto+1} of #{tags_jdtraceto.length}..."

                jd_traceto.search($jdtrace_tag).each_with_index do | jd_trace, indx_trace |

                    this_traceid    = jd_trace.search($jdtraceid_tag).first.text
                    this_tracename  = jd_trace.search($jdtracename_tag).first.text

                    @logger.info "            Found <#{$jdtrace_tag}> tag #{indx_trace+1}; JDtraceId=#{this_traceid}; JDtraceName='#{this_tracename}'"

                    is_requirement = this_traceid.match(/^REQ/)
                    if !is_requirement.nil? then
                        traces_array.push(this_traceid)
                    else
                        @logger.info "ERROR: TraceTo was not a REQ..."
                    end
                end
            end

            ##### #####
            # Find all <JDtracefrom>'s
            tags_jdtracefrom = jd_request.search($jdtracefrom_tag)
            tags_jdtracefrom.each_with_index do | jd_tracefrom, indx_tracefrom |
                @logger.info "        Searching <#{$jdtracefrom_tag}> tag #{indx_tracefrom+1} of #{tags_jdtracefrom.length}..."

                jd_tracefrom.search($jdtrace_tag).each_with_index do | jd_trace, indx_trace |

                    this_traceid    = jd_trace.search($jdtraceid_tag).first.text
                    this_tracename  = jd_trace.search($jdtracename_tag).first.text

                    @logger.info "            Found <#{$jdtrace_tag}> tag #{indx_trace+1}; JDtraceId=#{this_traceid}; JDtraceName='#{this_tracename}'"

                    is_requirement = this_traceid.match(/^REQ/)
                    if !is_requirement.nil? then
                        traces_array.push(this_traceid)
                    else
                        @logger.info "ERROR: TraceFrom was not a REQ..."
                    end
                end
            end

            ##### #####
            # Create traces text for import to rally
            if traces_array.length > 0 then
                #traces_text = create_traces_text_from_traces_array(traces_array)
                traces_text = create_traces_markup_from_traces_array(traces_array)
            end

            if $preview_mode then
                @logger.info "    Rally Story OID=#{this_req_id} needs updated with #{traces_array.length} Caliber Traces from Requirement: #{this_req_name}"
            else
	        if traces_text.nil? then
                    @logger.info "        Nothing to update for Rally Story OID=#{story_oid} (no traces found)."
		else
                    @logger.info "        Updating Rally Story: FmtID=#{story_fid}; OID=#{story_oid}; with Caliber Traces."
                    update_story_with_caliber_traces(story_oid, this_req_name, traces_text)
		end
            end

            # Circuit-breaker for testing purposes
            if import_count < $max_import_count then
                import_count += 1
            else
	        @logger.info "Stopping import; 'import_count' reached #{import_count+1} ($max_import_count)"
                break
            end
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

    ####----####
    # Output a CSV file of ...
    $csv_story_fidoidcid_by_reqname = "s2-requirement_traces.csv"
    @logger.info "CSV file creation of #{$csv_story_fidoidcid_by_reqname}..."
    wholefile = CSV.generate do |csv|
        csv << %w{reqname  FmtID  ObjectID  CaliberID}
        @story_fidoidcid_by_reqname.each do |this_HASHENTRY|
            csv << this_HASHENTRY
        end
    end
    File.write($csv_story_fidoidcid_by_reqname, wholefile)
    ####----####
    #$csv_story_fidoid_by_reqid     = ""
    #$req_name_by_reqid             = ""
    ####----####

    @logger.show_msg_stats

} # end of "bm_time = Benchmark.measure"

@logger.info ""
@logger.info "This script (#{$PROGRAM_NAME}) is finished; benchmark time in seconds:"
@logger.info "  --User--   -System-   --Total-  --Elapsed-"
@logger.info bm_time.to_s

exit(0)

#the end#

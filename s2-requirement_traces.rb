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

# Tags of interest
$tag_JDrequestTraces    = "JDrequestTraces"
$tag_JDrequest          = "JDrequest"   # The name attribute of the Traceability tag is the name of the Caliber Requirement to which this set of Traces corresponds
$tag_JDid               = "JDid"        # This contains the Caliber ID of the testcase to which we want to associate the traces.
$tag_JDname             = "JDname"
$tag_JDtracefrom        = "JDtracefrom" # Traces From
$tag_JDtraceto          = "JDtraceto"   # Traces To
$tag_JDtrace            = "JDtrace"     # Trace
$tag_JDtraceId          = "JDtraceId"   # TraceID
$tag_JDtraceName        = "JDtraceName"

# set preview mode
if $preview_mode then
    $import_to_rally    = false
else
    $import_to_rally    = true
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


def cache_story_oid(header, row) #{
    story_fid       = row[header[0]].strip  # Rally FormattedID
    story_oid       = row[header[1]].strip  # Rally ObjectID
    req_id          = row[header[2]].strip  # Caliber "id="
    req_tag         = row[header[3]].strip  # Caliber "tag="
    req_name        = row[header[4]].strip  # Caliber Req Name

    if !req_id.eql? nil then
        @story_oid_by_reqid[req_id] = story_oid.to_s
    end

    if !req_name.eql? nil then
        @req_name_by_reqid[req_id] = req_name
    end

    @story_TagFidOidName_by_reqid[req_id] = [req_tag, story_fid.to_s, story_oid.to_s, req_name]

end #} end of "def cache_story_oid(header, row)"


def cache_testcase_oid(header, row) #{
    testcase_fid    = row[header[0]].strip  # Rally FormattedID
    testcase_oid    = row[header[1]].strip  # Rally ObjectID
    testcase_id     = row[header[2]].strip  # Caliber "id="
    testcase_tag    = row[header[3]].strip  # Caliber "tag="
    testcase_name   = row[header[4]].strip  # Caliber Req Name

    @testcase_TagFidOidName_by_reqid[testcase_id] = [testcase_tag, testcase_fid.to_s, testcase_oid.to_s, testcase_name]

end #} end of "def cache_testcase_oid(header, row)"


def create_traces_text_from_traces_array(traces_array) #{
    rally_host = $my_base_url.split("/")[-2]
    detail_url_prefix = "https://#{rally_host}/#/detail/userstory"
    traces_markup = '<p><b>Caliber TRACES</b></p><br/>'
    trace_counter = 1

    traces_array.each do | this_trace |
        story_oid = @story_TagFidOidName_by_reqid[this_trace][1]
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
end #} end of "def create_traces_text_from_traces_array(traces_array)"


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
            testcase_tag, testcase_fid, testcase_oid, testcase_name = @testcase_TagFidOidName_by_reqid[this_traceid.sub("TC", "")]

            if testcase_oid.nil? then
                @logger.warn "    *** No Rally TestCase found for Caliber TestCase: CID=#{this_traceid}; (link will be empty)"
                this_trace = this_traceid
            else
                @logger.info "        Linking Trace JDtraceId=#{this_traceid}; to Rally TestCase: FmtID=#{testcase_fid}; OID=#{testcase_oid};"
                #this_trace_name = @testcase_name_by_caliber_testcase_id[testcase_oid] || this_traceid
                this_trace_name = "#{this_traceid}: #{testcase_name}"

                detail_url = "#{testcase_detail_url_prefix}/#{testcase_oid}"
                this_trace = "<a href=\"#{detail_url}\">#{this_trace_name}</a>"
            end
            traces_markup += trace_counter.to_s + ". "
            traces_markup += this_trace
            traces_markup += '<br/>'
            trace_counter += 1
        end

        if !is_requirement.nil? then
            story_tag, story_fid, story_oid, story_name = @story_TagFidOidName_by_reqid[this_traceid.sub("REQ", "")]

            if story_oid.nil? then
                @logger.warn "    *** No Rally UserStory found for Caliber Requirement: CID=#{this_traceid}; (link will be empty)"
                this_trace = @req_name_by_reqid[this_traceid] || this_traceid
            else
                @logger.info "        Linking Trace JDtraceId=#{this_traceid}; to Rally UserStory: FmtID=#{story_fid}; OID=#{story_oid};"
                #this_trace_name = @req_name_by_reqid[this_traceid.sub("REQ", "")] || this_traceid
                this_trace_name = "#{this_traceid}: #{story_name}"

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
def update_story_with_caliber_traces(story_oid, req_name, traces_text)
    update_fields                                 = {}
    update_fields[$caliber_req_traces_field_name] = traces_text
    begin
        @rally.update("hierarchicalrequirement", story_oid, update_fields)
    rescue => ex
        @logger.error "Error occurred attempting to Import Caliber Traces to Rally UserStory: OID=#{story_oid};"
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

    # Initialize Caliber Helper
    @caliber_helper = CaliberHelper.new($caliber_project, $caliber_id_field_name,
        $description_field_hash, $caliber_image_directory, @logger, nil)
    @caliber_helper.display_vars()
    @rally = @caliber_helper.get_rally_connection()

    @logger.info "Opening XML file for reading: '#{$caliber_file_req_traces}'"
    caliber_data = Nokogiri::XML(File.open($caliber_file_req_traces), 'UTF-8') do | config |
        config.strict
    end

    # Hash to provide a lookup from Caliber reqname -> Rally Story OID
    @story_TagFidOidName_by_reqid       = {}
    @testcase_TagFidOidName_by_reqid    = {}
    @story_oid_by_reqid                 = {}
    @req_name_by_reqid                  = {}

    #---------------------------------------------------------------------------
    # Read in cached reqname -> Story OID mapping from file
    @logger.info "CSV file reading (requirement-name --> Story-OID): '#{$csv_US_OidCidReqname_by_FID}'"
    input  = CSV.read($csv_US_OidCidReqname_by_FID,  {:col_sep => $my_delim})
    header = input.first #ignores first line
    rows   = []
    (1...input.size).each { |i| rows << CSV::Row.new(header, input[i])}
    @logger.info "    Found #{rows.length} rows of data"
    number_processed = 0

    # Proceed through rows in input CSV and store reqname -> story OID lookup in a hash
    @logger.info "    Building hash of Rally UserStory OID's by Caliber Requirement Name (for traces import)"
    rows.each do |row|
        cache_story_oid(header, row)
        number_processed += 1
    end

    #---------------------------------------------------------------------------
    # Read in cached reqname -> Testcase OID mapping from file, if it exists.
    #
    if File.file?($csv_TC_OidCidReqname_by_FID) #{
        @logger.info "CSV file reading (requirement-name --> Story-OID): '#{$csv_TC_OidCidReqname_by_FID}'"
        input  = CSV.read($csv_TC_OidCidReqname_by_FID,  {:col_sep => $my_delim})
        header = input.first #ignores first line
        rows   = []
        (1...input.size).each { |i| rows << CSV::Row.new(header, input[i])}
        @logger.info "    Found #{rows.length} rows of data"
        number_processed = 0

        # Proceed through rows in input CSV and store reqname -> testcase OID lookup in a hash
        @logger.info "    Building hash of Rally TestCase OID's by Caliber Requirement Name (for traces import)"
        rows.each do |row|
            cache_testcase_oid(header, row)
            number_processed += 1
        end
    end #} end of "if File.file?($csv_TC_OidCidReqname_by_FID)"

    # Process traces
    import_count = 0

    all_JDrequestTraces_tags = caliber_data.search($tag_JDrequestTraces)
    all_JDrequestTraces_tags.each_with_index do | this_JDrequestTraces, indx_JDrequestTraces |
        @logger.info "<#{$tag_JDrequestTraces}> tag #{indx_JDrequestTraces+1} of #{all_JDrequestTraces_tags.length}"

        all_JDrequest_tags = this_JDrequestTraces.search($tag_JDrequest)
        all_JDrequest_tags.each_with_index do | this_JDrequest, indx_JDrequest |

            this_req_id = ""
            this_JDrequest.search($tag_JDid).each do | this_JDid |
                this_req_id = this_JDid.text
            end

            this_req_name = ""
            this_JDrequest.search($tag_JDname).each do | this_JDname |
                this_req_name = this_JDname.text
            end

            @logger.info "    <#{$tag_JDrequest}> tag #{indx_JDrequest+1} of #{all_JDrequest_tags.length}; JDid=#{this_req_id};"

            story_tag, story_fid, story_oid, story_name = @story_TagFidOidName_by_reqid[this_req_id.sub("REQ", "")]
            if story_oid.nil? then
                @logger.warn "        Can't find Rally UserStory: JDid=#{this_req_id}; JDname='#{this_req_name}'; skipping import."
                next
            else
                @logger.info "        Hashed Rally UserStory: FmtID=#{story_fid}; OID=#{story_oid} for JDname='#{this_req_name}'"
            end

            traces_array = []

            ##### #####
            # Find all <JDtraceto>'s & <JDtracefrom>'s    
            all_JDtraceTOandFROM_tags = this_JDrequest.search($tag_JDtraceto, $tag_JDtracefrom)
            all_JDtraceTOandFROM_tags.each_with_index do | this_JDtraceTOandFROM, indx_JDtraceTOandFROM | #{
                @logger.info "        Searching <#{$tag_JDtraceto}>/<#{$tag_JDtracefrom}> tag #{indx_JDtraceTOandFROM+1} of #{all_JDtraceTOandFROM_tags.length}"
                all_JDtrace_tags = this_JDtraceTOandFROM.search($tag_JDtrace)
                all_JDtrace_tags.each_with_index do | this_JDtrace, indx_JDtrace |

                    this_traceid    = this_JDtrace.search($tag_JDtraceId).first.text
                    this_tracename  = this_JDtrace.search($tag_JDtraceName).first.text

                    @logger.info "            Found <#{$tag_JDtrace}> tag #{indx_JDtrace+1}; JDtraceId=#{this_traceid}; JDtraceName='#{this_tracename}'"

                    is_testcase_or_requirement = this_traceid.match(/^(TC|REQ)/)
                    if !is_testcase_or_requirement.nil? then
                        traces_array.push(this_traceid)
                    else
                        @logger.error "        *** ERROR: Above <#{$tag_JDtraceID}> was neither TC or REQ"
                    end
                end
            end #} end of "all_JDtraceTOandFROM_tags.each_with_index do | this_JDtraceTOandFROM, indx_JDtraceTOandFROM |"

            ##### #####
            # Create traces text for import to rally
            if traces_array.length > 0 then
                #traces_text = create_traces_text_from_traces_array(traces_array)
                traces_text = create_traces_markup_from_traces_array(traces_array)
            end

            if $preview_mode then
                @logger.info "    Rally Story OID=#{this_req_id}; needs updated with #{traces_array.length} Caliber Traces from Requirement: '#{this_req_name}'"
            else
	            if traces_text.nil? then
                    @logger.info "        Nothing to update for Rally Story OID=#{story_oid}; (no traces found)."
		        else
                    @logger.info "        Updating Rally Story with Caliber Traces: FmtID=#{story_fid}; OID=#{story_oid};  CID=#{this_req_id};"
                    update_story_with_caliber_traces(story_oid, this_req_name, traces_text)
		        end
            end

            # Circuit-breaker for testing purposes
            if import_count < $max_import_count-1 then
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

    @logger.show_msg_stats

} # end of "bm_time = Benchmark.measure"

@logger.info ""
@logger.info "This script (#{$PROGRAM_NAME}) is finished; benchmark time in seconds:"
@logger.info "  --User--   -System-   --Total-  --Elapsed-"
@logger.info bm_time.to_s

exit(0)

#the end#

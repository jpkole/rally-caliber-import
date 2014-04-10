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
    $import_to_rally    = false
else
    $import_to_rally    = true
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
$tag_JDrequestTraces    = "JDrequestTraces"
$tag_JDrequest          = "JDrequest"       # The name attribute of the Traceability tag is the name of the Caliber Requirement to which this set of Traces corresponds
$tag_JDid               = "JDid"            # This contains the Caliber ID of the testcase to which we want to associate the traces.
$tag_JDname             = "JDname"
$tag_JDtracefrom        = "JDtracefrom"     # Traces From
$tag_JDtraceto          = "JDtraceto"       # Traces To
$tag_JDtrace            = "JDtrace"         # Trace
$tag_JDtraceId          = "JDtraceId"       # TraceID
$tag_JDtraceName        = "JDtraceName"


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
                @logger.warn "        *** No Rally TestCase found for Caliber TestCase; CID=#{this_traceid} - skipping linkage."
                this_trace = @testcase_name_by_reqid[this_traceid] || this_traceid
            else
                @logger.info "            Linking Caliber Trace: CID=#{this_traceid}; to Rally TestCase: FID=#{testcase_fid}; OID=#{testcase_oid}"
                this_trace_name = @testcase_name_by_reqid[testcase_oid] || this_traceid

                detail_url = "#{testcase_detail_url_prefix}/#{testcase_oid}"
                this_trace = "<a href=\"#{detail_url}\">#{this_trace_name}</a>"
            end
            traces_markup += trace_counter.to_s + ". "
            traces_markup += this_trace
            traces_markup += '<br/>'
            trace_counter += 1
        end

        if !is_requirement.nil? then
            story_oid = @story_oid_by_reqid[this_traceid.sub("REQ", "")]
            story_tag, story_fid, story_oid, req_name = @story_TagFidOidName_by_reqid[this_traceid.sub("REQ", "")]
            if story_oid.nil? then
                @logger.warn "        *** No Rally UserStory found for Caliber Requirement; CID=#{this_traceid} - skipping linkage."
                this_trace = @req_name_by_reqid[this_traceid] || this_traceid
            else
                @logger.info "            Linking Caliber Trace: CID=#{this_traceid}; to Rally UserStory: FID=#{story_fid}; OID=#{story_oid}."
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


def update_testcase_with_caliber_traces(testcase_oid, testcase_id, traces_text) #{
    # Take Caliber traces array, process and combine field data and import into corresponding Rally Story
    update_fields                                = {}
    update_fields[$caliber_tc_traces_field_name] = traces_text
    begin
        @rally.update("testcase", testcase_oid, update_fields)
        #@logger.info "        Imported Caliber Traces for Rally TestCase: OID=#{testcase_oid}"
    rescue => ex
        @logger.error "Error occurred attempting to Import Caliber Traces to Rally TestCase: OID=#{testcase_oid}"
        @logger.error ex.message
        @logger.error ex.backtrace
    end
end #} end of "def update_testcase_with_caliber_traces(testcase_oid, testcase_id, traces_text)"


bm_time = Benchmark.measure {

#==================== Connect to Rally and Import Caliber data ====================

    # Instantiate Logger
    log_file = File.open($cal2ral_tc_traces_log, "a")
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

    @logger.info "Opening XML file for reading: '#{$caliber_file_tc_traces}'"
    caliber_data = Nokogiri::XML(File.open($caliber_file_tc_traces), 'UTF-8') do | config |
        config.strict
    end

    ############################
    # Hash to provide a lookup from Caliber TestCase ID -> Rally TestCase OID
    @story_TagFidOidName_by_reqid       = {}
    @testcase_TagFidOidName_by_reqid    = {}
    @story_oid_by_reqid                 = {}
    @req_name_by_reqid                  = {}
    @testcase_name_by_reqid             = {}

    ############################
    # Read in cached reqname -> Story OID mapping from file
    @logger.info "CSV file reading (Caliber-Testcase-ID --> Rally-OID): '#{$csv_TC_OidCidReqname_by_FID}'"
    input  = CSV.read($csv_TC_OidCidReqname_by_FID,  {:col_sep => $my_delim})
    header = input.first #ignores first line
    rows   = []
    (1...input.size).each do |i|
        rows << CSV::Row.new(header, input[i])
    end
    @logger.info "    Found #{rows.length} rows of CSV data"

    ############################
    # Proceed through rows in input CSV and store reqname -> story OID lookup in a hash
    number_processed = 0
    rows.each_with_index do |row, indx|
        cache_testcase_oid(header, row)
        number_processed += 1
    end

    ############################
    # Read in cached reqname -> Story OID mapping from file
    @logger.info "CSV file reading (reqname --> story-OID): '#{$csv_US_OidCidReqname_by_FID}'"
    input  = CSV.read($csv_US_OidCidReqname_by_FID,  {:col_sep => $my_delim})

    header = input.first #ignores first line
    rows   = []
    (1...input.size).each do |i|
        rows << CSV::Row.new(header, input[i])
    end
    @logger.info "    Found #{rows.length} rows of CSV data"

    ############################
    # Proceed through rows in input CSV and store reqname -> story OID lookup in a hash
    number_processed = 0
    rows.each do |row|
        cache_story_oid(header, row)
        number_processed += 1
    end

    ##############################
    # Read through caliber file and store trace records in array of testcase hashes
    import_count = 0

    all_JDrequestTraces_tags = caliber_data.search($tag_JDrequestTraces)
    all_JDrequestTraces_tags.each_with_index do | this_JDrequestTraces, indx_JDrequestTraces | #{
        @logger.info "<#{$tag_JDrequestTraces}> tag #{indx_JDrequestTraces+1} of #{all_JDrequestTraces_tags.length}"

        all_JDrequest_tags = this_JDrequestTraces.search($tag_JDrequest)
        all_JDrequest_tags.each_with_index do | this_JDrequest, indx_JDrequest | #{

            this_testcase_id = ""
            this_JDrequest.search($tag_JDid).each do | this_JDid |
                this_testcase_id = this_JDid.text
            end

            this_testcase_name = ""
            this_JDrequest.search($tag_JDname).each do | this_JDname |
                this_testcase_name = this_JDname.text
            end

            @logger.info "    <#{$tag_JDrequest}> tag #{indx_JDrequest+1} of #{all_JDrequest_tags.length}; JDid=#{this_testcase_id}"

            testcase_tag, testcase_fid, testcase_oid, testcase_name = @testcase_TagFidOidName_by_reqid[this_testcase_id.sub("TC", "")]
            if testcase_oid.nil? then
                @logger.warn "        Can't find Rally TestCase: JDid=#{this_testcase_id}; JDname='#{this_testcase_name}'; skipping import."
                next
            else
                @logger.info "        Hashed Rally TestCase: FmtID=#{testcase_fid}; OID=#{testcase_oid} for JDname='#{this_testcase_name}'"
            end

            traces_array = []

            ##### #####
            # Find all <JDtraceto>'s & <JDtracefrom>'s
            all_JDtraceTOandFROM_tags = this_JDrequest.search($tag_JDtraceto, $tag_JDtracefrom)
            all_JDtraceTOandFROM_tags.each_with_index do | this_JDtraceTOandFROM, indx_JDtraceTOandFROM | #{
                @logger.info "        Searching <#{this_JDtraceTOandFROM.name}> tag #{indx_JDtraceTOandFROM+1} of #{all_JDtraceTOandFROM_tags.length}"
    
                all_JDtrace_tags = this_JDtraceTOandFROM.search($tag_JDtrace)
                all_JDtrace_tags.each_with_index do | this_JDtrace, indx_JDtrace |                 
                    this_traceid    = this_JDtrace.search($tag_JDtraceId).first.text
                    this_tracename  = this_JDtrace.search($tag_JDtraceName).first.text

                    @logger.info "            Found <#{$tag_JDtrace}> tag #{indx_JDtrace+1}; JDid=#{this_traceid}; JDname='#{this_tracename}'"

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
                traces_text = create_traces_markup_from_traces_array(traces_array)
            end

            if $preview_mode then
                @logger.info "    Rally TestCase OID=#{this_testcase_id} needs updated with #{traces_array.length} Caliber Traces from TestCase: #{this_testcase_name}"
            else
                if traces_text.nil? then
                    @logger.info "            No traces found."
                else
                    @logger.info "        Updating Rally TestCase: FmtID=#{testcase_fid}; OID=#{testcase_oid}; with Caliber Traces: CID=#{this_testcase_id}"
                    update_testcase_with_caliber_traces(testcase_oid, this_testcase_id, traces_text)
                end
            end

            # Circuit-breaker for testing purposes
            if import_count < $max_import_count-1 then
                import_count += 1
            else
                @logger.info "Stopping import; 'import_count' reached #{import_count+1} ($max_import_count)"
                break
            end

        end #} end of "all_JDrequest_tags.each_with_index do | this_JDrequest, indx_JDrequest |"

    end #} end of "all_JDrequestTraces_tags.each_with_index do | this_JDrequestTraces, indx_JDrequestTraces |"

    # Only import into Rally if we're not in "preview_mode" for testing
    if $preview_mode then
        @logger.info "Finished Processing Caliber TestCase Traces for import to Rally. Total Traces Processed: #{import_count}."
    else
        @logger.info "Finished Importing Caliber Traces to Rally. Total Traces Processed: #{import_count}."
    end

    @logger.show_msg_stats

} # end of "bm_time = Benchmark.measure"

@logger.info ""
@logger.info "This script (#{$PROGRAM_NAME}) is finished; benchmark time in seconds:"
@logger.info "  --User--   -System-   --Total-  --Elapsed-"
@logger.info bm_time.to_s

exit (0)

#the end#

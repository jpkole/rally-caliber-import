require 'base64'
require 'csv'
require 'nokogiri'
require 'uri'
require 'rally_api'
require 'logger'
require './multi_io.rb'

# Rally Connection parameters
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "topsecret"
$wsapi_version                   = "1.43"
$my_workspace                    = "My Workspace"
$my_project                      = "My Project"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_name               = "jdf_testcase_traces_zeuscontrol.xml"
$caliber_trace_field_name        = 'CaliberTraces'

# Cached Caliber Requirement to Rally Story OID data
$testcase_oids_from_id           = "testcase_oids_by_testcaseid.csv"

# Runtime preferences
$max_import_count                = 100000
$preview_mode                    = false

# JDF Project setting
$jdf_zeus_control_project        = "JDF-Zeus_Control-project"

if $my_delim == nil then $my_delim = "\t" end

# Load (and maybe override with) my personal/private variables from a file...
# my_vars = File.dirname(__FILE__) + "/my_vars_testcase_traces.rb"
# if FileTest.exist?( my_vars ) then require my_vars end

caliber_data = Nokogiri::XML(File.open($caliber_file_name), 'UTF-8') do | config |
    config.strict
end

# set preview mode
if $preview_mode then
    $import_to_rally                 = false
else
    $import_to_rally                 = true
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
$jdrequesttraces_tag                              = "JDrequestTraces"

# The name attribute of the Traceability tag is the name of the
# Caliber Requirement to which this set of Traces corresponds
$jdrequest_tag                                    = "JDrequest"

# Traces From/To
$jdtracefrom_tag                                  = "JDtracefrom"
$jdtraceto_tag                                    = "JDtraceto"

# Trace
$jdtrace_tag                                      = "JDtrace"

#TraceID
$jdtraceid_tag                                    = "JDtraceId"
$jdtracename_tag                                  = "JDtraceName"

def cache_testcase_oid(header, row)
    testcase_id                 = row[header[0]].strip
    testcase_oid                = row[header[1]].strip

    if !testcase_id.eql? nil then
        @testcase_oid_by_id[testcase_id] = testcase_oid.to_s
    end
end

def create_traces_text_from_traces_array(traces_array)
    traces_markup = '<p><b>Caliber TRACES</b></p><br>'
    trace_counter = 1
    traces_array.each do | this_trace |
        traces_markup += trace_counter.to_s + ". "
        traces_markup += this_trace
        traces_markup += '<br>'
        trace_counter += 1
    end
    return traces_markup
end

# Take Caliber traces array, process and combine field data and import into corresponding Rally Story
def update_testcase_with_caliber_traces(testcase_oid, testcase_id, traces_text)

    @logger.info "Updating Rally TestCase ObjectID: #{testcase_oid} with Caliber Traces from TestCase: #{testcase_id}"

    update_fields                               = {}
    update_fields[$caliber_trace_field_name]    = traces_text
    begin
        @rally.update("testcase", testcase_oid, update_fields)
        @logger.info "Successfully Imported Caliber Traces for Rally TestCase: ObjectID #{testcase_oid}."
    rescue => ex
        @logger.error "Error occurred attempting to Import Caliber Traces to Rally Story: ObjectID #{testcase_oid}."
        @logger.error ex.message
        @logger.error ex.backtrace
    end
end

begin

#==================== Connect to Rally and Import Caliber data ====================

#Setting custom headers
    $headers                = RallyAPI::CustomHttpHeader.new()
    $headers.name           = "Caliber Traces Importer"
    $headers.vendor         = "Rally Technical Services"
    $headers.version        = "0.50"

    config                  = {:base_url => $my_base_url}
    config[:username]       = $my_username
    config[:password]       = $my_password
    config[:workspace]      = $my_workspace
    config[:project]        = $my_project
    config[:version]        = $wsapi_version
    config[:headers]        = $headers

    @rally = RallyAPI::RallyRestJson.new(config)

    # Instantiate Logger
    log_file = File.open("caliber2rally.log", "a")
    log_file.sync = true
    @logger = Logger.new MultiIO.new(STDOUT, log_file)

    @logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL

    # Hash to provide a lookup from Caliber reqname -> Rally TestCase OID
    @testcase_oid_by_id = {}

    # Read in cached reqname -> Story OID mapping from file
    input  = CSV.read($testcase_oids_from_id,  {:col_sep => $my_delim})

    header = input.first #ignores first line
    rows   = []
    (1...input.size).each { |i| rows << CSV::Row.new(header, input[i])}
    number_processed = 0

    # Proceed through rows in input CSV and store reqname -> story OID lookup
    # in a hash
    @logger.info "Reading/caching TestCase name -> TestCase OID mapping from #{$testcase_oids_from_id} file..."

    rows.each do |row|
        cache_testcase_oid(header, row)
        number_processed += 1
    end

    @traces_array_by_testcase_id = {}

    # Read through caliber file and store trace records in array of testcase hashes
    import_count = 0
    caliber_data.search($jdrequesttraces_tag ).each do | request_traces |
        request_traces.search($jdrequest_tag).each do | jd_requests |
            jd_requests.search($jdtraceto_tag).each do | jd_traceto |

                jd_traceto.search($jdtrace_tag).each do | jd_trace |
                    this_traceid          = jd_trace.search($jdtraceid_tag).first.text
                    this_tracename        = jd_trace.search($jdtracename_tag).first.text

		    # May need to remove if testcases can/should link to requirements as well?
                    is_testcase = this_traceid.match(/^TC/)

                    if !is_testcase.nil? then
                        this_testcase_id      = this_traceid
                        this_trace_string     = "#{this_testcase_id}:   #{this_tracename}"
                        traces_array = @traces_array_by_testcase_id[this_testcase_id]
                        if traces_array.nil? then
                            traces_array = []
                        end
                        traces_array.push(this_trace_string)
                        @traces_array_by_testcase_id[this_testcase_id] = traces_array
                    end
                end
            end
        end
    end

    @traces_array_by_testcase_id.each_pair do | this_testcase_id, this_traces_array |
        testcase_oid = @testcase_oid_by_id[this_testcase_id]

        if testcase_oid.nil? then
            @logger.warn "No Rally TestCase ObjectID found for Caliber TestCase ID: #{this_testcase_id}. Skipping import of traces for this TestCase."
            next
        else
            @logger.info "Rally TestCase ObjectID: #{testcase_oid} found for Caliber TestCase ID: #{this_testcase_id}."
        end

        # Create traces text for import to rally
        traces_text = create_traces_text_from_traces_array(this_traces_array)

        if $preview_mode == false then
            update_testcase_with_caliber_traces(testcase_oid, this_testcase_id, traces_text)
        else
            @logger.info "Rally TestCase ObjectID: #{testcase_oid} needs updated with #{trace_array.length} Caliber Traces from TestCase: #{this_testcase_id}"
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
        @logger.info "Finished Processing Caliber TestCase Traces for import to Rally. Total Traces Processed: #{import_count}."
    else
        @logger.info "Finished Importing Caliber Traces to Rally. Total Traces Processed: #{import_count}."
    end

end

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
$caliber_file_name               = "hhc.xml"
$caliber_id_field_name           = 'CaliberID'
$caliber_image_directory         = "/images"

# Runtime preferences
$max_import_count                = 100000
$html_mode                       = true
$preview_mode                    = false

# Flag to set in @rally_story_hierarchy_hash if Requirement has no Parent
$no_parent_id                    = "-9999"

# Output parameters
$my_output_file                  = "caliber_requirements.csv"
$requirement_fields              =  %w{id hierarchy name project description validation purpose pre_condition basic_course post_condition exceptions remarks}

# Output fields to store a CSV
# allowing lookup of Story OID by Caliber Requirement name
# (needed for traces import)
$story_oid_output_csv            = "story_oids_by_reqname.csv"
$story_oid_output_fields         =  %w{reqname ObjectID}

# JDF Project setting
$jdf_zeus_control_project        = "JDF-Zeus_Control-project"

if $my_delim == nil then $my_delim = "\t" end

# Load (and maybe override with) my personal/private variables from a file...
# my_vars = File.dirname(__FILE__) + "/my_vars.rb"
# if FileTest.exist?( my_vars ) then require my_vars end

# HTML Mode vs. XML Mode
# The following is needed to preserve newlines in formatting of UDAValues when
# Imported into Rally. Caliber export uses newlines in UDAValue attributes as formatting.
# When importing straight XML, the newlines are ignored completely
# Rally (and Nokogiri, really) needs markup. This step replaces newlines with <br>
# And reads the resulting input as HTML rather than XML
caliber_file = File.open($caliber_file_name, 'rb')
caliber_content = caliber_file.read
caliber_content_html = caliber_content.gsub("\n", "&lt;br&gt;\n")

if $html_mode then
    caliber_data = Nokogiri::HTML(caliber_content_html, 'UTF-8') do | config |
        config.strict
    end
else
    caliber_data = Nokogiri::XML(File.open($caliber_file_name), 'UTF-8') do | config |
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
$uda_value_name_purpose                  = "JDF Purpose [Pu]"
$uda_value_name_pre_condition            = "JDF Pre-condition [Pr]"
$uda_value_name_basic_course             = "JDF Basic Course [Ba]"
$uda_value_name_post_condition           = "JDF Post-condition [Po]"
$uda_value_name_exceptions               = "JDF Exceptions [Ex]"
$uda_value_name_remarks                  = "JDF Remarks [Re]"
$uda_value_name_open_issues              = "JDF Open Issues"


# Record template hash for a requirement from Caliber
# Hash fields are in same order as CSV output format

$caliber_requirement_record_template = {
    'id'                    => 0,
    'hierarchy'             => 0,
    'name'                  => "",
    'project'               => "",
    'description'           => "",
    'caliber_validation'    => "",
    'caliber_purpose'       => "",
    'pre_condition'         => "",
    'basic_course'          => "",
    'post_condition'        => "",
    'exceptions'            => "",
    'remarks'               => "",
    'open_issues'           => ""
}

$description_field_hash = {
    'Caliber Purpose'         => 'caliber_purpose',
    'Pre-condition'           => 'pre_condition',
    'Basic course'            => 'basic_course',
    'Post-condition'          => 'post_condition',
    'Exceptions'              => 'exceptions',
    'Remarks'                 => 'remarks',
    'Description'             => 'description'
}

# Caliber hierarchy id's look like: 1.1.1, as an example
# The parent requirement of 1.1.1 would be 1.1
# This function returns the value "1.1" as the parent of "1.1.1"
def get_parent_hierarchy_id(requirement)

    hierarchy_id = requirement['hierarchy']
    hierarchy_id_split = hierarchy_id.split('.')
    hierarchy_depth = hierarchy_id_split.length
    if hierarchy_depth > 1 then
        # [0..hierarchy_depth-2] goes through 2nd to last element
        parent_hierarchy_arr = hierarchy_id_split[0..hierarchy_depth-2]
        parent_id_string = parent_hierarchy_arr.join(".")
    else
        parent_id_string = $no_parent_id
    end
    @logger.info "hierarchy_id: #{hierarchy_id} has parent_id: #{parent_id_string}."
    return parent_id_string
end

# Combines Caliber name, Caliber hiearachy id (1.1.1), and Caliber id (1234)
# fields, into a single string for Rally Story name
def make_name_from_requirement(requirement)
    hierarchy               = requirement['hierarchy']
    req_id                  = requirement['id']
    name                    = requirement['name']

    return "<b>Caliber</b> #{hierarchy} REQ #{req_id}: #{name}"
end

# A Bolded Caliber field header for inclusion into Rally Description markup
def make_header(field_string)
    return "<p><b>#{field_string}</b></p>"
end

# Prepares arrays of File references and Caliber image id attributes from Caliber Description markup
def get_caliber_image_files(caliber_description)

    caliber_description_parser = Nokogiri::HTML(caliber_description, 'UTF-8') do | config |
        config.strict
    end

    caliber_image_files = []
    caliber_image_ids = []
    caliber_description_parser.search('img').each do | this_image |
        image_id = this_image['id']
        image_src = this_image['src']

        image_url_unescaped = URI.unescape(image_src)
        image_file_name = image_url_unescaped.split("\\")[-1]

        image_file = File.dirname(__FILE__) + "#{$caliber_image_directory}/#{image_file_name}"
        caliber_image_files.push(image_file)
        caliber_image_ids.push(image_id)
    end
    return caliber_image_files, caliber_image_ids
end

# Parses through caliber description markup and looks for
# <img> tags
def count_images_in_caliber_description(caliber_description)
    caliber_description_parser = Nokogiri::HTML(caliber_description, 'UTF-8') do | config |
        config.strict
    end
    image_count = 0
    caliber_description_parser.search('img').each do | this_image |
        image_count += 1
    end
    return image_count
end

# Loop through the Caliber fields we wish to mash up into a Rally Description
# and combine them as needed into Rally description markup
def make_description_from_requirement(requirement)

    project = requirement['project']
    if project == $jdf_zeus_control_project then
        $description_field_hash['Caliber Validation'] = 'caliber_validation'
    end

    story_description = ''

    $description_field_hash.each do | field_title, field_key |
        field_string = requirement[field_key]
        story_description += make_header(field_title)
        if !field_string.nil? then
            story_description += field_string
        end
    end
    story_description += "<br>"
    if story_description.length > 32000
        @logger.warn "Story Description Length: #{story_description.length} Exceeds Rally limit of 32K. Description is truncated."
        story_description_shortened = story_description[0..32000]
        story_description = story_description_shortened
    end
    return story_description
end

# Mash Caliber Open Issues data into a notes field for Rally Story
def make_notes_from_requirement(requirement)
    notes = make_header('Caliber Open Issues')
    notes += requirement['open_issues']
end

# Take Caliber Requirement hash, process and combine field data and create a story in Rally
def create_story_from_caliber(requirement)

    req_id = requirement['id']
    req_hierarchy = requirement['hierarchy']
    req_project = requirement['project']
    req_description = requirement['description']

    @logger.info "Processing Caliber Requirement ID: #{req_id}; Hierarchy: #{req_hierarchy}; Project: #{req_project}"

    story = {}
    story["Name"]                   = make_name_from_requirement(requirement)
    story["Description"]            = make_description_from_requirement(requirement)
    story["Notes"]                  = make_notes_from_requirement(requirement)
    story[$caliber_id_field_name]   = requirement['id']
    begin
        story = @rally.create("hierarchicalrequirement", story)
        story.read
        story_oid = story['ObjectID']
        @logger.info "Successfully Created Rally Story: ObjectID #{story_oid}; from CaliberID: #{req_id}."
        return story
    rescue => ex
        @logger.error "Error occurred creating Rally Story from Caliber Requirement ID: #{req_id}. Not imported."
        @logger.error ex.message
        @logger.error ex.backtrace
    end
end

# Pulls HTML content out of <html><body> tags
def process_description_body(description)
    if !description.eql?("") then
        description_html = Nokogiri::HTML(description, 'UTF-8') do | config |
            config.strict
        end
        this_html = description_html.search('html').first
        this_body = this_html.search('body').first
        body_content = this_body.children.to_s.gsub("\n", "")
    else
        body_content = ""
    end
    return body_content
end

# Post-import service to stitch up Story Hierarchy in Rally based on hash of Parent Rally Stories
# by Caliber Hierarchy ID that we created during initial import
def post_import_hierarchy_stitch()
    @logger.info "Starting post-service to parent Rally User Stories According to Caliber Hierarchy."

    parents_stitched = 0
    @caliber_parent_hash.each_pair do | this_hierarchy_id, this_parent_hierarchy_id |
        if this_parent_hierarchy_id != $no_parent_id then
            child_story = @rally_story_hierarchy_hash[this_hierarchy_id]
            child_story_oid = child_story['ObjectID']
            parent_story = @rally_story_hierarchy_hash[this_parent_hierarchy_id]
            parent_story_oid = parent_story['ObjectID']

            @logger.info "Parenting Child Hierarchy ID: #{this_hierarchy_id} with Story ObjectID: #{child_story_oid} to: "
            @logger.info "         Parent Hierarchy ID: #{this_parent_hierarchy_id} with Story ObjectID: #{parent_story_oid}."
            update_fields = {}
            update_fields["Parent"] = parent_story._ref
            begin
                @rally.update("hierarchicalrequirement", child_story_oid, update_fields)
                @logger.info "Successfully Parented Rally Story: ObjectID #{child_story_oid}; to Story: #{parent_story_oid}."
            rescue => ex
                @logger.error "Error occurred attempting to Parent Rally Story: ObjectID #{child_story_oid}; to Story: #{parent_story_oid}."
                @logger.error ex.message
                @logger.error ex.backtrace
            end
        end
    end
end

# Simple lookup for mimetypes by file extension
def get_mimetype_from_extension(file_ext)
    valid_mime_types = {
        "bmp"    => "image/bmp",
        "gif"    => "image/gif",
        "jpeg"   => "image/jpeg",
        "jpg"    => "image/jpeg",
        "png"    => "image/png"
    }
    return valid_mime_types[file_ext]
end

# turns 0E2050EC-A2BD-4432-92A3-5B74027FC4AE.JPG (caliber name) into:
# img961.jpg, image/jpg
# (img961 is the ID in the Caliber XML)
def get_image_metadata(image_file, image_id)
    image_filename = File.basename(image_file)
    filename_split = image_filename.split("\.")
    file_extension = filename_split[-1].downcase
    new_attachment_name = "#{image_id}.#{file_extension}"
    attachment_mimetype = get_mimetype_from_extension(file_extension)
    return image_filename, attachment_mimetype
end

# Takes a Rally attachment object and filename string and returns a
# relative URL to the attachment in Rally of the form:
# /slm/attachment/12345678910/file.jpg
def get_url_from_attachment(rally_attachment, filename)
    attachment_oid = rally_attachment["ObjectID"].to_s
    return "/slm/attachment/#{attachment_oid}/#{filename}"
end

# Creates an image (png, gif, jpg, bmp) image in rally
# and returns the Rally attachment object
def create_image_attachment(attachment_data_hash)

    # Base64-encoded string of image bytes for upload to Rally
    attachment_content_string = Base64.encode64(attachment_data_hash[:bytes])

    # Create Rally Attachment Content Object
    attachment_content = @rally.create(:attachmentcontent, {"Content" => attachment_content_string})

    # Now create Rally Attachment and wire it up to Story
    attachment_fields = {}
    attachment_fields["Name"]                  = attachment_data_hash[:name]
    attachment_fields["ContentType"]           = attachment_data_hash[:mimetype]
    attachment_fields["Content"]               = attachment_content
    attachment_fields["Artifact"]              = attachment_data_hash[:artifact]
    attachment_fields["Size"]                  = attachment_data_hash[:size]
    attachment = @rally.create(:attachment, attachment_fields)

    @logger.info "Imported #{attachment_data_hash[:name]} and attached to Rally Story with ObjectD: #{attachment_data_hash[:artifactoid]}."
    return attachment
end

# Loops through Description on Rally Story and replaces embedded <img src="file:\\\blah\blah1\blah2.jpg"
# References with <img src="/slm/attachment/12345678910/blah2.jpg" type of references once we've imported
# the embedded images to Rally as attachments
def fix_description_images(story_oid, story_description, rally_attachment_sources)

    index = 0
    description_doc = Nokogiri::HTML(story_description)
    description_doc.css('img').each do | img |
        img.set_attribute('src', rally_attachment_sources[index])
        index += 1
    end

    new_description = description_doc.to_s
    # Rip out <html><body> tags
    new_description = process_description_body(new_description)

    update_fields = {}
    update_fields["Description"] = new_description
    updated_story = @rally.update("hierarchicalrequirement", story_oid, update_fields)
    @logger.info "Updated Rally Story ObjectID: #{story_oid} with embedded images."

end

# Post-import image import service
# Loops through hash of image data hashes keyed by Rally Story OID
# and:
# - Creates an attachment in Rally corresponding to the image from Caliber
# - Stitches Rally's image URL back into Rally Story description <img src="" tags
#   to effect "in-lining" of the images in the Rally Story description
def import_images()
    @logger.info "Starting post-service to import Caliber images for requirements that have embedded images."
    @rally_stories_with_images_hash.each_pair do | this_story_oid, this_caliber_image_data |

        this_image_list         = this_caliber_image_data["files"]
        this_image_id_list      = this_caliber_image_data["ids"]
        this_story_description  = this_caliber_image_data["description"]
        this_story_ref          = this_caliber_image_data["storyref"]

        index = 0

        # Array with relative URL's to Rally-embedded attachments
        new_attachment_sources = []

        this_image_list.each do | this_image_file |
            if File.exist?(this_image_file) then
                image_bytes = File.open(this_image_file, 'rb') { | file | file.read }
                image_id = this_image_id_list[index]
                attachment_name, mimetype = get_image_metadata(this_image_file, image_id)

                if mimetype.nil? then
                    @logger.warn "Invalid mime-type encountered! Skipped importing image file #{this_image_file} to Rally Description on Story with ObjectID: #{this_story_oid}."
                    next
                end
                if image_bytes.length > $max_attachment_length then
                    @logger.warn "Attachment size of #{image_bytes.length} exceeds Rally allowed maximum of 5 MB. Skipped importing image file #{this_image_file} on Story with ObjectID: #{this_story_oid}"
                    next
                end
                begin
                    attachment_info_hash = {
                        :bytes           => image_bytes,
                        :name            => attachment_name,
                        :mimetype        => mimetype,
                        :artifact        => this_story_ref,
                        :artifactoid     => this_story_oid,
                        :size            => image_bytes.length
                    }
                    attachment_object = create_image_attachment(attachment_info_hash)
                    attachment_src_url = get_url_from_attachment(attachment_object, attachment_name)

                    # Store the actual Rally URL (not REST URL) of the attachment, looks like this:
                    # /slm/attachment/1234578910/myAttachment.jpg
                    # So that we can stitch it back into the Description to "in-line" the image
                    new_attachment_sources.push(attachment_src_url)
                rescue => ex
                    @logger.error "Error occurred trying to create attachment from #{this_image_file} for Rally Story with ObjectID: #{this_story_oid}."
                    @logger.error ex.message
                    @logger.error ex.backtrace
                end
            else
                @logger.warn "Caliber image file: #{this_image_file} not found. Skipped importing image to Rally Description on Story with ObjectID: #{this_story_oid}."
            end
            index += 1
        end

        # Stitch the attachment url into Rally Descritpion and replace embedded
        # <img src="file:\\\blah\blah1\blah2.jpg"
        # tags of the Rally Description with new URL data from actual attachment in Rally
        fix_description_images(this_story_oid, this_story_description, new_attachment_sources)
    end
end

begin

#==================== Connect to Rally and Import Caliber data ====================

    #Setting custom headers
    $headers                            = RallyAPI::CustomHttpHeader.new()
    $headers.name                       = "Caliber Requirement Importer"
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
    log_file = File.open("caliber2rally.log", "a")
    log_file.sync = true
    @logger = Logger.new MultiIO.new(STDOUT, log_file)

    @logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL

    # Output CSV of Requirement data
    requirements_csv = CSV.open($my_output_file, "wb", {:col_sep => $my_delim})
    requirements_csv << $requirement_fields

    # Output CSV of Story OID's by Caliber Requirement Name
    story_oid_csv    = CSV.open($story_oid_output_csv, "wb", {:col_sep => $my_delim})
    story_oid_csv    << $story_oid_output_fields


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
    caliber_data.search($report_tag).each do | report |
        report.search($requirement_type_tag).each do | req_type |
            req_type.search($requirement_tag).each do | requirement |

                # Data - holds output for CSV
                requirement_data = []
                story_oid_data         = []

                # Store fields that derive from Project and Requirement objects
                this_requirement = $caliber_requirement_record_template
                this_requirement['project']             = report['project']
                this_requirement['hierarchy']           = requirement['hierarchy']
                this_requirement['id']                  = requirement['id']
                this_requirement['name']                = requirement['name'] || ""

                # process_description_body pulls HTML content out of <html><body> tags
                this_requirement['description']         = process_description_body(requirement['description'] || "")
                this_requirement['validation']          = requirement['validation'] || ""

                # Store Caliber ID, HierarchyID, Project and Name in variables for convenient logging output
                req_id                                  = this_requirement['id']
                req_hierarchy                           = this_requirement['hierarchy']
                req_project                             = this_requirement['project']
                req_name                                = this_requirement['name']

                @logger.info "Started Reading Caliber Requirement ID: #{req_id}; Hierarchy: #{req_hierarchy}; Project: #{req_project}"

                # Loop through UDAValue records and cache fields from them
                # There are many UDAValue records per requirement and each is different
                # So assign to values of interest via case statement
                requirement.search($uda_values_tag).each do | uda_values |
                    uda_values.search($uda_value_tag).each do | uda_value |
                        uda_value_name = uda_value['name']
                        uda_value_value = uda_value['value'] || ""
                        case uda_value_name
                            when $uda_value_name_purpose
                                this_requirement['caliber_purpose']    = uda_value_value
                            when $uda_value_name_pre_condition
                                this_requirement['pre_condition']      = uda_value_value
                            when $uda_value_name_basic_course
                                this_requirement['basic_course']       = uda_value_value
                            when $uda_value_name_post_condition
                                this_requirement['post_condition']     = uda_value_value
                            when $uda_value_name_exceptions
                                this_requirement['exceptions']         = uda_value_value
                            when $uda_value_name_remarks
                                this_requirement['remarks']            = uda_value_value
                            when $uda_value_name_open_issues
                                this_requirement['open_issues']        = uda_value_value
                        end
                    end
                end

                @logger.info "Finished Reading Caliber Requirement ID: #{req_id}; Hierarchy: #{req_hierarchy}; Project: #{req_project}"

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
                    story = create_story_from_caliber(this_requirement)
                end

                # Save the Story OID and associated it to the Caliber Hierarchy ID for later use
                # in stitching
                @rally_story_hierarchy_hash[req_hierarchy] = story

                # Get the Parent hierarchy ID for this Caliber Requirement
                parent_hierarchy_id = get_parent_hierarchy_id(this_requirement)
                @logger.info "Parent Hierarchy ID: #{parent_hierarchy_id}"

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
                caliber_image_count = count_images_in_caliber_description(this_requirement['description'])

                if caliber_image_count > 0 then
                    description_with_images = this_requirement['description']
                    image_file_objects, image_file_ids = get_caliber_image_files(description_with_images)
                    caliber_image_data = {
                        "files"           => image_file_objects,
                        "ids"             => image_file_ids,
                        "description"     => description_with_images,
                        "storyref"        => story["_ref"]
                    }
                    @rally_stories_with_images_hash[story["ObjectID"].to_s] = caliber_image_data
                end

                # Record requirement data for CSV output
                this_requirement.each_pair do | key, value |
                    requirement_data << value
                end

                # Post-pend to CSV
                requirements_csv << CSV::Row.new($requirement_fields, requirement_data)

                # Output story OID and Caliber requirement name
                # So we can use this information later when importing traces
                story_oid_data << req_name
                story_oid_data << story["ObjectID"]
                # Post-pend to CSV
                story_oid_csv  << CSV::Row.new($story_oid_output_fields, story_oid_data)

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
        @logger.info "Finished Processing Caliber Requirements for import to Rally. Total Stories Processed: #{import_count}."
    else
        @logger.info "Finished Importing Caliber Requirements to Rally. Total Stories Created: #{import_count}."
    end

    # Run the hierarchy stitching service
    if $stitch_hierarchy then
        post_import_hierarchy_stitch()
    end

    # Run the image import service
    # Necessary to run the image import as a post-Story creation service
    # Because we have to have an Artifact in Rally to attach _to_.
    if $import_images_flag
        import_images()
    end
end
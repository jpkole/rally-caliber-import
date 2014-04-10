class CaliberHelper

    def initialize(project, id_fieldname, field_hash, image_directory, logger_instance, weblink_fieldname = nil ) #{
        # ----------------------------------------------------------------------
        @caliber_project            = project
        @caliber_id_field_name      = id_fieldname
        @description_field_hash     = field_hash
        @caliber_image_directory    = image_directory
        @logger                     = logger_instance
        @caliber_weblink_field_name = weblink_fieldname
        @max_attachment_length      = 5_000_000

        # Flag to set in @rally_story_hierarchy_hash if Requirement has no Parent
        @no_parent_id               = "-9999"

        # JDF Project setting
        @jdf_zeus_control_project   = "JDF-Zeus_Control-project"
    end #} end of "def initialize(project, id_fieldname, field_hash, image_directory, logger_instance, weblink_fieldname = nil )"


    def display_vars #{
        # Report all vars
        @logger.info "Running #{$PROGRAM_NAME} with the following settings:
                $my_base_url                                = #{$my_base_url}
                $my_username                                = #{$my_username}
                $my_wsapi_version                           = #{$my_wsapi_version}
                $my_workspace                               = #{$my_workspace}
                $my_project                                 = #{$my_project}
                $max_attachment_length                      = #{$max_attachment_length}
                $max_description_length                     = #{$max_description_length}
                $caliber_file_req                           = #{$caliber_file_req}
                $caliber_file_req_traces                    = #{$caliber_file_req_traces}
                $caliber_file_tc                            = #{$caliber_file_tc}
                $caliber_file_tc_traces                     = #{$caliber_file_tc_traces}
                $caliber_image_directory                    = #{$caliber_image_directory}
                $caliber_id_field_name                      = #{$caliber_id_field_name}
                $caliber_weblink_field_name                 = #{$caliber_weblink_field_name}
                $caliber_req_traces_field_name              = #{$caliber_req_traces_field_name}
                $caliber_tc_traces_field_name               = #{$caliber_tc_traces_field_name}
                $max_import_count                           = #{$max_import_count}
                $html_mode                                  = #{$html_mode}
                $preview_mode                               = #{$preview_mode}
                $csv_requirements                           = #{$csv_requirements}
                $csv_requirement_fields                     = #{$csv_requirement_fields}
                $csv_US_OidCidReqname_by_FID                = #{$csv_US_OidCidReqname_by_FID}
                $csv_US_OidCidReqname_by_FID_fields         = #{$csv_US_OidCidReqname_by_FID_fields}
                $csv_testcases                              = #{$csv_testcases}
                $csv_TC_OidCidReqname_by_FID                = #{$csv_TC_OidCidReqname_by_FID}
                $csv_TC_OidCidReqname_by_FID_fields         = #{$csv_TC_OidCidReqname_by_FID_fields}
                $cal2ral_req_log                            = #{$cal2ral_req_log}
                $cal2ral_req_traces_log                     = #{$cal2ral_req_traces_log}
                $cal2ral_tc_log                             = #{$cal2ral_tc_log}
                $cal2ral_tc_traces_log                      = #{$cal2ral_tc_traces_log}
"
    end #} end of "def display_vars"


    def get_rally_connection #{
        @logger.info "Initiating connection to Rally: #{$my_base_url}"
        @rally = RallyAPI::RallyRestJson.new({
                           :base_url       => $my_base_url,
                           :username       => $my_username,
                           :password       => $my_password,
                           :workspace      => $my_workspace,
                           :project        => $my_project,
                           :version        => $my_wsapi_version,
                           :headers        => RallyAPI::CustomHttpHeader.new(
                                                :name       => "Caliber Importer",
                                                :vendor     => "Rally Technical Services",
                                                :version    => "0.60"       )
                                            })
        return @rally
    end #} end of "def get_rally_connection"


    def get_mimetype_from_extension(file_ext) #{
        # ----------------------------------------------
        # Simple lookup for mimetypes by file extension
        valid_mime_types = {
            "bmp"    => "image/bmp",
            "gif"    => "image/gif",
            "jpeg"   => "image/jpeg",
            "jpg"    => "image/jpeg",
            "png"    => "image/png",
            "ico"    => "image/icon",
            "emf"    => "image/emf",
            "wmf"    => "image/wmf"
        }
        if valid_mime_types.has_key?(file_ext)
            return valid_mime_types[file_ext]
        else
            @logger.error "Unrecognized mimetype '#{file_ext}' found."
        end
    end #} end of "def get_mimetype_from_extension(file_ext)"


    def get_image_metadata(image_file, image_id) #{
        # ----------------------------------------------
        # turns 0E2050EC-A2BD-4432-92A3-5B74027FC4AE.JPG (caliber name) into:
        # img961.jpg, image/jpg
        # (img961 is the ID in the Caliber XML)
        image_filename      = File.basename(image_file)
        filename_split      = image_filename.split("\.")
        file_extension      = filename_split[-1].downcase
        new_attachment_name = "#{image_id}.#{file_extension}"
        attachment_mimetype = get_mimetype_from_extension(file_extension)
        return image_filename, attachment_mimetype
    end #} end of "def get_image_metadata(image_file, image_id)"


    def create_image_attachment(attachment_data_hash) #{
        # ----------------------------------------------
        # Creates an image (png, gif, jpg, bmp) image in rally
        # and returns the Rally attachment object

        # Base64-encoded string of image bytes for upload to Rally
        attachment_content_string = Base64.encode64(attachment_data_hash[:bytes])

        # Create Rally Attachment Content Object
        attachment_content = @rally.create(:attachmentcontent, {"Content" => attachment_content_string})

        # Now create Rally Attachment and wire it up to Story
        attachment_fields = {}
        attachment_fields["Name"]        = attachment_data_hash[:name]
        attachment_fields["ContentType"] = attachment_data_hash[:mimetype]
        attachment_fields["Content"]     = attachment_content
        attachment_fields["Artifact"]    = attachment_data_hash[:artifact]
        attachment_fields["Size"]        = attachment_data_hash[:size]
        attachment = @rally.create(:attachment, attachment_fields)

        @logger.info "            created Rally Attachment Artifact: OID=#{attachment.ObjectID}; Orig/Base64 sizes=#{attachment_data_hash[:bytes].length}/#{attachment_content_string.length}"
        return attachment
    end #} end of "def create_image_attachment(attachment_data_hash)"


    def fix_description_images(artifact_fmtid, artifact_ref, artifact_description, rally_attachment_sources) #{
        # ----------------------------------------------
        # Loops through Description on Rally Story and replaces embedded <img src="file:\\\blah\blah1\blah2.jpg"
        # References with <img src="/slm/attachment/12345678910/blah2.jpg" type of references once we've imported
        # the embedded images to Rally as attachments
        index = 0
        description_doc = Nokogiri::HTML(artifact_description)
        description_doc.css('img').each do | img |
            img.set_attribute('src', rally_attachment_sources[index])
            index += 1
        end
        new_description = description_doc.to_s
        # Rip out <html><body> tags
        new_description = process_description_body(new_description)
        artifact_type = artifact_ref.split("/")[-2]
        artifact_oid  = artifact_ref.split("/")[-1].split("\.")[-2]
        update_fields = {}
        update_fields["Description"] = new_description
        updated_artifact = @rally.update(artifact_type, artifact_oid, update_fields)
        @logger.info "        updated Rally Artifact; FmtID=#{artifact_fmtid}; OID=#{artifact_oid} with embedded images."
    end #} end of "def fix_description_images(artifact_fmtid, artifact_ref, artifact_description, rally_attachment_sources)"


    def import_images(artifacts_with_images_hash) #{
        # ----------------------------------------------
        # Post-import image import service
        # Loops through hash of image data hashes keyed by Rally Artifact OID and:
        # - Creates an attachment in Rally corresponding to the image from Caliber
        # - Stitches Rally's image URL back into Rally Artifact description <img src="" tags
        #   to effect "in-lining" of the images in the Rally Artifact description
        if artifacts_with_images_hash.count > 0 then
            @logger.info "Starting post-service processing to import Caliber images for requirements that have embedded images."
        else
            @logger.info "No images found for processing."
        end

        artifact_count = 0
        artifacts_with_images_hash.each_pair do | this_artifact_oid, this_caliber_image_data |

            artifact_count += 1

            this_image_list             = this_caliber_image_data["files"]
            this_image_id_list          = this_caliber_image_data["ids"]
            this_image_title_list       = this_caliber_image_data["titles"]
            this_artifact_description   = this_caliber_image_data["description"]
            this_artifact_fmtid         = this_caliber_image_data["fmtid"]
            this_artifact_ref           = this_caliber_image_data["ref"]
            # Array with relative URL's to Rally-embedded attachments
            new_attachment_sources = []

            @logger.info "    Import #{artifact_count} of #{artifacts_with_images_hash.length}: adding #{this_image_list.length} image(s) to Rally User Story; FmtID=#{this_artifact_fmtid}; OID=#{this_artifact_oid}"
            this_image_list.each_with_index do | this_image_file, indx_image | #{

                @logger.info "        importing image file #{indx_image+1} of #{this_image_list.length}: id=#{this_image_title_list[indx_image]}; Name=#{File.basename(this_image_file)}"

                if !File.exist?(this_image_file) then #{
                    @logger.warn "    *** image file: #{this_image_file} not found; skipping import of this image."
                else
                    image_bytes = File.open(this_image_file, 'rb') { | file | file.read }
                    image_id = this_image_id_list[indx_image]
                    image_title = this_image_title_list[indx_image]
                    #attachment_name, mimetype = get_image_metadata(this_image_file, image_id)
                    attachment_name, mimetype = get_image_metadata(this_image_file, image_title)

                    if mimetype.nil? then
                        @logger.warn "    *** invalid mime-type; skipping import of this image."
                        next
                    end
                    if image_bytes.length > @max_attachment_length then
                        @logger.warn "    *** attachment size #{image_bytes.length} > #{@max_attachment_length} bytes; skipping import of this image."
                        next
                    end
                    begin
                        attachment_info_hash = {
                            :bytes           => image_bytes,
                            :name            => attachment_name,
                            :mimetype        => mimetype,
                            :artifact        => this_artifact_ref,
                            :artifactoid     => this_artifact_oid,
                            :size            => image_bytes.length
                        }
                        attachment_object = create_image_attachment(attachment_info_hash)
                        #attachment_src_url = get_url_from_attachment(attachment_object, attachment_name)
                        # Rally attachment object and filename ->into-> relative URL to the attachment in Rally of the form: /slm/attachment/12345678910/file.jpg
                        attachment_src_url = "/slm/attachment/#{attachment_object["ObjectID"].to_s}/#{attachment_name}"

                        # Store the actual Rally URL (not REST URL) of the attachment, looks like this:
                        # /slm/attachment/1234578910/myAttachment.jpg
                        # So that we can stitch it back into the Description to "in-line" the image
                        new_attachment_sources.push(attachment_src_url)
                    rescue => ex
                        @logger.error "Error occurred trying to create attachment from #{this_image_file} for Rally Artifact with OID=#{this_artifact_oid}"
                        @logger.error ex.message
                        @logger.error ex.backtrace
                    end
                end #} end of "if !File.exist?(this_image_file) then"
            end #} end of "this_image_list.each do | this_image_file |"

            # Stitch the attachment url into Rally Description and replace embedded
            # <img src="file:\\\blah\blah1\blah2.jpg"
            # tags of the Rally Description with new URL data from actual attachment in Rally
            fix_description_images(this_artifact_fmtid, this_artifact_ref, this_artifact_description, new_attachment_sources)
        end
        @logger.info "End of post-service to import Caliber images for requirements that have embedded images."
    end #} end of "def import_images(artifacts_with_images_hash)"


    def get_parent_hierarchy_id(requirement)
        # ----------------------------------------------
        # Caliber hierarchy id's look like: 1.1.1, as an example
        # The parent requirement of 1.1.1 would be 1.1
        # This function returns the value "1.1" as the parent of "1.1.1"
        hierarchy_id = requirement['hierarchy']
        hierarchy_id_split = hierarchy_id.split('.')
        hierarchy_depth = hierarchy_id_split.length
        if hierarchy_depth > 1 then
            # [0..hierarchy_depth-2] goes through 2nd to last element
            parent_hierarchy_arr = hierarchy_id_split[0..hierarchy_depth-2]
            parent_id_string = parent_hierarchy_arr.join(".")
        else
            parent_id_string = @no_parent_id
        end
        return parent_id_string
    end


    def make_name(caliber_object, object_type)
        # ----------------------------------------------
        # Combines Caliber name, Caliber hiearachy id (1.1.1), and Caliber id (1234)
        # fields, into a single string for Rally Story name
        hierarchy   = caliber_object['hierarchy']
        obj_id      = caliber_object['id']
        name        = caliber_object['name']

        if object_type == :requirement then
            obj_type_prefix = "REQ"
        elsif object_type == :testcase then
            obj_type_prefix = "TC"
        else
            obj_type_prefix = "UNKNOWN"
        end

        return "Caliber #{hierarchy} #{obj_type_prefix} #{obj_id}: #{name}"
    end


    def get_caliber_image_files(caliber_description) #{
        # ----------------------------------------------
        # Prepares arrays of File references and Caliber image id attributes
        # from Caliber Description markup
        caliber_description_parser = Nokogiri::HTML(caliber_description, 'UTF-8') do | config |
            config.strict
        end

        caliber_image_files = []
        caliber_image_ids = []
        caliber_image_titles = []
        caliber_description_parser.search('img').each do | this_image |
            image_id            = this_image['id']
            image_title         = this_image['title']
            image_src           = this_image['src']
            image_url_unescaped = URI.unescape(image_src)
            image_file_name     = image_url_unescaped.split("\\")[-1]
            image_file          = File.dirname(__FILE__) + "/#{@caliber_image_directory}/#{image_file_name}"
            caliber_image_files.push(image_file)
            caliber_image_ids.push(image_id)
            caliber_image_titles.push(image_title)
        end
        return caliber_image_files, caliber_image_ids, caliber_image_titles
    end #} end of "def get_caliber_image_files(caliber_description)"


    def count_images_in_caliber_description(caliber_description)
        # ----------------------------------------------
        # Parses through caliber description markup and
        # looks for <img> tags
        caliber_description_parser = Nokogiri::HTML(caliber_description, 'UTF-8') do | config |
            config.strict
        end
        image_count = 0
        caliber_description_parser.search('img').each do | this_image |
            image_count += 1
        end
        return image_count
    end


    def create_markup_from_hash(caliber_object, markup_hash, obj_type) #{
        # ----------------------------------------------
        # Loop through the Caliber fields we wish to mash up into a Rally Description
        # and combine them as needed into Rally description markup
        project = caliber_object['project']
        if project == @jdf_zeus_control_project && obj_type == :testcase then
            @description_field_hash['Caliber Validation'] = 'caliber_validation'
        end

        artifact_markup = ''
        markup_hash.each do | field_title, field_key |
            field_string = caliber_object[field_key]
            artifact_markup += "<p><b>#{field_title}</b></p>"
            if !field_string.nil? then
                artifact_markup += field_string
            end
        end
        artifact_markup += "<br/>"
        if artifact_markup.length <= $max_description_length
            return artifact_markup
        else
            @logger.warn "        *** Description length: #{artifact_markup.length} exceeds Rally limit of #{$max_description_length}; truncated; CID=#{caliber_object["id"]}"
            trunc_warn = '*** Too long; TRUNCATED! ***'

            # Save a copy of the description (that is too long), into its own file.
            # (the block around write has the added benefit of closing the file)
            File.open("Desc-REQ"+caliber_object["id"]+".txt", 'w') do |file|
                file.write(artifact_markup)
            end

            # Return a truncated Description with an appended warning
            return (artifact_markup[0..$max_description_length-trunc_warn.length-1] + trunc_warn)
        end
    end #} end of "def create_markup_from_hash(caliber_object, markup_hash, obj_type)"


    def create_story_from_caliber(requirement) #{
        # ----------------------------------------------
        # Take Caliber Requirement hash, process and combine field data and create a story in Rally
        story = {}
        story["Name"]                   = make_name(requirement, :requirement)
        description = create_markup_from_hash(requirement, @description_field_hash, :requirement)
        if !description.nil? then
            # Within an <img...> tag, Rally no longer allows src= strings which have a leading "file://"; so change it to "http://".
            description = description.gsub(/file:\/\//, "http://")
            # Within an <img...> tag, Rally no longer allows id= tags; so change it to "title=" (which are allowed).
            description = description.gsub(/id=/, "title=")
        end
        story["Description"]            = description

        story["Notes"]                  = ""
        story["Notes"]                 += "<p><b>Caliber Open Issues</b></p>"
        if requirement.has_key? 'open_issues'
            story["Notes"]             += requirement['open_issues']
        end
        story["Notes"]                 += "<p><b>Caliber Remarks</b></p>"
        if requirement.has_key? 'remarks'
            story["Notes"]             += requirement['remarks']
        end

        story[@caliber_id_field_name]   = requirement['id']
        begin
            newstory = @rally.create("hierarchicalrequirement", story)
            newstory.read
            newstory_oid = newstory['ObjectID']
            newstory_fid = newstory['FormattedID']
            return newstory
        rescue => ex
            @logger.error "Error occurred creating Rally Story from Caliber Requirement ID: #{requirement['id']}. Not imported."
            @logger.error ex.message
            @logger.error ex.backtrace
        end
    end #} end of "def create_story_from_caliber(requirement)"


    def create_testcase_from_caliber(testcase) #{
        # ----------------------------------------------
        # Take Caliber TestCase hash, process and combine field data and create a TestCase in Rally
        testcase_id                   = testcase['id']
        testcase_hierarchy            = testcase['hierarchy']
        testcase_project              = testcase['project']
        testcase_description          = testcase['description']

        preconditions_field_hash = {
            'Testing Status'             => 'testing_status',
            'Test Running'               => 'test_running',
            'Machine Type'               => 'machine_type'
        }

        #@logger.info "    Processing Caliber TestCase ID: #{testcase_id}; Hierarchy: #{testcase_hierarchy}; Project: #{testcase_project}"

        testcase_fields = {}
        testcase_fields["Name"]                   = make_name(testcase, :testcase)
        testcase_fields["Description"]            = create_markup_from_hash(testcase, @description_field_hash, :testcase)
        testcase_fields["PreConditions"]          = create_markup_from_hash(testcase, preconditions_field_hash, :testcase)
        testcase_fields[@caliber_id_field_name]   = testcase_id

        # Rally requires the following fields for TestCase
        testcase_fields["Method"]                 = "Automated"
        testcase_fields["Type"]                   = "Functional"

        begin
            testcase = @rally.create("testcase", testcase_fields)
            testcase.read
            testcase_oid = testcase['ObjectID']
            return testcase
        rescue => ex
            @logger.error "Error occurred creating Rally TestCase from Caliber TestCase ID: #{testcase_id}. Not imported."
            @logger.error ex.message
            @logger.error ex.backtrace
        end
    end #} end of "def create_testcase_from_caliber(testcase)"


    def process_description_body(description) #{
        # ----------------------------------------------
        # Pulls HTML content out of <html><body> tags

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
    end #} end of "def process_description_body(description)"


    def post_import_hierarchy_stitch(caliber_parent_hash, rally_story_hierarchy_hash) #{
        # ----------------------------------------------
        # Post-import service to stitch up Story Hierarchy in Rally based on hash of Parent Rally Stories
        # by Caliber Hierarchy ID that we created during initial import

        @logger.info "Starting post-service to parent Rally User Stories according to Caliber Hierarchy."

        us_parents_stitched = 0
        tot_us = caliber_parent_hash.length
        caliber_parent_hash.each_pair do | this_hierarchy_id, this_parent_hierarchy_id | #{
            us_parents_stitched += 1
            if this_parent_hierarchy_id == @no_parent_id then
                @logger.info "    No parenting for (##{us_parents_stitched} of #{tot_us}); top-level Child Hierarchy #{this_hierarchy_id}"
                next
            end
            child_story = rally_story_hierarchy_hash[this_hierarchy_id]
            child_story_oid = child_story['ObjectID']
            child_story_fid = child_story['FormattedID']

            if rally_story_hierarchy_hash[this_parent_hierarchy_id].nil? then
                @logger.info "    No parent found for (##{us_parents_stitched} of #{tot_us}); Child Hierarchy #{this_hierarchy_id}"
                next
            end

            parent_story = rally_story_hierarchy_hash[this_parent_hierarchy_id]
            parent_story_oid = parent_story['ObjectID']
            parent_story_fid = parent_story['FormattedID']
            update_fields = {}
            update_fields["Parent"] = parent_story._ref

            @logger.info "    Parenting (##{us_parents_stitched} of #{tot_us}); Child Hierarchy #{this_hierarchy_id}: Rally UserStory: FmtID=#{child_story_fid}; OID=#{child_story_oid} to:"
            @logger.info "        parent Hierarchy #{this_parent_hierarchy_id}: Rally UserStory: FmtID=#{parent_story_fid}; OID=#{parent_story_oid}"
            begin
                @rally.update("hierarchicalrequirement", child_story_oid, update_fields)
            rescue => ex
                @logger.error "Error occurred attempting to Parent Rally Story: OID=#{child_story_oid}; to Story: OID=#{parent_story_oid}"
                @logger.error ex.message
                @logger.error ex.backtrace
            end
        end #} end of "caliber_parent_hash.each_pair do | this_hierarchy_id, this_parent_hierarchy_id |"

        @logger.info "End of post-service to parent Rally UserStoryies according to Caliber hierarchy."

    end #} end of "def post_import_hierarchy_stitch(caliber_parent_hash, rally_story_hierarchy_hash)"


    def post_import_testcase_hierarchy_linker(caliber_parent_hash, rally_testcase_hierarchy_hash) #{
        # ----------------------------------------------
        # Post-import service to create weblinks that link TestCase Hierarchy in Rally
        # based on hash of Parent Rally TestCases
        # by Caliber Hierarchy ID that we created during initial import
        @logger.info "Starting post-service to create weblinks from Rally TestCases to their parents According to Caliber Hierarchy."

        tc_parents_stitched = 0
        tot_tc = caliber_parent_hash.length
        caliber_parent_hash.each_pair do | this_hierarchy_id, this_parent_hierarchy_id | #{
            tc_parents_stitched += 1
            if this_parent_hierarchy_id == @no_parent_id then
                @logger.info "    No parenting for (##{tc_parents_stitched} of #{tot_tc}); top-level Child Hierarchy #{this_hierarchy_id}"
                next
            end
            child_testcase = rally_testcase_hierarchy_hash[this_hierarchy_id]
            child_testcase_oid = child_testcase['ObjectID']
            child_testcase_fid = child_testcase['FormattedID']

            if rally_testcase_hierarchy_hash[this_parent_hierarchy_id].nil? then
                @logger.info "    No parent found for (##{tc_parents_stitched} of #{tot_tc}); Child Hierarchy #{this_hierarchy_id}"
                next
            end

            parent_testcase = rally_testcase_hierarchy_hash[this_parent_hierarchy_id]
            parent_testcase_oid = parent_testcase['ObjectID']
            parent_testcase_fid = parent_testcase['FormattedID']
            parent_web_link = {}
            parent_web_link["LinkID"] = parent_testcase_oid
            parent_web_link["DisplayString"] = "Caliber Parent TestCase"
            update_fields = {}
            update_fields[@caliber_weblink_field_name] = parent_web_link

            @logger.info "    Parenting (##{tc_parents_stitched} of #{tot_tc}); Child Hierarchy #{this_hierarchy_id}: Rally TestCase: FmtID=#{child_testcase_fid}; OID=#{child_testcase_oid} to:"
            @logger.info "        parent Hierarchy #{this_parent_hierarchy_id}: Rally Testcase: FmtID=#{parent_testcase_fid}; OID=#{parent_testcase_oid}"
            begin
                @rally.update("testcase", child_testcase_oid, update_fields)
            rescue => ex
                @logger.error "Error occurred attempting to Link Rally TestCase: OID=#{child_testcase_oid}; to TestCase: OID=#{parent_testcase_oid}"
                @logger.error ex.message
                @logger.error ex.backtrace
            end
        end #} end of "caliber_parent_hash.each_pair do | this_hierarchy_id, this_parent_hierarchy_id |"

        @logger.info "End of post-service to parent Rally TestCases according to Caliber hierarchy."

    end #} end of "def post_import_testcase_hierarchy_linker(caliber_parent_hash, rally_testcase_hierarchy_hash)"

end

class CaliberHelper

    def initialize(rally_connection, project, id_fieldname, field_hash,
        image_directory, logger_instance, weblink_fieldname = nil )

        @rally                           = rally_connection
        @caliber_project                 = project
        @caliber_id_field_name           = id_fieldname
        @description_field_hash          = field_hash
        @caliber_image_directory         = image_directory
        @logger                          = logger_instance
        @caliber_weblink_field_name      = weblink_fieldname
        @max_attachment_length           = 5000000

        # Flag to set in @rally_story_hierarchy_hash if Requirement has no Parent
        @no_parent_id                    = "-9999"

        # JDF Project setting
        @jdf_zeus_control_project        = "JDF-Zeus_Control-project"
    end

    # Simple lookup for mimetypes by file extension
    def get_mimetype_from_extension(file_ext)
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
    end

    # turns 0E2050EC-A2BD-4432-92A3-5B74027FC4AE.JPG (caliber name) into:
    # img961.jpg, image/jpg
    # (img961 is the ID in the Caliber XML)
    def get_image_metadata(image_file, image_id)
        image_filename      = File.basename(image_file)
        filename_split      = image_filename.split("\.")
        file_extension      = filename_split[-1].downcase
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
        attachment_fields["Name"]        = attachment_data_hash[:name]
        attachment_fields["ContentType"] = attachment_data_hash[:mimetype]
        attachment_fields["Content"]     = attachment_content
        attachment_fields["Artifact"]    = attachment_data_hash[:artifact]
        attachment_fields["Size"]        = attachment_data_hash[:size]
        attachment = @rally.create(:attachment, attachment_fields)

        @logger.info "    Imported #{attachment_data_hash[:name]} and attached to Rally Artifact with ObjectID: #{attachment_data_hash[:artifactoid]}"
        return attachment
    end

    # Loops through Description on Rally Story and replaces embedded <img src="file:\\\blah\blah1\blah2.jpg"
    # References with <img src="/slm/attachment/12345678910/blah2.jpg" type of references once we've imported
    # the embedded images to Rally as attachments
    def fix_description_images(artifact_ref, artifact_description, rally_attachment_sources)

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
        @logger.info "    Updated Rally Artifact ObjectID: #{artifact_oid} with embedded images."

    end

    # Post-import image import service
    # Loops through hash of image data hashes keyed by Rally Artifact OID
    # and:
    # - Creates an attachment in Rally corresponding to the image from Caliber
    # - Stitches Rally's image URL back into Rally Artifact description <img src="" tags
    #   to effect "in-lining" of the images in the Rally Artifact description
    def import_images(artifacts_with_images_hash) #{
        @logger.info "Starting post-service to import Caliber images for requirements that have embedded images."
        artifacts_with_images_hash.each_pair do | this_artifact_oid, this_caliber_image_data |

            this_image_list            = this_caliber_image_data["files"]
            this_image_id_list         = this_caliber_image_data["ids"]
            this_artifact_description  = this_caliber_image_data["description"]
            this_artifact_ref          = this_caliber_image_data["ref"]

            index = 0

            # Array with relative URL's to Rally-embedded attachments
            new_attachment_sources = []

            this_image_list.each do | this_image_file | #{
                @logger.info "Processing image file #{index+1}: #{File.basename(this_image_file)}..."
                if File.exist?(this_image_file) then
                    image_bytes = File.open(this_image_file, 'rb') { | file | file.read }
                    image_id = this_image_id_list[index]
                    attachment_name, mimetype = get_image_metadata(this_image_file, image_id)

                    if mimetype.nil? then
                        @logger.warn "Invalid mime-type encountered! Skipped importing image file #{this_image_file} to Rally Description on Artifact with ObjectID: #{this_artifact_oid}"
                        next
                    end
                    if image_bytes.length > @max_attachment_length then
                        @logger.warn "Attachment size of #{image_bytes.length} exceeds Rally allowed maximum of 5 MB. Skipped importing image file #{this_image_file} on Artifact with ObjectID: #{this_artifact_oid}"
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
                        attachment_src_url = get_url_from_attachment(attachment_object, attachment_name)

                        # Store the actual Rally URL (not REST URL) of the attachment, looks like this:
                        # /slm/attachment/1234578910/myAttachment.jpg
                        # So that we can stitch it back into the Description to "in-line" the image
                        new_attachment_sources.push(attachment_src_url)
                    rescue => ex
                        @logger.error "Error occurred trying to create attachment from #{this_image_file} for Rally Artifact with ObjectID: #{this_artifact_oid}"
                        @logger.error ex.message
                        @logger.error ex.backtrace
                    end
                else
                    @logger.warn "Caliber image file: #{this_image_file} not found. Skipped importing image to Rally Description on Artifact with ObjectID: #{this_artifact_oid}"
                end
                index += 1
            end #} end of "this_image_list.each do | this_image_file |"

            # Stitch the attachment url into Rally Descritpion and replace embedded
            # <img src="file:\\\blah\blah1\blah2.jpg"
            # tags of the Rally Description with new URL data from actual attachment in Rally
            fix_description_images(this_artifact_ref, this_artifact_description, new_attachment_sources)
        end
    end #} end of "def import_images(artifacts_with_images_hash)"

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
            parent_id_string = @no_parent_id
        end
        @logger.info "    hierarchy_id: #{hierarchy_id} has parent_id: #{parent_id_string}"
        return parent_id_string
    end

    # Combines Caliber name, Caliber hiearachy id (1.1.1), and Caliber id (1234)
    # fields, into a single string for Rally Story name
    def make_name(caliber_object, object_type)

        hierarchy               = caliber_object['hierarchy']
        obj_id                  = caliber_object['id']
        name                    = caliber_object['name']
        if object_type == :requirement then
            obj_type_prefix = "REQ"
        end
        if object_type == :testcase then
            obj_type_prefix = "TC"
        end

        return "<b>Caliber</b> #{hierarchy} #{obj_type_prefix} #{obj_id}: #{name}"
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

            image_file = File.dirname(__FILE__) + "/#{@caliber_image_directory}/#{image_file_name}"
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
    def create_markup_from_hash(caliber_object, markup_hash, obj_type)

        project = caliber_object['project']
        if project == @jdf_zeus_control_project && obj_type == :testcase then
            @description_field_hash['Caliber Validation'] = 'caliber_validation'
        end

        artifact_markup = ''

        markup_hash.each do | field_title, field_key |
            field_string = caliber_object[field_key]
            artifact_markup += make_header(field_title)
            if !field_string.nil? then
                artifact_markup += field_string
            end
        end
        artifact_markup += "<br>"
        if artifact_markup.length > 32000
            @logger.warn "Description Length: #{artifact_markup.length} Exceeds Rally limit of 32K. Description is truncated."
            artifact_markup_shortened = artifact_markup[0..32000]
            artifact_markup = artifact_markup_shortened
        end
        return artifact_markup
    end

    # Mash Caliber Open Issues data into a notes field for Rally Story
    def make_requirement_notes(requirement)
        notes = make_header('Caliber Open Issues')
        if requirement.has_key? 'open_issues'
            notes += requirement['open_issues']
	end
    end

    # Take Caliber Requirement hash, process and combine field data and create a story in Rally
    def create_story_from_caliber(requirement)

        req_id = requirement['id']
        req_hierarchy = requirement['hierarchy']
        req_project = requirement['project']
        req_description = requirement['description']

        @logger.info "    Processing Caliber Requirement ID: #{req_id}; Hierarchy: #{req_hierarchy}; Project: #{req_project}"

        story = {}
        story["Name"]                   = make_name(requirement, :requirement)
        story["Description"]            = create_markup_from_hash(requirement, @description_field_hash,
                                            :requirement)
        story["Notes"]                  = make_requirement_notes(requirement)
        story[@caliber_id_field_name]   = requirement['id']
        begin
            story = @rally.create("hierarchicalrequirement", story)
            story.read
            story_oid = story['ObjectID']
            story_fid = story['FormattedID']
            @logger.info "    Successfully Created Rally Story: #{story_fid}; OID: #{story_oid}; from CaliberID: #{req_id}"
            return story
        rescue => ex
            @logger.error "Error occurred creating Rally Story from Caliber Requirement ID: #{req_id}. Not imported."
            @logger.error ex.message
            @logger.error ex.backtrace
        end
    end

    # Take Caliber TestCase hash, process and combine field data and create a TestCase in Rally
    def create_testcase_from_caliber(testcase)
        testcase_id                   = testcase['id']
        testcase_hierarchy            = testcase['hierarchy']
        testcase_project              = testcase['project']
        testcase_description          = testcase['description']

        preconditions_field_hash = {
            'Testing Status'             => 'testing_status',
            'Test Running'               => 'test_running',
            'Machine Type'               => 'machine_type'
        }

        @logger.info "    Processing Caliber TestCase ID: #{testcase_id}; Hierarchy: #{testcase_hierarchy}; Project: #{testcase_project}"

        testcase_fields = {}
        testcase_fields["Name"]                   = make_name(testcase, :testcase)
        testcase_fields["Description"]            = create_markup_from_hash(testcase, @description_field_hash,
                                                    :testcase)


        testcase_fields["PreConditions"]          = create_markup_from_hash(testcase, preconditions_field_hash,
                                                    :testcase)
        testcase_fields[@caliber_id_field_name]   = testcase_id

        # Rally requires the following fields for TestCase
        testcase_fields["Method"]                 = "Automated"
        testcase_fields["Type"]                   = "Functional"

        begin
            testcase = @rally.create("testcase", testcase_fields)
            testcase.read
            testcase_oid = testcase['ObjectID']
            @logger.info "    Successfully Created Rally TestCase: ObjectID #{testcase_oid}; from CaliberID: #{testcase_id}"
            return testcase
        rescue => ex
            @logger.error "Error occurred creating Rally TestCase from Caliber TestCase ID: #{testcase_id}. Not imported."
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
    def post_import_hierarchy_stitch(caliber_parent_hash, rally_story_hierarchy_hash)
        @logger.info "Starting post-service to parent Rally User Stories According to Caliber Hierarchy."

        parents_stitched = 0
        caliber_parent_hash.each_pair do | this_hierarchy_id, this_parent_hierarchy_id |
            if this_parent_hierarchy_id != @no_parent_id then
                child_story = rally_story_hierarchy_hash[this_hierarchy_id]
                child_story_oid = child_story['ObjectID']
                child_story_fid = child_story['FormattedID']
                parent_story = rally_story_hierarchy_hash[this_parent_hierarchy_id]
                parent_story_oid = parent_story['ObjectID']
                parent_story_fid = parent_story['FormattedID']

                @logger.info "Parenting Child Hierarchy ID: #{this_hierarchy_id} with Story: #{child_story_fid}; OID: #{child_story_oid} to: "
                @logger.info "    Parent Hierarchy ID: #{this_parent_hierarchy_id} with Story: #{parent_story_fid}; OID: #{parent_story_oid}"
                update_fields = {}
                update_fields["Parent"] = parent_story._ref
                begin
                    @rally.update("hierarchicalrequirement", child_story_oid, update_fields)
                    @logger.info "    Successfully Parented Rally Story: #{child_story_fid}; OID: #{child_story_oid}; to Story: #{parent_story_fid}; OID: #{parent_story_oid}"
                rescue => ex
                    @logger.error "Error occurred attempting to Parent Rally Story: ObjectID #{child_story_oid}; to Story: #{parent_story_oid}"
                    @logger.error ex.message
                    @logger.error ex.backtrace
                end
            end
        end
    end

    # Post-import service to create weblinks that link TestCase Hierarchy in Rally
    # based on hash of Parent Rally TestCases
    # by Caliber Hierarchy ID that we created during initial import
    def post_import_testcase_hierarchy_linker(caliber_parent_hash, rally_testcase_hierarchy_hash)
        @logger.info "Starting post-service to create weblinks from Rally TestCases to their parents According to Caliber Hierarchy."

        parents_stitched = 0
        caliber_parent_hash.each_pair do | this_hierarchy_id, this_parent_hierarchy_id |
            if this_parent_hierarchy_id != @no_parent_id then
                child_testcase = rally_testcase_hierarchy_hash[this_hierarchy_id]
                child_testcase_oid = child_testcase['ObjectID']
                parent_testcase = rally_testcase_hierarchy_hash[this_parent_hierarchy_id]
                parent_testcase_oid = parent_testcase['ObjectID']

                @logger.info "Linking Child Hierarchy ID: #{this_hierarchy_id} with TestCase ObjectID: #{child_testcase_oid} to: "
                @logger.info "    Parent Hierarchy ID: #{this_parent_hierarchy_id} with TestCase ObjectID: #{parent_testcase_oid}"

                parent_web_link = {}
                parent_web_link["LinkID"] = parent_testcase_oid
                parent_web_link["DisplayString"] = "Caliber Parent TestCase"

                update_fields = {}
                update_fields[@caliber_weblink_field_name] = parent_web_link
                begin
                    @rally.update("testcase", child_testcase_oid, update_fields)
                    @logger.info "    Successfully Linked Rally TestCase: ObjectID #{child_testcase_oid}; to TestCase: #{parent_testcase_oid}"
                rescue => ex
                    @logger.error "Error occurred attempting to Link Rally TestCase: ObjectID #{child_testcase_oid}; to TestCase: #{parent_testcase_oid}"
                    @logger.error ex.message
                    @logger.error ex.backtrace
                end
            end
        end
    end

end

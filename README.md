--------------------------------------------------------------------------------

01) TechServices has been engaged to help John Deere move data from their
    Caliber system into the Rally ALM product.

    The import scripts are written in Ruby, running in a Ruby 2.1.1 environment.
    The gems are:
        $ rvm use ruby-2.1.1
        $ gem list | pr -2
        bigdecimal (1.2.4)          multipart-post (1.2.0)
        bundler (1.5.3)             nokogiri (1.6.1)
        bundler-unload (1.0.2)          psych (2.0.3)
        ClothRed (0.5.0)            rake (10.1.0)
        columnize (0.3.6)           rally_api (0.9.25)
        debugger (1.6.6)            rally_jest (1.2.5)
        debugger-linecache (1.2.0)      rallyeif-jira (4.3.3)
        debugger-ruby_core_source (1.3.2)   rallyeif-wrk (0.2.9)
        executable-hooks (1.3.1)        rdoc (4.1.0)
        faraday (0.8.8)             rubygems-bundler (1.4.2)
        gem-wrappers (1.2.4)            rvm (1.11.3.9)
        httpclient (2.3.4.1)            sanitize (2.0.6)
        io-console (0.4.2)          test-unit (2.1.1.0)
        json (1.8.1)                trollop (2.0)
        mini_portile (0.5.2)            xml-simple (1.1.2)
        minitest (4.7.5)


--------------------------------------------------------------------------------

02) The structure of the data move is as follows:
        Caliber         ==>     Rally
        ---------------         -----
        1) Requirements         1) Storys
            1a) RequireTraces       1a) Link to other Storys

        2) TestCases            2) TestCases
            2a) RequireTraces       2a) Links to other Storys
            2b) TestCaseTraces      2b) Links to other TestCases

--------------------------------------------------------------------------------

03) The nine Caliber Requirement projects to be moved:

    Project                 Datafiles (images and REQ/TC)
    ---------------         ------------------------------------------
    01) JDF_Hera            ImageCache2014.zip  ---> (lots of images)
                            heraTC_and_REQ.zip  ---> heraTC_and_REQ.xml
                                                --->    heratrace.xml
    02) JDF_DTI
    03) JDF_Harald
    04) JDF_Rimu
    05) JDF_Tcenter
    06) JDF_Tnavi
    07) JDF_ZeusControl
        (test cases and DTC’s as well, separate project or new mapping)
    08) JDF_ZeusHarvesting
    09) JDF_ZeusPC

    And a test data set:
        01) hhc.xml --- match item 01) above

--------------------------------------------------------------------------------

04) Pre-Import procedure:

    a. When run for the first time in a subscription, create a new Workspace
       and Project on your Rally server.
       Note:    If possible, change your default Workspace & Project to the
                same as you just created above... to help prevent issues when
                code is in error.

    b. Create the custom fields under the Project (as opposed to the
       Workspace where it will be seen by all Porjects) to match the
       my_vars.rb settings (see next step):
            On UserStories:
                $caliber_id_field_name (External reference) - type text
                $caliber_req_traces_field_name (CaliberID) - type string
            On TestCases:
                $caliber_id_field_name (External reference) - type text
                $caliber_tc_traces_field_name (CaliberID) - type string
                $caliber_weblink_field_name (CaliberTCParent) - type Weblink,
                    https://demo-services1.rallydev.com/#/detail/testcase/${id}

    c. In file my_vars.rb, set these variables:
        Rally connection:
            $my_base_url
            $my_username
            $my_password
            $my_workspace
            $my_project
        Caliber data files:
            $caliber_file_req
            $caliber_file_req_traces
            $caliber_file_tc
            $caliber_file_tc_traces
            $caliber_image_directory
        Custom fields created:
            User Story:
                $caliber_id_field_name
                $caliber_req_traces_field_name
            Test Case:
                $caliber_id_field_name
                $caliber_weblink_field_name
                $caliber_tc_traces_field_name
        Misc:
            $max_import_count

--------------------------------------------------------------------------------

05) Import procedure for Requirements:

    a. Edit my_vars.rb with:
        $description_field_hash:
            Project-specific field mapping (in PPT slides for JDF_Hera...
            others to come... hopefully).

       For example:
            $description_field_hash = {
                'Caliber Purpose'         => 'caliber_purpose',
                'Pre-condition'           => 'pre_condition',
                'Basic course'            => 'basic_course',
                'Post-condition'          => 'post_condition',
                'Exceptions'              => 'exceptions',
                'Remarks'                 => 'remarks',
                'Description'             => 'description'
                'Validation'              => 'validation',
                'Input'                   => 'input',
                'Output'                  => 'output'
                 }

    b. Run s1-requirements.rb against the data files (defined in my_vars.rb)
       to import the Caliber-Requirements to Rally-UserStorys.

    c. Run s2-requirements_traces.rb against the data files (defined in
       my_vars.rb) to import Caliber-RequirementTraces into the Rally
       custom field "External reference" (rich-text) on Rally Storys that
       were created in the previous step "04)" above. This custom field
       will be populated with hyperlinks to other Rally Storys imported in
       the previous step "b." above.

--------------------------------------------------------------------------------

06) Import procedure for TestCases:

    a. Populate $description_field_hash in my_vars.rb with
       project-specific field mapping.

       For example, $description_field_hash for jdf_zeus_harvesting during
       proof-of-concept was:
            $description_field_hash = {
                'Source [So]'             => 'source',
                'Purpose [Pu]'            => 'purpose',
                'Pre-condition [Pr]'      => 'pre_condition',
                'Testing Course [Te]'     => 'testing_course',
                'Post-condition [Po]'     => 'post_condition',
                'Remarks [Re]'            => 'remarks',
                'Validation'              => 'validation',
                'Description'             => 'description'
                }

    b. Run s3-testcases.rb against the data files (defined in my_vars.rb)
       to import the Caliber-TestCases to Rally-TestCases.

    c. Run s4-testcase_traces.rb against the data files (defined in
       my_vars.rb) to import Caliber-TestCaseTraces into the Rally custom
       field "External reference" (rich-text) on Rally TestCases that were
       created in the previous step "05)" above. This custom field will
       be populated with hyperlinks to other Rally-UserStorys imported in
       step "05)b." (above) and Rally-TestCases created in step "b." (above).

--------------------------------------------------------------------------------
[the end]

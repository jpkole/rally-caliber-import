# Rally Connection parameters

# --------------------------------------------------------------------------
# My test environment.
#
$my_base_url                    = "https://demo-services1.rallydev.com/slm"
$my_username                    = "jpkole@rallydev.com"
$my_password                    = "!!nrlad1804"
$my_wsapi_version               = "1.43"
$my_workspace                   = "JDF Tampere"

# --------------------------------------------------------------------------
# The real deal...
#
#$my_base_url                    = "https://rally1.rallydev.com/slm"
#$my_username                    = "rally_caliber@johndeere.com"
#$my_password                    = "!!nrlad1804"
#$my_wsapi_version               = "1.43"
#$my_workspace                   = "JDF Tampere"

# ------------------------------------------------------------------------------
# JDF_zeuscontrol project (proof of concept)
#
#$my_project                     = ""                                                                # Rally Project name
#$caliber_file_req               = "../from-marks-dropbox/hhc.xml"                                   # 01-Requirements
#$caliber_file_req_traces        = "../from-marks-dropbox/hhc_traces.xml"                            # 02-Requirement-Traces
#$caliber_file_tc                = "../from-marks-dropbox/jdf_testcase_zeuscontrol.xml"              # 03-Testcases
#$caliber_file_tc_traces         = "../from-marks-dropbox/jdf_testcase_traces_zeuscontrol.xml"       # 04-Testcases-Traces
#$caliber_image_directory        = "../from-marks-dropbox/images"                                    # 05-Image data

# ------------------------------------------------------------------------------
# Proj1: Hera project
#
#$my_project                     = ""                                                                # Rally Project name
#$caliber_file_req               = "../from-ftp-site/fetch1/heraTC_and_REQ/heraTC_and_REQ.xml"       # 01-Requirements
#$caliber_file_req_traces        = "../from-ftp-site/fetch1/heraTC_and_REQ/heratrace.xml"            # 02-Requirement-Traces
#$caliber_file_tc                = "../from-ftp-site/fetch1/heraTC_and_REQ/heraTC_and_REQ.xml"       # 03-Testcases
#$caliber_file_tc_traces         = "../from-ftp-site/fetch1/heraTC_and_REQ/heratrace.xml"            # 04-Testcases-Traces
#$caliber_image_directory        = "../from-ftp-site/fetch1/ImageCache"                              # 05-Image data

# ------------------------------------------------------------------------------
# Proj2: Tnavi project
#
#$my_project                     = "TNavi_requirements"                                              # Rally Project name
#$caliber_file_req               = "../from-ftp-site/fetch2-TNvai/tnavi2014.xml"                     # 01-Requirements
#$caliber_file_req_traces        = "../from-ftp-site/fetch2-TNvai/TNavitrace.xml"                    # 02-Requirement-Traces
#$caliber_file_tc                = ""                                                                # 03-Testcases
#$caliber_file_tc_traces         = ""                                                                # 04-Testcases-Traces
#$caliber_image_directory        = "../from-ftp-site/fetch2-TNvai/ImageCache"                        # 05-Image data

# ------------------------------------------------------------------------------
# Proj3: TimberOffice project
#
#$my_project                     = "TimberOffice_requirements"                                       # Rally Project name
#$caliber_file_req               = "../from-ftp-site/fetch3-TimberOffice/Toffice_toRally.xml"        # 01-Requirements
#$caliber_file_req_traces        = "../from-ftp-site/fetch3-TimberOffice/JDF_tofficetrace2.xml"      # 02-Requirement-Traces
#$caliber_file_tc                = ""                                                                # 03-Testcases
#$caliber_file_tc_traces         = ""                                                                # 04-Testcases-Traces
#$caliber_image_directory        = "../from-ftp-site/fetch3-TimberOffice/ImageCache"                 # 05-Image data

# ------------------------------------------------------------------------------
# Proj4: HHC Harvest project
#
$my_project                     = "HHC_requirements"                                                # Rally Project name
$caliber_file_req               = "../from-ftp-site/fetch4-HHC_Harvest/HHC_to_rally.xml"            # 01-Requirements
$caliber_file_req_traces        = "../from-ftp-site/fetch4-HHC_Harvest/HHC_traces.xml"              # 02-Requirement-Traces
$caliber_file_tc                = ""                                                                # 03-Testcases
$caliber_file_tc_traces         = ""                                                                # 04-Testcases-Traces
$caliber_image_directory        = "../from-ftp-site/fetch3-TimberOffice/ImageCache"                 # 05-Image data

# ------------------------------------------------------------------------------
# Proj5: DTI project (runtimes: s1=16 minutes, s2=1.8 minute, s3=7.7 minutes, s4-1.5 minutes)
#
#$my_project                     = "DTI_requirements"                                                # Rally Project name
#$caliber_file_req               = "../from-ftp-site/fetch5-DTI/JDF_DTI_reqs_without_trash.xml"      # 01-Requirements
#$caliber_file_req_traces        = "../from-ftp-site/fetch5-DTI/JDF_DTItracereq.xml"                 # 02-Requirement-Traces
#$caliber_file_tc                = "../from-ftp-site/fetch5-DTI/JDF_DTI_TC_without_trash.xml"        # 03-Testcases
#$caliber_file_tc_traces         = "../from-ftp-site/fetch5-DTI/JDF_DTItraceTC.xml"                  # 04-Testcases-Traces
#$caliber_image_directory        = "../from-ftp-site/fetch3-TimberOffice/ImageCache"                 # 05-Image data

# ------------------------------------------------------------------------------
# Proj6: Rimu project (runtimes: s1=40 minutes, s2=1 minute)
#
#$my_project                     = "RIMU_requirements"                                               # Rally Project name
#$caliber_file_req               = "../from-ftp-site/fetch6-Rimu_Reqs_and_Traces/rimu.xml"           # 01-Requirements
#$caliber_file_req_traces        = "../from-ftp-site/fetch6-Rimu_Reqs_and_Traces/JDF_rimutraces.xml" # 02-Requirement-Traces
#$caliber_file_tc                = ""                                                                # 03-Testcases
#$caliber_file_tc_traces         = ""                                                                # 04-Testcases-Traces
#$caliber_image_directory        = "../from-ftp-site/fetch3-TimberOffice/ImageCache"                 # 05-Image data (Same as TOffice)

# ------------------------------------------------------------------------------
# Proj7: Timbermatic / Zeus project (runtimes: s1=1.7 hours, s2=13.6 minutes)
#
#$my_project                     = "Timbermatic_requirements"                                        # Rally Project name
#$caliber_file_req               = "../from-ftp-site/fetch7-Timbermatic/JDF_zeusPC.xml"              # 01-Requirements
#$caliber_file_req_traces        = "../from-ftp-site/fetch7-Timbermatic/Zeus_PC_traces.xml"          # 02-Requirement-Traces
#$caliber_file_tc                = ""                                                                # 03-Testcases
#$caliber_file_tc_traces         = ""                                                                # 04-Testcases-Traces
#$caliber_image_directory        = "../from-ftp-site/fetch7-Timbermatic/ImageCache"                  # 05-Image data

# ------------------------------------------------------------------------------
# Proj8: Carrier project.
#   Elapsed time (minutes): demo-services1: s1=95, s2=25, s3=76, s4=23, tot=220
#                           rally1:         s1=55, s2=10, s3=31, s4=9, tot=105
#$my_project                     = "Carrier_requirements"                                            # Rally Project name
#$caliber_file_req               = "../from-ftp-site/fetch8-Carrier/carrier_req.xml"                 # 01-Requirements
#$caliber_file_req_traces        = "../from-ftp-site/fetch8-Carrier/carrier_req_traces.xml"          # 02-Requirement-Traces
#$caliber_file_tc                = "../from-ftp-site/fetch8-Carrier/carrier_tc.xml"                  # 03-Testcases
#$caliber_file_tc_traces         = "../from-ftp-site/fetch8-Carrier/carrier_TC_traces.xml"           # 04-Testcases-Traces
#$caliber_image_directory        = "../from-ftp-site/fetch7-Timbermatic/ImageCache"                  # 05-Image data


# ------------------------------------------------------------------------------
# Custom fields in Rally:
#
$caliber_id_field_name          = "CaliberID"           # US - type String
$caliber_req_traces_field_name  = "Externalreference"   # US - type Text

$caliber_id_field_name          = "CaliberID"           # TC - type String
$caliber_weblink_field_name     = "CaliberTCParent"     # TC - type Weblink
$caliber_tc_traces_field_name   = "Externalreference"   # TC - type Text


# ------------------------------------------------------------------------------
# Runtime preferences
#
$max_attachment_length          = 5_242_880 # 5mb - https://help.rallydev.com/creating-user-story
$max_description_length         = 32_768    # fail
$max_description_length         = 31_310    # This apparently needs to be lower than the published 32,768...
                                            # maybe nokigiri adds more?
                                            # maybe try 31310 for Toffice (above)
$max_import_count               = 50_000

$html_mode                      = true      #
$preview_mode                   = false     #


# ------------------------------------------------------------------------------
# CSV USERSTORY:
# CSV file & fields for lookup of Story OID by Caliber Requirement Name (needed for traces import).
$csv_requirements                  = "s1-requirements.csv"
#                                           -------1-------     -------2-------     -------3-------     -------4-------     -------5-------
$csv_requirement_fields            = %w{    project             hierarchy           id                  tag                 name
                                            description         caliber_purpose     pre_condition       basic_course        post_condition
                                            exceptions          input               output              remarks             open_issues     }
#                                           -------1-------     -------2-------     -------3-------     -------4-------     -------5-------
$csv_US_OidCidReqname_by_FID        = "s1-US_OidCidReqname_by_FID.csv"
#                                           -------1-------     -------2-------     -------3-------     -------4-------     -------5-------
$csv_US_OidCidReqname_by_FID_fields = %w{   FmtID               OID                 id                  tag                 REQname         }
#                                           -------1-------     -------2-------     -------3-------     -------4-------     -------5-------


# ------------------------------------------------------------------------------
# CSV TESTCASE:
# CSV file & fields for lookup of Testcase OID by Caliber Requirement Name (needed for traces import).
$csv_testcases                      = "s3-testcases.csv"
#                                           -------1-------     -------2-------     -------3-------     -------4-------     -------5-------
$csv_testcase_fields                = %w{   project             hierarchy           id                  tag                 name
                                            description         validation          purpose             pre_condition       testing_course
                                            post_condition      remarks             machine_type                                            }
#                                           -------1-------     -------2-------     -------3-------     -------4-------     -------5-------
$csv_TC_OidCidReqname_by_FID        = "s3-TC_OidCidReqname_by_FID.csv"
#                                           -------1-------     -------2-------     -------3-------     -------4-------     -------5-------
$csv_TC_OidCidReqname_by_FID_fields = %w{   FmtID               OID                 id                  tag             TCname              }
#                                           -------1-------     -------2-------     -------3-------     -------4-------     -------5-------


# ------------------------------------------------------------------------------
# Log files
$cal2ral_req_log                = "s1-requirements.log"
$cal2ral_req_traces_log         = "s2-requirement_traces.log"
$cal2ral_tc_log                 = "s3-testcases.log"
$cal2ral_tc_traces_log          = "s4-testcase_traces.log"

#the end#

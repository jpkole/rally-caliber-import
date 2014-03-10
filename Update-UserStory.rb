#!/usr/bin/env ruby
# ------------------------------------------------------------------------------
# SCRIPT:
#       Update-UserStory.rb
#
# PURPOSE:
#       Used to modify some desired fields of the Rally User Story given on the
#	command line.
#
# USAGE:
#       ./Update-UserStory.rb  <options>
# add real docs here....
#
# ERROR EXITS:
#	-1 = No FormattedID specified on command line.
#	-2 = No Description field specified on command line.
#	-3 = A query to Rally for the FormattedID returned nothing.
#	-4 = A query for the specific FormattedID returned more than 1.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Define our constants / variables.
#
require "rally_api"
require "trollop"
require "base64"
require "debugger"

util_name       = "Update-UserStory.rb"
$my_base_url	= "https://audemo.rallydev.com/slm"
$my_username	= "jpkole@rallydev.com"
$my_password	= "!!nrlad1804"
$my_workspace	= "JPKole-Testing"
$my_project	= "JDF-Tnavi-1"


# ------------------------------------------------------------------------------
# Displays some brief information about a user story.
def display_us(str,mystory)
	print "#{str} User Story (hierarichalrequirement):\n"
	print "    FormattedID: #{mystory[:FormattedID]}\n"
	print "       ObjectID: #{mystory[:ObjectID]}\n"
	print "       (length): #{mystory[:Description].length} (Description field)\n"
	if mystory[:Description].length < 1 then
		desc = "<the 'Description' field is empty>"
	else
		desc = mystory[:Description]
	end
	encoded_desc = Base64.encode64(desc)
	print "    Description: (base64 encoded)\n"
	print "#{encoded_desc}"
	print "\n"
	print "    Description: #{desc}\n\n"
end


# ------------------------------------------------------------------------------
# Process the command line args.
#
opts = Trollop::options do
    opt :FormattedID, "The FormattedID of the UserStory to be modified",   :short => 'f', :type => String
    opt :Description, "The file containing new 'Description' field text",  :short => 'd', :type => String
end

if !opts[:FormattedID_given] then
    print "ERROR: Command line option '--FormattedID <id>' (or '-f') required.\n"
    exit (-1)
end

if !opts[:Description_given] then
    print "ERROR: Command line option '--Description <text>' (or '-d') required.\n"
    exit (-2)
end


# ------------------------------------------------------------------------------
# Connect to Rally and find the data.
#
print "Connecting to Rally @ <#{$my_base_url}> as user '#{$my_username}'...\n"
@rallycon = RallyAPI::RallyRestJson.new({
		:base_url       => $my_base_url,
		:username       => $my_username,
		:password       => $my_password,
		:workspace      => $my_workspace,
		:project        => $my_project,
		:version        => "v2.0",
		:headers        => RallyAPI::CustomHttpHeader.new(:name=>"#{util_name}", :vendor=>"JPcode", :version=>"3.14159")
		})

# Fields to query for (code removes all spaces for you)...
ftqf = "Name, FormattedID, ObjectID, Description".delete(' ')

print "Query Rally for User Story (hierarichalrequirement) with FormattedID=#{opts[:FormattedID]}...\n"
all_us = @rallycon.find(RallyAPI::RallyQuery.new(
		:type		=> :hierarchicalrequirement,
		:query_string	=> "(FormattedID = \"#{opts[:FormattedID]}\")",
		:fetch		=> ftqf))


# ------------------------------------------------------------------------------
# Verify we got back the kind of data we expected.
#
if all_us.count < 1 then	# Did we find too few?
    print "ERROR: Query returned nothing (ForamttedID does not exist?).\n"
    exit (-3)
end

if all_us.count > 1 then	# Did we find too many?
    print "ERROR: Query returned more than one (#{all_us.count} to be exact).\n"
    exit (-4)
end

us = all_us.first		# Take the first one (even though there is only one)


# ------------------------------------------------------------------------------
# Show user what we obtained.
#
display_us("Found", us)


# ------------------------------------------------------------------------------
# Update the Description field from either command-line text or filename.
#
update_fields = {}
if opts[:Description][0..2] == "pn:" then
    update_fields[:Description] = File.read(opts[:Description][3..-1])
else
    update_fields[:Description] = opts[:Description]
end
new_us = @rallycon.update("hierarchicalrequirement", us[:ObjectID], update_fields)

# ------------------------------------------------------------------------------
# Show user the updated UserStory.
#
display_us("Updated", new_us)


#[the end]#

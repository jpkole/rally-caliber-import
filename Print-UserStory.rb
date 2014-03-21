#!/usr/bin/env ruby
# ------------------------------------------------------------------------------
# SCRIPT:
#       Print-UserStory.rb
#
# PURPOSE:
#       Display some desired fields of the Rally User Story given on the
#	command line.
#
# USAGE:
#       ./Print-UserStory.rb  <Rally-UserStory-FormattedID>
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Define our constants / variables.
#
util_name       = "Print-UserStory.rb"
$my_base_url	= "https://demo-services1.rallydev.com/slm"
$my_username	= "jpkole@rallydev.com"
$my_password	= "!!nrlad1804"
$my_workspace	= "JDF Tampere"
$my_project	= "Toffice"

require "rally_api"
require "debugger"

if ARGV[0].nil? then
	print "USAGE: #{$0} <FormattedID of an existing User Story>\n"
	exit
else
	my_us=ARGV[0]
end

class Regexp
	def each_match(str)
		start = 0
		while matchdata = self.match(str, start)
			yield matchdata
			start = matchdata.end(0)
		end
	end
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
		:headers        => RallyAPI::CustomHttpHeader.new(:name=>"Print-UserStory.rb", :vendor=>"JP code", :version=>"3.14159")
		})

# Fields to query for (code removes all spaces for you)...
ftqf = "Name, FormattedID, ObjectID, CreationDate, LastUpdateDate, DirectChildrenCount, HasParent, Description, CaliberID, Externalreference".delete(' ')

print "Query Rally for User Story (hierarichalrequirement) #{my_us}...\n"
all_us = @rallycon.find(RallyAPI::RallyQuery.new(
		:type		=> :hierarchicalrequirement,
		:query_string	=> "(FormattedID = \"#{my_us}\")",
		:fetch		=> ftqf))


# ------------------------------------------------------------------------------
# Verify we got back the kind of data we expected.
#
if all_us.count < 1 then	# Did we find too few?
    print "ERROR: Query returned nothing.\n"
    exit (-1)
end

if all_us.count > 1 then	# Did we find too many?
    print "ERROR: Query returned more than one (#{all_us.count} to be exact).\n"
    exit (-1)
end

us = all_us.first		# Take the first one (even though there is only one)


# ------------------------------------------------------------------------------
# Prepare pretty printing field labels by finding the longest field name.
#
fields = ftqf.split(",")
lfn = fields.group_by(&:size).max[0]


# ------------------------------------------------------------------------------
# Pretty print all fields that don't need special formatting.
#
print "Found User Story (hierarichalrequirement):\n"
fn = 1
fields.each_with_index do | this_Field, this_Index |
	#next if this_Field == "Description"
	next if this_Field == "Externalreference"
	print "    %5s"%[fn]			# Relative field number
	print "  %-#{lfn}s :"%[this_Field]	# Field name
	print " %s\n"%[us[this_Field.to_sym]]	# Field value
	fn += 1
end


# ------------------------------------------------------------------------------
# Print the Description field by breaking it into pieces along <p><b> tags.
#
pa = Array.new
/<p><b>/.each_match(us[:Description] + "<p><b>") {|m| pa << m.begin(0)}

print "       %2s  Description         :\n"%[fn]
s1=0
pa.each_with_index do |s1,ndx|
	break if ndx+1 == pa.length
	s2 = pa[ndx+1]-1
	print "                               : <br/>%s<br/>\n"%[us[:Description][s1..s2]]
end
fn += 1


# ------------------------------------------------------------------------------
# Print the Externalreference custom field by breaking it into pieces at <br/>.
#
print "       %2s  Externalreference   :\n"%[fn]
a=us[:Externalreference].split("<br/>")
a.each_with_index do |this_Piece, this_Index |
	print "                               : %s<br/>\n"%[this_Piece]

end
fn += 1

#[the end]#

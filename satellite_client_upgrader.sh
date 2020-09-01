############################################################################################################################
# Purpose:                                                                                                                 #
#                                                                                                                          #
#        Automate Content-View changes after patching Satellite                                                            #
#                                                                                                                          #
# Usage:                                                                                                                   #
#                                                                                                                          #
#        Run on your Satellite host as root or a user with hammer configured. You may need to update the "org_id" variable #
#        This script will obtain the Satellite and Foreman version from rpms on the system. It will then ensure that the   #
#        corresponding Tools repository is added to each content-view which is not a Puppet content-view. It will          #
#        indiscriminately remove the previous Satellite Tools or Foreman Tools repository from the content-view,           #
#        regardless of the version.                                                                                        #
#                                                                                                                          #
# Disclaimer:                                                                                                              #
#                                                                                                                          #
#        If you turn on async processing, it may break the Foreman Proxy and require a restart of services. This may also  #
#        lead to stuck tasks which require flushing if you turn async processing back on. It may sporadically promote      #
#        through some lifecycles but not others. If symptoms persist, see your doctor or healthcare professional.          #
#
#        Even without async on it may break                                                                                #
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
# NOTE: DOES NOT SYNC THE REPOSITORIES FOR YOU OR ADD THEM. MANUALLY ADD THE REPOSITORIES FOR THE TOOLS /  CLIENT PACKAGES #
#       OF THE NEW SATELLITE VERSION. NOT DOING SO WILL BREAK THIS SCRIPT                                                  #                       
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
############################################################################################################################
#                                                                                                                          #
# Prerequisites:                                                                                                           #
#                                                                                                                          #
#     1. Add the latest Satellite Tools and Foreman Clients repositories. These should be given the following naming       #
#                format "(Satellite Tools | Foreman Client) major_version.minor_version (RHEL|EL) os_version architecture" #
#                eg: "Satellite Tools 6.7 RHEL 7 x86_64"; "Foreman Client 1.24 EL7 x86_64"; Foreman Client 1.24 EL5 x86_64"#
#        This script does not facilitate more that one architecture as it assumes everything is 64 bit                     #
#                                                                                                                          #
#     2. Consistent Naming conventions for Content Views:                                                                  #
#             a) Views for Puppet specify  somewhere in their title "puppet", case insensitive, and "puppet" is not used   #
#                in a non-puppet content-view.                                                                             #
#                eg: "RHEL 7 Puppet View"; "CentOS 8 view PuPpeT"                                                          #                                 
#             b) Content-views follow a naming convention which has the distribution as the 1st word and the first digit   #
#                is the major version of the OS. Valid names would include:                                                #
#                "RHEL 7 7 Server Content-View" ; "RHEL 7 Terradata Content-View" ; "Oracle Linux 7 Content-View" ;        #
#                 "CentOS SAP 7.5 Servers"; "Fedora M'Lady 6.9 Servers"                                                    #
#             c) Non-RHEL hosts are "CentOs", "Fedora" or "Oracle" and contain these keywords as their first argument      #
#                                                                                                                          #
#     3. As indicated by the big warning above you have likely ignored, satisfy condition 1                                # #                                                                                                                          #     #                                                                                                                          #
############################################################################################################################
#  Potential improvements:                                                                                                 #
#                                                                                                                          #                                                                                               
#      - The  matching logic could be easily tweaked to not to require the distribution as first argument. This has not    #
#        been added as it would be untested                                                                                #
#      - Error handling to ensure that if you've ticked that you're using CentOS 5,7; Oracle 6; RHEL 8 (as an example), it #
#        will exit if it can't find those repositories instead of erroring out                                             #
#      - Validation that the content-view ID is a number                                                                   #
#      - Turn async back on for promoting content-views if you like seeing Satellite cry or it is able to keep up with     #
#        the task load                                                                                                     #
#      - Investigate telling awk to not use buffers                                                                        #            
#      - Store hammer output rather than querying multiple times                                                           #
#                                                                                                                          #                                                                                   
############################################################################################################################


#### VARIABLES ####
#~~User variables~~#
# The organisation ID for which to update content-views. Discover this with `hammer organization-list`
org_id="1"


#~~Commands~~#
add_repo="hammer content-view add-repository --organization-id='${org_id}'"
del_repo="hammer content-view remove-repository --organization-id='${org_id}'"
pub_repo="hammer content-view publish --organization-id='${org_id}'"

#~~Version variables~~#
satellite_version=$(rpm -q satellite | grep -o -e '-[0-9].[0-9]' | cut -d '-' -f 2)
foreman_version=$(rpm -q foreman | grep -o -e '[0-9].[0-9][0-9]' | head -1)

#Package versions need space
satellite_package=" $satellite_version "
foreman_package=" $foreman_version "

#~~Repo IDs for the tools needed for each OS version~~#

# RHEL/Satellite repo IDs
rhel5=$(hammer repository list | awk -F "|" -v satver="$satellite_package" '$0 ~ satver {puppies=$0}{if (puppies ~ /RHEL 5/ && puppies ~ /Satellite Tools/){print $1}}')
rhel6=$(hammer repository list | awk -F "|" -v satver="$satellite_package" '$0 ~ satver {puppies=$0}{if (puppies ~ /RHEL 6/ && puppies ~ /Satellite Tools/){print $1}}')
rhel7=$(hammer repository list | awk -F "|" -v satver="$satellite_version" '$0 ~ satver {puppies=$0}{if (puppies ~ /RHEL 7/ && puppies ~ /Satellite Tools/){print $1}}')
rhel8=$(hammer repository list | awk -F "|" -v satver="$satellite_version" '$0 ~ satver {puppies=$0}{if (puppies ~ /RHEL 8/ && puppies ~ /Satellite Tools/){print $1}}')
rhel9=$(hammer repository list | awk -F "|" -v satver="$satellite_version" '$0 ~ satver {puppies=$0}{if (puppies ~ /RHEL 9/ && puppies ~ /Satellite Tools/){print $1}}')

# Non-RHEL/Foreman Client repo IDs
foreman5=$(hammer repository list | awk -F "|" -v satver="foreman_package" '$0 ~ satver {puppies=$0}{if (puppies ~ /EL5/ && puppies ~ /Foreman Client/){print $1}}')
foreman6=$(hammer repository list | awk -F "|" -v satver="foreman_package" '$0 ~ satver {puppies=$0}{if (puppies ~ /EL6/ && puppies ~ /Foreman Client/){print $1}}')
foreman7=$(hammer repository list | awk -F "|" -v satver="foreman_package" '$0 ~ satver {puppies=$0}{if (puppies ~ /EL7/ && puppies ~ /Foreman Client/){print $1}}')
foreman8=$(hammer repository list | awk -F "|" -v satver="foreman_package" '$0 ~ satver {puppies=$0}{if (puppies ~ /EL8/ && puppies ~ /Foreman Client/){print $1}}')
foreman9=$(hammer repository list | awk -F "|" -v satver="foreman_package" '$0 ~ satver {puppies=$0}{if (puppies ~ /EL9/ && puppies ~ /Foreman Client/){print $1}}')



##### FUNCTIONS ####
#~~Obtain Content-View Lists~~#

# Associative arrays were originally stored in a file for retrieval, the original awk is retained for future purposes. 
# This pulls all Red Hat content-views via hammer. Awk matches case insensitively for rhel/red to find Red Hat views, 
# without matching puppet-specific views. It then also ensures that the first column is a number - ie it is 
# a content view id. It maps the values to an associative array and outputs this in an easily seddable or otherwise array-like output. There
# is some double handling, but the idea is that sed can be removed if the hash array format is wanted. Sed ensures that the output is consistently
# in the format: (RHEL|FOREMAN)[major version] = id; eg RHEL7 = 21 ; FOREMAN6 = 26. It's backwards. That's ok.

# Kept as two seperate functions as I wanted consistency and to not have to brain that tiny bit extra to make another sed to map RHEL -> RHEL
# everything else -> FOREMAN. Of course there could just be another sed for this now, but it is working as-is.


rhel_hammertime(){
hammer content-view list | awk -F '|' 'tolower($0) !~ /puppet/ && tolower($0) ~ /(red|rhel)/{if ($1 ~ /[0-9]/);map[$1]=$2}END{for (key in map){printf "%s => %s\n",map[key],key'}} | sed '{ s/\(rhel\|red\)\([0-9]\|.[0-9]\).*\(> [0-9].*\)/RHEL\2\3/i; s/\([a-z]\|[A-Z]\)\s\([0-9]\)/\1\2/i; s/>/ =/;t;d }' | sort ;
}

nonrhel_hammertime(){
# Non-rhel client content-views which require Katello agent. As above except less tested. FOREMAN in place of RHEL as a blanket OS for all non-RHEL systems as they get the Foreman Tools.
hammer content-view list | awk -F '|' 'tolower($0) !~ /puppet/ && tolower($0) ~ /(cent|oracle|fedora)/{if ($1 ~ /[0-9]/);map[$1]=$2}END{for (key in map){printf "%s => %s\n",map[key],key'}} | sed '{ s/\(cent.*\|oracle.*\|fedora.*\)\([0-9]\)\(.*\)\(> [0-9].*\)/FOREMAN\2\4/i; s/>/ =/;t;d }' | sort ;
}



#### MAIN #### 

# Version switching logic

rhel_hammertime |
    while IFS= read -r line; do 
        content_view_id=$(echo $line | awk '{print $3}')
        # The first match for Foreman Client or Satellite tools is likely the oldest. In any case, store in variable to be removed
        old_repo=$(hammer content-view info --id="${content_view_id}" | grep -B1 -m 1 'Foreman Client\|Satellite Tools' | awk '/ID/{print $3}')
        [[ ! -z old_repo ]] && $del_repo --repository-id="${old_repo}" --id="${content_view_id}"

        case $line in 
            *RHEL5*)
            $add_repo --repository-id="${rhel5}" --id="${content_view_id}"
            ;;
            *RHEL6*)
            $add_repo --repository-id="${rhel6}" --id="${content_view_id}"
            ;;
            *RHEL7*) 
            $add_repo --repository-id="${rhel7}" --id="${content_view_id}"
            ;; 
            *RHEL8*)
            $add_repo --repository-id="${rhel8}" --id="${content_view_id}"
            ;;
            # Unecessary future-proofing. Hopefully Sat can do this by then
            *RHEL9*)
            $add_repo --repository-id="${rhel9}" --id="${content_view_id}"
            ;;
           *)
            echo "$line is invalid and the content-view $content_view_id has not been updated"
            continue
            ;;
        esac 
        $pub_repo --id="${content_view_id}"
        latest_vers=$(hammer  content-view version list --content-view-id="${content_view_id}"   --organization-id="${org_id}" |awk -F "|" '/[0-9]/{gsub(" ","");print $3}'|sort -nr | head -1)
        
        for lifecycle in $(hammer lifecycle-environment list | awk -F "|" '{if ($1 ~ /[0-9]/){gsub(" ","");print $2}}'); do
		# Commented out async as it was causing issues due to Satellite being unable to handle simultaneous requests well. Commented out redirects to log stdout for troubleshooting.
            hammer content-view version promote --version="$latest_vers"  --organization-id="$org_id" --content-view-id="${content_view_id}" --to-lifecycle-environment="$lifecycle" --force #--async  > /dev/null 2>&1
        done 
   done           

nonrhel_hammertime |
    while IFS= read -r line; do
        content_view_id=$(echo $line | awk '{print $3}')
        # The first match for Foreman Client or Satellite tools is likely the oldest. In any case, store in variable to be removed
        old_repo=$(hammer content-view info --id="${content_view_id}" | grep -B1 -m 1 'Foreman Client\|Satellite Tools' | awk '/ID/{print $3}')
        [[ ! -z old_repo ]] && $del_repo --repository-id="${old_repo}" --id="${content_view_id}"

        case $line in
            *FOREMAN5*)
            $add_repo --repository-id="${foreman5}" --id="${content_view_id}"
            ;;
            *FOREMAN6*)
            $add_repo --repository-id="${foreman6}" --id="${content_view_id}"
            ;;
            *FOREMAN7*)
            $add_repo --repository-id="${foreman7}" --id="${content_view_id}"
            ;;
            *FOREMAN8*)
            $add_repo --repository-id="${foreman8}" --id="${content_view_id}"
            ;;
            # Unecessary future-proofing. Hopefully Sat can do this by then
            *FOREMAN9*)
            $add_repo --repository-id="${foreman9}" --id="${content_view_id}"
            ;;
            *)
            echo "$line is invalid and the content-view $content_view_id has not been updated"
            continue
            ;;
        esac
        $pub_repo --id="${content_view_id}"
        latest_vers=$(hammer  content-view version list --content-view-id="${content_view_id}"   --organization-id="${org_id}" |awk -F "|" '/[0-9]/{gsub(" ","");print $3}'|sort -nr | head -1)
        
        for lifecycle in $(hammer lifecycle-environment list | awk -F "|" '{if ($1 ~ /[0-9]/){gsub(" ","");print $2}}'); do
		# Commented out async as it was causing issues due to Satellite being unable to handle simultaneous requests well. Commented out redirects to log stdout for troubleshooting.
            hammer content-view version promote --version="$latest_vers"  --organization-id="$org_id" --content-view-id="${content_view_id}" --to-lifecycle-environment="$lifecycle" --force #--async  > /dev/null 2>&1
        done
    done

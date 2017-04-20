#!/bin/bash
# (c) GNU GPL v3.0, 2013-2014 Andreas Tusche <daily-todo.txt@andreas-tusche.de>
#
# todo.txt sorted once a day puts most important tasks to the top
#
# 2013-04-04 AnTu initial release
# 2013-04-12 AnTu added extensions: STICKY, DUEDATE, PERIODIC, ID, WAITINGFOR, DEPEND
# 2013-04-16 AnTu new sorting function virtualSort()
# 2013-04-17 AnTu reschedule finished but periodic tasks
# 2013-04-25 AnTu additional output categorised by context or project
# 2013-04-25 AnTu additional graphviz output
# 2013-05-06 AnTu multiple file support, added extension: DELEGATED
# 2013-05-14 AnTu removal of dependencies on just done tasks
# 2013-05-24 AnTu new today:, tomorrow:, thisweek: and nextweek: DUEDATEs
# 2013-06-28 AnTu added import of MS Outlook tasks from outlook.csv file
# 2013-08-06 AnTu resolved confusion between done-date and create-date
# 2013-11-08 AnTu print statistics of tasks to do per year and day
# 2014-07-25 AnTu fixed bug when input lines contained valid printf arguments
# 2014-09-04 AnTu optionally check for graphviz availability

#==============================================================================
# config

# workdir
cd .

# files (must be the same number of files for each type!, It's not checked)
# e.g.
# FILE_TODO=("private.todo.txt",   "work.todo.txt")
# FILE_DONE=("private.done.txt",   "work.done.txt")
# FILE_RPRT=("private.report.txt", "work.report.txt")
FILE_TODO=("todo.txt")
FILE_DONE=("done.txt")
FILE_RPRT=("report.txt")

# define order of fields
n=0
STICKY=$((++n))         # ^            # do not change order (sticky extension)
DONE=$((++n))           # x            # do not change order, part of todo.txt syntax
DONEDATE=$((++n))       # yyyy-mm-dd   # do not change order, part of todo.txt syntax
PRIORITY=$((++n))       # (.)          # do not change order, part of todo.txt syntax
CREATEDATE=$((++n))     # yyyy-mm-dd   # do not change order, part of todo.txt syntax
NOTBEFORE=$((++n))      # @yyyy-mm-dd
DUEDATE=$((++n))        # !yyyy-mm-dd
PERIODIC=$((++n))       # ...:
TASK=$((++n))           # ... ... ... 
PROJECT=$((++n))        # +...
CONTEXT=$((++n))        # @...
DELEGATED=$((++n))      # !...
ID=$((++n))             # #...
WAITINGFOR=$((++n))     # @!...
DEPEND=$((++n))         # @!#...
DURATION=$((++n))       # =...

CNT_FIELDS=$n           # total number of fields

# OPTIONS
optHaveCreateDate=1                    # add (1), keep (0) or remove (-1) a task creation date (default:1)
optHaveCreateDateForPeriodicTasks=-1   # add (1), keep (0) or remove (-1) the task creation date for periodic events (default:-1)
optHaveTodaysTasksFirst=1              # sort today's tasks to the top (1) or keep then chronological (0) (suggest:1)
optAddSeparator=1                      # add a line of "-" (or $optSeparator) between search results and the rest (default:1)
optExportCSV=0                         # additionally save todo.txt and done.txt files as csv (default:0)
optSeparator="-"                       # the separator character to be used between search results and the rest (default:"-")
optSeparatorLength=80                  # the length of a line for the separator (default:80)
optDependenciesGraph=0                 # generate a graphviz file of the dependencies (default:0)
optPrintSearchResults=1                # output search results also to stdout (default:1)
optPrintStatistics=1                   # print statistics about tasks per year or day to stdout (default:0)
optListByContext=0                     # output the list grouped by context, can be set by command line option "-c" (default:0)
optListByProject=0                     # output the list grouped by project, can be set by command line option "-p" (default:0)
optShortDuration=15                    # minutes that a short task may take to be displayed more to the top (suggest:15)
optSortTags=0                          # activate tag sorting of CONTEXT, DEPEND, PROJECT and WAITINGFOR tags, can be set by command line option "-s" (default:0)

# other
today=$(date +"%Y-%m-%d")              # today

# check for executables --dot--
if [[ $optDependenciesGraph > 0 ]]; then
	CMD_GAWK=$( which dot )
	if [[ $? > 0 ]]; then
		case ${BASH_VERSINFO[5]} in
			x86_64-apple-darwin14) CMD_GAWK='/usr/local/bin/dot' ;;
			mobaxterm)             CMD_DOT='/drives/c/My\ Program\ Files/graphviz/bin/dot' ;;
			*)                     CMD_GAWK='/bin/dot' ;;
		esac
	fi
	$CMD_DOT -V >/dev/null  2>&1
	if [[ $? > 0 ]]; then 
		echo "ERROR: dot not found"
		exit 1
	fi
fi

# check for executables --gawk--
CMD_GAWK=$( which gawk )
if [[ $? > 0 ]]; then
	case ${BASH_VERSINFO[5]} in
		x86_64-apple-darwin14) CMD_GAWK='/usr/local/bin/gawk' ;;
		*)                     CMD_GAWK='/bin/gawk' ;;
	esac
fi
$CMD_GAWK '' >/dev/null
if [[ $? > 0 ]]; then 
	echo "ERROR: gawk not found"
	exit 1
fi

#==============================================================================
# command line options

for ((n=1; $n <= $# ; n++)) ; do
	option="${!n}"                                         # get the $n.th argument
	case "$option" in
	--) break ;;                                           # end of parsing
	-[A-Za-z0-9][A-Za-z0-9]*)                              # split combined options
		_o=""
		for (( i=1; $i < ${#option} ; i++ )) ; do
			_o="$_o -${option:$i:1}"
		done
		set - $_o ${@:$((n+1))}
		n=0
		;;
	-c | --cont*)  optListByContext=1; (( n++ )); optContext="${!n}" ;;
	-p | --proj*)  optListByProject=1; (( n++ )); optProject="${!n}" ;;
	-s | --sort*)  optSortTags=1 ;;                        # activate sorting of CONTEXT, DEPEND, PROJECT and WAITINGFOR tags
	-S | --stat*)  optPrintStatistics=1 ;;                 # print statistics
	-x | --xport)  optExportCSV=1 ;;                       # export as csv  
	*)	           MyARGS=( ${MyARGS[@]} $option ) ;;      # collect all the rest (without checking)
	esac
done

argSearchMe="${MyARGS[@]}"

#==============================================================================
# awk functions

# awkImportOutlook - Import tasks from MS Outlook
# This expects a manual export of the open tasks to the file outlook.csv
# The expected fields are separated by a TAB:
# Start Date	Due Date	Task Subject	Total Work	% Complete	In Folder	Categories	

awkImportOutlook='
	BEGIN {FS="	"}
	/^Start Date/ {next}
	{
		sub("None","",$1)
		sub("None","",$2)
		gsub(" ","",$4); sub("^0h","",$4)
		sub("^0%","",$5)
		gsub(",","",$6); gsub(" ","_",$6); 
		gsub(",","",$7); gsub(" "," @",$7)
		
		if (sub("^Inbox","",$6)) { printf "%s ", "@INBOX" }
		sub("^Tasks","",$6)

		if ($1) {printf "%s ", "@"$1} # Start Date
		if ($2) {printf "%s ", "!"$2} # Due Date
		if ($3) {printf "%s ",    $3} # Task Subject
		if ($4) {printf "%s ", "="$4} # Total Work
		if ($5) {printf "%s ", "="$5} # % Complete
		if ($6) {printf "%s ", "+"$6} # In Folder
		if ($7) {printf "%s ", "@"$7} # Categories
		print "(see Outlook)"
	}
'

#==============================================================================
# functions

function csv2txt {
	cat $1 | #
	awk '
		/^[ \t]*$/ {next}         # ignore empty lines (but keep separators)
		BEGIN {FS=","}
		{
			sub(/^,+/,"")         # remove leading commas (task not done)
			gsub(/,+/," ")        # replace comma by space
			gsub("&#44;",",")     # re-insert commas for free text
			gsub(/[\t ]+/," ")    # trim multiple white-space
			print
		}
		'
}

# txt2csv - parse todo.txt or done.txt file and sort entries in respective columns
# Arguments: $1 = file-name, $2 = file-type flog: todo (default) or done
function txt2csv {
	cat $1 | #
	awk '
		/^[ \t'${optSeparator}']*$/ {next}       # ignore empty lines and separators
		/^'${optSeparator}${optSeparator}${optSeparator}']*/ {next} # ignore 3+ separators
		{print $0" __NEXT__"}                    # remember line end
	' | #
	$CMD_GAWK '                         
		BEGIN {RS="[\t ]+"}       # process word by word, needs gawk on Mac OS X
		/^{/,/}$/ {print; next}
		{print}
	' | #
	$CMD_GAWK -vFILETIME=$( stat -c "%Y" $1) -vFILETYPE=$2 '
		BEGIN {
			IGNORECASE=1
			OFS=","
			c=0                             # field counter
			CNT_FIELDS='${CNT_FIELDS}'
			CONTEXT='${CONTEXT}'
			CREATEDATE='${CREATEDATE}'
			DELEGATED='${DELEGATED}'
			DEPEND='${DEPEND}'
			DONE='${DONE}'
			DONEDATE='${DONEDATE}'
			DUEDATE='${DUEDATE}'
			DURATION='${DURATION}'
			ID='${ID}'
			NOTBEFORE='${NOTBEFORE}'
			PERIODIC='${PERIODIC}'
			PRIORITY='${PRIORITY}'
			PROJECT='${PROJECT}'
			STICKY='${STICKY}'
			TASK='${TASK}'
			WAITINGFOR='${WAITINGFOR}'
 
			m=strftime("%m")+0 # month
			y=strftime("%Y")+0 # year
			isLEAPYEAR=(y%100==0)?(y%400==0):(y%4==0)
			weekdayToday=(index("MonTueWedThuFriSatSun",strftime("%a"))+2)/3 #/
			dateFILE=strftime("%F", FILETIME)
			dateTODAY=strftime("%F")
			dateTOMORROW=strftime("%F", systime()+86400)
			dateMONDAYBEFORENEXTFRIDAY=strftime("%F", systime()+(((5-weekdayToday+6)%7)-3)*86400)
			dateNEXTFRIDAY=strftime("%F", systime()+(((5-weekdayToday+6)%7)+1)*86400)
			dateMONDAYBEFORE2NDNEXTFRIDAY=strftime("%F", systime()+(((5-weekdayToday+6)%7)+4)*86400)
			date2NDNEXTFRIDAY=strftime("%F", systime()+(((5-weekdayToday+6)%7)+8)*86400)
			daysTHISMONTH=substr("312831303130313130313031",m*2-1,2)+isLEAPYEAR&&(m==2)
			daysTHISYEAR=365+isLEAPYEAR
		}

		# sort the words within a string alphabetically
		function sortString(s, 		a, i, n, r) {
			split(s, a)
			n = asort(a)
			for (i=1; i<=n; i++) {
				r = r sprintf(a[i]) " "
			}
			return r
		}

		{
			c++                             # field counter
			gsub(/^[ \t]+|[ \t]+$/, "")     # trim
			gsub(",", "\\&#44;")            # replace commas in free text
		}

		# DONE
		# A completed task starts with an x (case-sensitive lowercase) followed directly by a space. (Gina Trapani)
		/^x$/ && c==1 {
			F[DONE] = "x"
			F[STICKY] = "" # get rid of sticky bit when task was done
			next
		}

		# DONEDATE
		# The date of completion appears directly after the x, separated by a space. (Gina Trapani)
		# caveat: gawk v3.1.7 does not support interval expressions in regular expressions (e.g. /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/)
		/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && c==2 && F[DONE] {
			if (FILETYPE == "todo") { # we do not know if it really is a DONEDATE or a CREATEDATE
				F[CREATEDATE] = $0
				F[DONEDATE] = dateFILE
			} else {
				F[DONEDATE] = $0
			}
			next
		}

		# DONEDATE extension
		# To avoid misinterpretation between DONEDATE and CREATEDATE, a "." right after the x will be replaced by the file date
		# It should not be necessary to use this option. This option may be deleted in a future version)
		/^\.$/ && c==2 && F[DONE] {
			F[DONEDATE] = dateFILE
			next
		}

		# STICKY new tag
		# A sticky task starts with an "^" followed directly by a space. (AnTu)
		# Have following cases:
		# ^            : c==1 -> keep sticky bit
		# x ^          : c==2 -> remove sticky bit
		# x DONEDATE ^ : c==3 -> remove sticky bit
		/^\^/ && c==1 {
			F[STICKY] = "^"
			c-- # dirty trick
			next
		}
		/^\^/ && ( c==2 && F[DONE] || c==3 && F[DONEDATE] ) { # has to be checked after DONE or DONEDATE
			F[STICKY] = "" # get rid of sticky bit when task was done
			c-- # dirty trick
			next
		}
		/^[~!@#$%&*-_=+<>]$/ && c==1 {
			F[STICKY] = $0
			c-- # dirty trick
			next
		}

		# PRIORITY
		# If priority exists, it ALWAYS appears first. (Gina Trapani)
		# The priority is an uppercase character from A-Z enclosed in parentheses and followed by a space. (Gina Trapani)
		/^\([A-Z]\)$/ && ( c==1 || (( c==2 || c==3 ) && F[DONE] )) {
			F[PRIORITY] = $0
			next
		}

		# CREATEDATE
		# A task creation date may optionally appear directly after priority and a space. (Gina Trapani)
		# Have following cases:
		# CREATEDATE                     : c==1
		# PRIORITY CREATEDATE            : c==2
		# x CREATEDATE                   : c==2 was handled above by DONEDATE
		# x DONEDATE CREATEDATE          : c==3
		# x PRIORITY CREATEDATE          : c==3
		# x DONEDATE PRIORITY CREATEDATE : c==4
		# caveat: gawk v3.1.7 does not support interval expressions in regular expressions (e.g. /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/)
		/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && ( c==1 || ( c==2 && ( F[PRIORITY] || F[DONE] ) ) || ( c==3 && ( F[DONEDATE] || ( F[DONE] && F[PRIORITY] ) ) ) || ( c==4 && F[DONEDATE] && F[PRIORITY] ) ) {
			if ( FILETYPE == "todo" && F[CREATEDATE] ) { # if the DONEDATE was mis-interpreted as CREATEDATE, undo that
				F[DONEDATE] = F[CREATEDATE]
			}
			F[CREATEDATE] = $0
			next
		}

		# NOTBEFORE extension: today
		# input  can be "(@|nb(4|f(r)?):)today(:)?"
		# output todays date as "@YYYY-MM-DD"
		/^(@|nb(4|f(r)?):)today(:)?$/ { # has to be checked before CONTEXT and NOTBEFORE
			F[NOTBEFORE] = "@" dateTODAY
			next
		}

		# NOTBEFORE extension: tomorrow
		# input  can be "(@|nb(4|f(r)?):)tomorrow(:)?"
		# output tomorrows date as "@YYYY-MM-DD"
		/^(@|nb(4|f(r)?):)tomorrow(:)?$/ { # has to be checked before CONTEXT and NOTBEFORE
			F[NOTBEFORE] = "@" dateTOMORROW
			next
		}

		# NOTBEFORE new tag (extension to CONTEXT)
		# Tasks that have to be done not before or start on a certain day.
		# input  prefix for not before dates: "(@|nb4:|nbf:|nbfr:)"
		# output prefix for not before dates: "@"
		# caveat: gawk v3.1.7 does not support interval expressions in regular expressions (e.g. /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/)
		/^(@|nb(4|f(r)?):)[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { # has to be checked before CONTEXT
			sub(/(@|nb(4|f(r)?):)/,"@")
			F[NOTBEFORE] = $0
			next
		}

		# DUEDATE extension: today
		# input  can be "!today", "!today:", "due:today", "due:today:" or "today:"
		# output todays date as "!YYYY-MM-DD"
		/^((!|due:)today(:)?|today:)$/ { # has to be checked before DELEGATED and DUEDATE
			F[DUEDATE] = "!" dateTODAY
			next
		}

		# DUEDATE extension: tomorrow
		# input  can be "!tomorrow", "!tomorrow:", "due:tomorrow", "due:tomorrow:" or "tomorrow:"
		# output tomorrows date as "!YYYY-MM-DD"
		/^((!|due:)tomorrow(:)?|tomorrow:)$/ { # has to be checked before DELEGATED and DUEDATE
			F[DUEDATE] = "!" dateTOMORROW
			next
		}

		# DUEDATE extension: thisweek
		# input  can be "!thisweek", "!thisweek:", "due:thisweek", "due:thisweek:" or "thisweek:"
		# output next Fridays date as "!YYYY-MM-DD"
		/^((!|due:)thisweek(:)?|thisweek:)$/ { # has to be checked before DELEGATED and DUEDATE but after NOTBEFORE
			F[DUEDATE] = "!" dateNEXTFRIDAY
			if (!F[NOTBEFORE]) { F[NOTBEFORE] = "@" dateMONDAYBEFORENEXTFRIDAY }
			next
		}

		# DUEDATE extension: nextweek
		# input  can be "!nextweek", "!nextweek:", "due:nextweek", "due:nextweek:" or "nextweek:"
		# output next Fridays date as "!YYYY-MM-DD"
		/^((!|due:)nextweek(:)?|nextweek:)$/ { # has to be checked before DELEGATED and DUEDATE but after NOTBEFORE
			F[DUEDATE] = "!" date2NDNEXTFRIDAY
			if (!F[NOTBEFORE]) { F[NOTBEFORE] = "@" dateMONDAYBEFORE2NDNEXTFRIDAY }
			next
		}

		# DUEDATE new tag
		# input  prefix for due dates: "(!|due:)"
		# output prefix for due dates: "!"
		# caveat: gawk v3.1.7 does not support interval expressions in regular expressions (e.g. /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/)
		/^(!|due:)[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ {
			sub(/(!|due:)/,"!")
			F[DUEDATE] = $0
			next
		}

		# PERIODIC new tag
		# Variant1: Use a term for periodic, ending in a colon ":"
		/^((half-|se(mi)?|bi|tri|dec|cent)?(weekly|mestr(i)?al|monthly|annual|ennial|yearly)|(catameni|diurn|hebdomad|menstru|season|sidere|tropic)al|centenary|(fortnight|midweek|quarter)(ly)?|(quotid|tert)ian|(sec|irreg)ular|continuous|(anomalist|dracon|synod)ic|(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)?da(ily|ys)):$/ {
			F[PERIODIC] = $0
			next
		}
		# Variant2: Have a date or a set of days, months, years in curly braces
		# if used in conjunction with variant 1, this one has to be _after_ variant 1
		/^{([0-9]+|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Mon|Tue|Wed|Thu|Fri|Sat|Sun)/,/}$/ {
			F[PERIODIC] = F[PERIODIC] " " $0
			next
		}

		# PROJECT
		# Projects may appear anywhere in the line after priority/prepended date. (Gina Trapani)
		# There may be more than one project. A project contains any non-whitespace character and must end in an alphanumeric or ‘_’. A project is preceded by an plus + sign. (Gina Trapani)
		/^\+[^ \t]/ { F[PROJECT] = F[PROJECT] " " $0 ; next} 

		# DEPEND new tag (extension of WAITINGFOR)
		# This task can only be done if the referred task was done. (This script does not check anything.)
		# input  prefix for dependencies "(@!#|dep:|wait:#)"
		# output prefix for dependencies "@!#"
		/^(@!#|dep:|wait:#)/ { # has to be checked before CONTEXT and WAITINGFOR
			sub(/(@!#|dep:|wait:#)/,"@!#")
			F[DEPEND] = F[DEPEND] " " $0
			next
		}

		# WAITINGFOR new tag (extension of CONTEXT)
		# input  prefix for waiting-for entries "(@!|wait:)"
		# output prefix for waiting-for entries: "@!"
		/^(@!|wait:)/ { # has to be checked before CONTEXT
			sub(/(@!|wait:)/,"@!")
			F[WAITINGFOR] = F[WAITINGFOR] " " $0
			next
		}

		# CONTEXT
		# Contexts may appear anywhere in the line after priority/prepended date. (Gina Trapani)
		# There may be more than one context. A context contains any non-whitespace character and must end in an alphanumeric or ‘_’. A context is preceded by an @ sign. (Gina Trapani)
		/^@/ { F[CONTEXT] = F[CONTEXT] " " $0 ; next}

		# ID new tag
		# There can be only one task-id. The first one wins -> all others are added to the task text -> be sure to have the ID printed before the TASK text. They should be unique but it is not checked here.
		# input  prefix for task-ids: "(#|id:)"
		# output prefix for task-ids: "#"
		/^(#|id:)/ && !F[ID] {
			sub(/(#|id:)/,"#")
			F[ID] = $0
			next
		}
		
		# DELEGATED new tag
		# input  prefix for task-ids: "(!|delegated:)"
		# output prefix for task-ids: "!"
		/^(!|delegated:)[A-Za-z]+)/ {
			sub(/(!|delegated:)/,"!")
			F[DELEGATED] = $0
			next
		}

		# DURATION new tag
		# input  prefix for task-ids: "(=|duration:)"
		# output prefix for task-ids: "="
		/^(=|duration:)[0-9]+(a|yr(s)?|M(on(th(s)?)?)?|(w|W)(eek(s)?)?|d(ay(s)?)?|h(r(s)?)?|min)/ && !F[DURATION] {
			sub(/(=|duration:)/,"=")
			F[DURATION] = $0
			next
		}

		# Output of one line
		/__NEXT__/ {

			# sort tags alphabetically
			if ('${optSortTags}') {
				if (F[CONTEXT])    { F[CONTEXT]    = sortString(F[CONTEXT])   }
				if (F[DEPEND])     { F[DEPEND]     = sortString(F[DEPEND])    }
				if (F[PROJECT])    { F[PROJECT]    = sortString(F[PROJECT])   }
				if (F[WAITINGFOR]) { F[WAITINGFOR] = sortString(F[WAITINGFOR])}
			}

			# trim
			gsub(/^[ \t]+|[ \t]+$/, "", F[CONTEXT]    )
			gsub(/^[ \t]+|[ \t]+$/, "", F[DEPEND]     )
			gsub(/^[ \t]+|[ \t]+$/, "", F[PROJECT]    )
			gsub(/^[ \t]+|[ \t]+$/, "", F[WAITINGFOR] )
			gsub(/^[ \t]+|[ \t]+$/, "", F[TASK]       )

			# new items are going to the INBOX
			if (!F[STICKY] && !F[DONE] && !F[DONEDATE] && !F[PRIORITY] && !F[CREATEDATE] && !F[NOTBEFORE] && !F[DUEDATE] && !F[PERIODIC] && !F[PROJECT] && !F[CONTEXT] && !F[DELEGATED] && !F[ID] && !F[WAITINGFOR] && !F[DEPEND] && !F[DURATION]) {
				F[CONTEXT] = "@INBOX"
			}

			# reference (R) and someday/maybe (S) items do not need any date
			if (F[PRIORITY] == "(R)" || F[PRIORITY] == "(S)" ) {
				F[NOTBEFORE]  = ""
				F[DUEDATE]    = ""
				F[PERIODIC]   = ""
				F[WAITINGFOR] = ""
				F[DEPEND]     = ""
				F[DURATION]   = ""
			}

			# dirty trick: if neither due date is given for periodic tasks,
			# mark it as done. The rescheuldeDone() function will then set a
			# proper new NOTBEFORE date.
			if (F[PERIODIC] && F[PERIODIC] != "irregular:" && !F[DONE] && !F[NOTBEFORE] && !F[DUEDATE]) {
				F[DONE] = "x"
			}

			# done today
			if (F[DONE] && !F[DONEDATE]) {
				F[DONEDATE] = "'${today}'"
			}

			# add or remove creation date
			if ('${optHaveCreateDate}'==1 && !F[CREATEDATE]) {
				F[CREATEDATE] = "'${today}'"
			} else if ('${optHaveCreateDate}'==-1) {
				F[CREATEDATE] = ""
			}

			if ('${optHaveCreateDateForPeriodicTasks}'==1 && F[PERIODIC] && !F[CREATEDATE] ) {
				F[CREATEDATE] = "'${today}'"
			} else if ('${optHaveCreateDateForPeriodicTasks}'==-1 && F[PERIODIC]) {
				F[CREATEDATE] = ""
			}

			# output
			for (i=1 ; i<=CNT_FIELDS ; i++) {
				printf "%s", F[i] OFS
			}
			printf "\n"
			delete F
			c=0
			next
		}

		# TASK
		# Everything else is part of the task description itself
		{ F[TASK] = F[TASK] " " $0 }
	'
}


# depend2gv - prepare for GraphViz outout (dot syntax)
#
function depend2gv {
	cat $1 | #
	awk '
		BEGIN {
			FS=","
			OFS=","
			CNT_FIELDS='${CNT_FIELDS}'
			CONTEXT='${CONTEXT}'
			CREATEDATE='${CREATEDATE}'
			DELEGATED='${DELEGATED}'
			DEPEND='${DEPEND}'
			DONE='${DONE}'
			DONEDATE='${DONEDATE}'
			DUEDATE='${DUEDATE}'
			DURATION='${DURATION}'
			ID='${ID}'
			NOTBEFORE='${NOTBEFORE}'
			PERIODIC='${PERIODIC}'
			PRIORITY='${PRIORITY}'
			PROJECT='${PROJECT}'
			STICKY='${STICKY}'
			TASK='${TASK}'
			WAITINGFOR='${WAITINGFOR}'

			print "digraph G{"
			print "graph [rankdir=LR]"
		}

		$ID != "" {
			sub("#", "", $ID)
#			label[$ID] = $TASK
			label[$ID] = $ID
		}

		$DEPEND != "" {
			needlabel[$ID] = 1
			gsub("@!#", "", $DEPEND)
			split($DEPEND, a," ")

			for (i in a) {
				needlabel[a[i]] = 1
				print "{ " a[i] " } -> { " $ID " }"
			}
			
		}

		END {
			for (i in needlabel) {
				print i " [ label=\"" label[i] "\" ]"
			}
			print "}"
		}
	'
}

# virtualSort - sort the list
#
# GTD says: "Sort 1st by context, 2nd by time available, 3rd by energy available, 4th by priority"
# This does it a bit different...
#
function virtualSort {
	cat $1 | #
	$CMD_GAWK ' # needs GNU awk time functions
		BEGIN {
			FS=","
			OFS=","
			CNT_FIELDS='${CNT_FIELDS}'
			CONTEXT='${CONTEXT}'
			CREATEDATE='${CREATEDATE}'
			DELEGATED='${DELEGATED}'
			DEPEND='${DEPEND}'
			DONE='${DONE}'
			DONEDATE='${DONEDATE}'
			DUEDATE='${DUEDATE}'
			DURATION='${DURATION}'
			ID='${ID}'
			NOTBEFORE='${NOTBEFORE}'
			PERIODIC='${PERIODIC}'
			PRIORITY='${PRIORITY}'
			PROJECT='${PROJECT}'
			STICKY='${STICKY}'
			TASK='${TASK}'
			WAITINGFOR='${WAITINGFOR}'
			tToday = systime() - systime() % 86400 # to ignore timezones
			#print "DEBUG: Today is " strftime("%F %T",tToday) > "/dev/stderr"
			tNextWeek = tToday + ( 7 * 86400 )
			#print "DEBUG: Next Week is " strftime("%F %T",tNextWeek) > "/dev/stderr"
			}

		{
			# get all the dates
			split($CREATEDATE,a,"-"); l=length(a[1]); tCREATE   = mktime(substr(a[1],l-3)" "a[2]" "a[3]" 00 00 00"); delete a
			split($DONEDATE,  a,"-"); l=length(a[1]); tDONE     = mktime(substr(a[1],l-3)" "a[2]" "a[3]" 00 00 00"); delete a
			split($NOTBEFORE, a,"-"); l=length(a[1]); tNOTBEFORE= mktime(substr(a[1],l-3)" "a[2]" "a[3]" 00 00 00"); delete a
			split($DUEDATE,   a,"-"); l=length(a[1]); tDUE      = mktime(substr(a[1],l-3)" "a[2]" "a[3]" 00 00 00"); delete a

			# get the Duration, if any
			tDuration = 0
			if (match($DURATION, /=([0-9]*)min/, a)) {tDuration = a[1] *    1 } else
			if (match($DURATION, /=([0-9]*)h/,   a)) {tDuration = a[1] *   60 } else
			if (match($DURATION, /=([0-9]*)d/,   a)) {tDuration = a[1] *  495 } # one working day = 8.25 h
			#print "DEBUG: Duration " $DURATION " is " tDuration " minutes" > "/dev/stderr"

			### now sort
			# 24.(Z) All the rest
			tSORT=sprintf("Z_%010d", 2147483647) # max value on 32bit systems, = mktime("2038 01 19 04 14 07")

			# 23.(Y) (not yet used)
			# 22.(X) (not yet used)
			# 21.(W) (not yet used)
			# 20.(V) (not yet used)
			
			# 19.(U) defer (see below)

			# 18.(T) Reference (see below)
			
			# 17.(S) waiting for something (delegated, depend, waitingfor) (see below)
			
			# 16.(R) Someday/maybe (see below)

			# 15.(Q) Start later (see below)

			# 14.(P) Creation date
			if ( tCREATE > 0 ) { tSORT = sprintf("P_%010d", tCREATE) }

			# 13.(O) Priority
			if ( $PRIORITY != "" ) { tSORT = sprintf("O_%3s0000000", $PRIORITY) }

			# ooo 18.(T) Reference R or Work-package W  (! needs to be out of order)
			if ( $PRIORITY == "(R)" ) { tSORT = "T_(R)00000000" }
			if ( $PRIORITY == "(W)" ) { tSORT = "T_(W)00000000" }

			# ooo 16.(R) Someday/maybe (! needs to be out of order)
			if ( $PRIORITY == "(S)" ) { tSORT = "R_0000000000" }

			# 12.(N) Future due (due date > next week)
			if ( tDUE >= tNextWeek ) { tSORT = sprintf("N_%010d", tDUE)  }

			# 11.(M) Start tomorrow (nb4 date = tomorrow)
			if ( tNOTBEFORE > 0 && tNOTBEFORE - tToday < 86400 ) { tSORT = sprintf("M_%010d", tNOTBEFORE) }

			# 10.(L) Deadline is next week (due date < next week)
			if ( tDUE > 0 && tDUE < tNextWeek ) { tSORT = sprintf("L_%010d", tDUE)  }

			# ooo 15.(Q) Start later (! needs to be out of order)
			if ( tNOTBEFORE >= tToday + 86400 ) { tSORT = sprintf("Q_%010d", tNOTBEFORE ) }

			# 9.(K) Needs project planning
			if ( $PRIORITY == "(P)" ) { tSORT =  sprintf("K_%010d", tCREATE) }

			# 8.(J) Deadline is tomorrow (due date = tomorrow)
			if ( tDUE > 0 && tDUE - tToday < 86400 ) { tSORT = sprintf("J_%010d", tDUE) }

			# 7.(I or C)  Start today (nb4 date = today)
			if ( tNOTBEFORE > 0 && tNOTBEFORE - tToday <= 0 ) { tSORT = sprintf("%.1s_%010d", ('${optHaveTodaysTasksFirst}' ? "C" : "I"), tNOTBEFORE) }

			# 6.(H) Not done (nb4 date < today)
			if ( tNOTBEFORE > 0 && tNOTBEFORE - tToday < -86400 ) { tSORT = sprintf("H_%010d", tNOTBEFORE) }

			# 5.(G) Only takes 5 minutes (e.g. duration <= 10 min)
			if ( tNOTBEFORE <= 0 && tDuration > 0 && tDuration <= '${optShortDuration}' ) { tSORT = sprintf("G_%010d", tDuration) }

			# 4.(F) check the in-box
			if ( $CONTEXT == "@INBOX" ) { tSORT = sprintf("F_%010d", tCREATE) }

			# 3.(E or B) Deadline is today (due date = today)
			if ( tDUE > 0 && tDUE - tToday <= 0 ) { tSORT = sprintf("%.1s_%010d", ('${optHaveTodaysTasksFirst}' ? "B" : "E"), tDUE) }

			# 2.(D) Overdue (due date < today)
			if ( tDUE > 0 && tDUE - tToday < -86400 ) { tSORT = sprintf("D_%010d", tDUE)  }

			# ooo 17.(S) waiting for something (delegated, depend, waiting for) (! needs to be out of order)
			if ( $DELEGATED != "" || $DEPEND != "" || $WAITINGFOR != "" ) { tSORT = sprintf("S_%010d", tCREATE) }

			# 1.(A) Sticky
			if ( $STICKY ) { tSORT = sprintf("A_%010d", tCREATE) }

			# ooo 19.(U) Defer  (! needs to be out of order)
			if ( $STICKY == "_" ) { tSORT = "U_0000000000" }

			tSORT = tSORT sprintf("%.1s_%-10.10s", substr($PRIORITY,2,1), $ID $DEPEND $WAITINGFOR sprintf("%06d", tDuration))
		}
		
		{
#			print "DEBUG: " tSORT , $0 > "/dev/stderr" #DEBUG
			print tSORT "," $0
		}
		' |#
		sort | #
		cut -d, -f2-
}

# rescheduleDone - reschedule periodic tasks when it was done
# 
function rescheduleDone {
	grep "^,x," $1 | # only done tasks need to be rescheduled
	$CMD_GAWK ' # needs GNU awk time functions
		BEGIN {
			FS=","
			OFS=","
			CNT_FIELDS='${CNT_FIELDS}'
			CONTEXT='${CONTEXT}'
			CREATEDATE='${CREATEDATE}'
			DELEGATED='${DELEGATED}'
			DEPEND='${DEPEND}'
			DONE='${DONE}'
			DONEDATE='${DONEDATE}'
			DUEDATE='${DUEDATE}'
			DURATION='${DURATION}'
			ID='${ID}'
			NOTBEFORE='${NOTBEFORE}'
			PERIODIC='${PERIODIC}'
			PRIORITY='${PRIORITY}'
			PROJECT='${PROJECT}'
			STICKY='${STICKY}'
			TASK='${TASK}'
			WAITINGFOR='${WAITINGFOR}'
		}
		
		function endOfMonth(t) {
			m = strftime("%m", t) + 0
			return substr("312831303130313130313031", m * 2 - 1, 2) + ( isLeapYear(t) && (m==2) )
		}

		function isLeapYear(t)   {
			y = strftime("%Y", t) + 0
			return ( y % 100 == 0 ) ? ( y % 400 == 0 ) : ( y % 4 == 0 )
		}

		$PERIODIC != "" {
#			print $0 > "/dev/tty" # DEBUG
			# if neither date is given, set a new NOTBEFORE date
			if (! ( $NOTBEFORE || $DUEDATE ) ) {
				$NOTBEFORE = strftime("@%F")
			}

			# get the dates
			split($NOTBEFORE, a,"-"); l=length(a[1]); tNOTBEFORE= mktime(substr(a[1],l-3)" "a[2]" "a[3]" 00 00 00"); delete a
			split($DUEDATE,   a,"-"); l=length(a[1]); tDUEDATE  = mktime(substr(a[1],l-3)" "a[2]" "a[3]" 00 00 00"); delete a
			periode=$PERIODIC
			addTnb4=0
			addTdue=0
			
			# this currently is only supporting Variant 1
			if (periode ~ "midweek(ly)?") {
				periode="Wednesdays:"
			}
			if (periode == "irregular:") {
				$NOTBEFORE=""          # remove any due dates
				$DUEDATE=""
			} else if (periode == "continuous:") {
				$STICKY="^"            # make it sticky for today
				tNOTBEFORE = systime()
				tDUEDATE   = systime()
			} else if (periode ~ "^(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)da(ily|ys):") {
				d = (index("MonTueWedThuFriSatSun",substr(periode,1,3))+2)/3 #/
				tNOTBEFORE= tNOTBEFORE + ((d+6-strftime("%u", tNOTBEFORE)) % 7 + 1) * 86400
				tDUEDATE  = tDUEDATE   + ((d+6-strftime("%u", tDUEDATE)  ) % 7 + 1) * 86400
			}
			else if (periode ~  "(d(aily|iurnal)|quotidian):")                 { addTnb4 = 86400 *     1.00 ; addTdue = addTnb4 }
			else if (periode == "bidaily:")                                    { addTnb4 = 86400 *     2.00 ; addTdue = addTnb4 }
			else if (periode ~  "t(ertian|ridaily):")                          { addTnb4 = 86400 *     3.00 ; addTdue = addTnb4 }
			else if (periode == "semiweekly:")                                 { addTnb4 = 86400 *     3.50 ; addTdue = addTnb4 }
			else if (periode ~ "^(hebdomadal|weekly):")                        { addTnb4 = 86400 *     7.00 ; addTdue = addTnb4 } 
			else if (periode ~  "(biweek|fortnight)ly:")                       { addTnb4 = 86400 *    14.00 ; addTdue = addTnb4 }
			else if (periode ~  "(half-|semi)monthly:")                        { addTnb4 = 86400 *    15.22 ; addTdue = addTnb4 }
			else if (periode == "triweekly:")                                  { addTnb4 = 86400 *    21.00 ; addTdue = addTnb4 }
			else if (periode == "draconic:")                                   { addTnb4 = 86400 *    27.21 ; addTdue = addTnb4 } # lunar
			else if (periode ~  "(sideri|tropic)al:")                          { addTnb4 = 86400 *    27.32 ; addTdue = addTnb4 } # lunar
			else if (periode == "anomalistic:")                                { addTnb4 = 86400 *    27.55 ; addTdue = addTnb4 } # lunar
			else if (periode ~  "((catameni|menstru)al|synodic):")             { addTnb4 = 86400 *    29.53 ; addTdue = addTnb4 } # lunar
			else if (periode == "monthly:")                                    { addTnb4 = 86400 * endOfMonth(tNOTBEFORE);
																				 addTdue = 86400 * endOfMonth(tDUEDATE) ;       } 
			else if (periode ~  "bim(estrial|onthly):")                        { addTnb4 = 86400 *    60.87 ; addTdue = addTnb4 }
			else if (periode ~  "(seasonal|quarterly|trimonthly):")            { addTnb4 = 86400 *    91.31 ; addTdue = addTnb4 }
			else if (periode ~  "trimester(ial)?:")                            { addTnb4 = 86400 *   121.75 ; addTdue = addTnb4 }
			else if (periode ~  "(sem(iannu|estr(i)?)al|(half-|semi)yearly):") { addTnb4 = 86400 *   182.62 ; addTdue = addTnb4 }
			else if (periode ~  "^(annual|yearly):")                           { addTnb4 = 86400 * (365 + isLeapYear(tNOTBEFORE));
																				 addTdue = 86400 * (365 + isLeapYear(tDUEDATE)) }
			else if (periode ~  "(canicular|sothic):")                         { addTnb4 = 86400 *   533.63 ; addTdue = addTnb4 } # new
			else if (periode ~  "bi((annu|enni)al|yearly):")                   { addTnb4 = 86400 *   730.49 ; addTdue = addTnb4 }
			else if (periode == "triennial:")                                  { addTnb4 = 86400 *  1095.73 ; addTdue = addTnb4 }
			else if (periode == "olymiad:")                                    { addTnb4 = 86400 *  1460.97 ; addTdue = addTnb4 } # new
			else if (periode == "lustrum:")                                    { addTnb4 = 86400 *  1826.21 ; addTdue = addTnb4 } # new
			else if (periode == "decennial:")                                  { addTnb4 = 86400 *  3652.43 ; addTdue = addTnb4 }
			else if (periode == "saeculum:")                                   { addTnb4 = 86400 * 32871.82 ; addTdue = addTnb4 } # new
			else if (periode ~  "(centen(ary|nial)|secular):")                 { addTnb4 = 86400 * 36524.25 ; addTdue = addTnb4 }
			else {
				# not used here: anything greater than 100 years (aeon, byr, banzai, chron, epoch, era, millennium) or smaller than 1 day (hour, minute, second, chronon)
			}

			if ($NOTBEFORE) { $NOTBEFORE = strftime("@%F", tNOTBEFORE + addTnb4) }
			if ($DUEDATE)   { $DUEDATE   = strftime("!%F", tDUEDATE   + addTdue) }
			$DONE=""
			$DONEDATE=""
			print # the rescheduled version
		}
	'
}

#==============================================================================
# MAIN
#==============================================================================

#line feed and separator
LF="
"

if [[ $optAddSeparator > 0 ]]; then
	eval printf -v sep "%.0s${optSeparator}" {1..${optSeparatorLength}}
	sep="${LF}${sep}"
else
	sep=""
fi

if [ -e outlook.csv ] ; then 
	awk "${awkImportOutlook}" outlook.csv >> todo.txt
	echo "^ Remove flag from imported Outlook tasks !today" >> todo.txt
	rm outlook.csv
fi

# loop over todo.txt files
for ((file_n=0; file_n < ${#FILE_TODO[@]}; file_n++)); do

#	echo "DEBUG: file_n = $file_n"
#	echo "DEBUG: done   = ${FILE_DONE[$file_n]}"
#	echo "DEBUG: todo   = ${FILE_TODO[$file_n]}"
#	echo "DEBUG: report = ${FILE_RPRT[$file_n]}"

	#------------------------------------------------------------------------------
	# read files, convert to csv
	if [ -e ${FILE_DONE[$file_n]} ] ; then done_csv="$(txt2csv ${FILE_DONE[$file_n]} 'done')" ; else done_csv="" ; fi
	if [ -e ${FILE_TODO[$file_n]} ] ; then todo_csv="$(txt2csv ${FILE_TODO[$file_n]} 'todo')" ; else todo_csv="" ; fi


	#------------------------------------------------------------------------------
	# add new entries for done tasks that are periodic
	todo_csv="${todo_csv}${LF}$(echo "${todo_csv}" | rescheduleDone )"

	#------------------------------------------------------------------------------
	# move finished tasks to done_csv
	# Since the sticky-bit is in the first field, the done-marker "x" is now in the second field
	justdone_csv="$(echo "${todo_csv}" | grep "^,x,")"
	done_csv="${done_csv}${LF}${justdone_csv}"
	todo_csv="$(echo "${todo_csv}" | grep -v "^,x,")"
	
	#------------------------------------------------------------------------------
	# remove dependencies on just done tasks or deleted tasks
	myIDs="$(echo "${todo_csv}" | awk -F, '$'${ID}' {printf $'${ID}'","}')"

	todo_csv="$(echo "${todo_csv}" | awk '
		BEGIN {
			FS=","
			OFS=","
			DEPEND='${DEPEND}'
			IDs="'${myIDs}'"
		}

		$DEPEND ~ /^@!#/    { if (! match(IDs,    substr($DEPEND,3)",")  ) { $DEPEND = "" } }
		$DEPEND ~ /^dep:/   { if (! match(IDs, "#"substr($DEPEND,5)",")  ) { $DEPEND = "" } }
		$DEPEND ~ /^wait:#/ { if (! match(IDs,    substr($DEPEND,6)",")  ) { $DEPEND = "" } } 
		{print}
		')"

	#------------------------------------------------------------------------------
	# create dependencies chart
	if [[ $optDependenciesGraph > 0 ]]; then
		echo "${todo_csv}" | depend2gv > ${FILE_TODO[$file_n]%.*}.gv
		$CMD_DOT -Tpng ${FILE_TODO[$file_n]%.*}.gv > ${FILE_TODO[$file_n]%.*}.png
	fi
	
	#------------------------------------------------------------------------------
	# search (if any) and sort
	# special handling of keyword "today"
	#
	tmp=""
	tmp_sticky="$(echo "${todo_csv}" | grep -Ei "^\^" | virtualSort )"  # sticky items

	if [ "${argSearchMe}" ]; then
		case "${argSearchMe}" in
			t|today) argSearchMe="(!|@)${today}" ;; # search for time-stamp of today
		esac
	
		tmp_found="${tmp}$(echo "${todo_csv}" | grep -Eiv "^\^" | grep -Ei "${argSearchMe}" | virtualSort )"
		tmp_other="$(echo "${todo_csv}" | grep -Eiv "^\^|${argSearchMe}" | virtualSort)"
	else
		tmp_other="$(echo "${todo_csv}" | grep -Eiv "^\^" | virtualSort)"
	fi
	
	if [ ! "$tmp_sticky" == "" ]; then tmp="${tmp}${tmp_sticky}${sep}${LF}"; fi
	
	if [ ! "$tmp_found"  == "" ]; then tmp="${tmp}${tmp_found}${sep}${LF}" ; fi
	
	if [[ $optPrintSearchResults > 0 && $tmp != "" ]]; then
		echo "${tmp}" | csv2txt | uniq
	fi
	
	if [ ! "$tmp_other" == ""  ]; then tmp="${tmp}${tmp_other}${LF}"       ; fi
	
	todo_csv="${tmp}"

	
	#------------------------------------------------------------------------------
	# write files

	if [[ $optExportCSV > 0 ]]; then
		echo "${todo_csv}" | uniq > ${FILE_TODO[$file_n]%.*}.csv
		echo "${done_csv}" | sort -ru > ${FILE_DONE[$file_n]%.*}.csv
	fi

	echo "${todo_csv}" | csv2txt | uniq > ${FILE_TODO[$file_n]}
	echo "${done_csv}" | csv2txt | sort -ru > ${FILE_DONE[$file_n]}
	echo "$( date -u +"%Y-%m-%dT%H:%M:%S" ) $( grep -Ev "^-*$" ${FILE_TODO[$file_n]} | wc -l) $(grep -Ev "^-*$" ${FILE_DONE[$file_n]} | wc -l)" >> ${FILE_RPRT[$file_n]}
	sort -t: -k1,1 -u -o ${FILE_RPRT[$file_n]} ${FILE_RPRT[$file_n]}
	
	
	#------------------------------------------------------------------------------
	# display on STDOUT"
	#
	eval printf -v sep '%.0s=' {1..80}
	
	if [[ $optListByContext > 0 ]]; then
		if [ ! "${optContext}" == "-" ]; then
			for context in $( awk 'BEGIN {RS="[ :]"} /^@/ {print substr($0,2)}' ${FILE_TODO[$file_n]} | grep -Ev '^[!12]' | sort -fu | paste -sd" " ); do
				echo "${context}${LF}${sep}"
				grep -hi "@${context}" ${FILE_TODO[$file_n]} | awk '{print "* " $0}'
				echo "${LF}"
			done
		fi
		echo "WITHOUT CONTEXT${LF}${sep}"
		grep -hv "@" ${FILE_TODO[$file_n]} | awk '{print "* " $0}'
	fi
	
	if [[ $optListByProject > 0 ]]; then
		if [ ! "${optProject}" == "-" ]; then
			for project in $( awk 'BEGIN {RS="[ :]"} /^\+/ {print substr($0,2)}' ${FILE_TODO[$file_n]} | sort -fu | paste -sd" " ); do
				echo "${project}${LF}${sep}${LF}"
				grep -hi "+${project}" ${FILE_TODO[$file_n]} | awk '{print "* " $0}'
				echo "${LF}"
			done
		fi
		echo "WITHOUT PROJECTS${LF}${sep}"
		grep -hv "+" ${FILE_TODO[$file_n]} | awk '{print "* " $0}'
	fi

	if [[ $optPrintStatistics > 0 ]]; then
		awk '
			BEGIN {
				n=0
				wd = 5/7*365 - 30 # working days / year
				oc = 1/6*52*7     # on-call days / year
				tr = 30           # training days / year
				}
			/yearly: /         {n = n +  1; next }
			/quarterly: /      {n = n +  4; next }
			/monthly: /        {n = n + 12; next }
			/fortnightly: /    {n = n + 26; next }
			/weekly: /         {n = n + 52; next }
			/daily:*.@on-call/ {n = n + oc; next }
			/daily:*.training/ {n = n + tr; next }
			/daily:/           {n = n + wd; next }
			/[Mon|Tues|Wednes|Thurs|Fri|Satur|Sun]days: / {
				n = n + 52; next
				}
			/^\([R|S]\)/    {next;}
			                {n = n +  1; next }
			END {
				printf "'${optSeparator}${optSeparator}${optSeparator}' %4.0d tasks per year\n", n
				printf "'${optSeparator}${optSeparator}${optSeparator}' %3.1f tasks per working day\n", n/wd
				printf "'${optSeparator}${optSeparator}${optSeparator}' %3.1f minutes per task\n\n", 8*60/(n/wd)
			}
		' ${FILE_TODO[$file_n]} >> ${FILE_TODO[$file_n]}
	fi

done

exit

## ideas, todos
# if task was deferred then set a waitingfor timestamp=(systime()+default_defer_timespan). If timestamp was reached, then delete defer flag
# allow new periodic "weekday(s):" for Mon-Fri tasks, "weekend(s):" for Sat-Sun
# add optional times to any date
# export the planning for the day or week as iCal
# allow team-work with !name, e.g. !AnTu or !Andreas
# have option to remove priorities
# have option to remove deadlines
# have option to define field separator character, e.g. ","
# allow export to other formats
# allow import from other formats
# allow to move tasks to other list "->LISTNAME", where destination-alias is defined in array of files.
# 2013-09-12 add a delete (d) command, where tasks are handled alike done tasks (x) but will not be re-scheduled
# not sure:
# 2013-04-24 implement mktime() in ANSI awk http://gnu.huihoo.org/gawk-3.0.3/html_node/gawk_147.html 


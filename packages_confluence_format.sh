# One liner for generating packages installed for Hadoop from repositories ambari and HDP*
# and converts output to Confluence markup wiki format to generate table

yum list installed | awk ' {OFS="|";$1=$1; if(NF<3){printf "|" $0" ";getline;print $0"|"}else {print "|"$0"|"} }'|column -t |sort -n| egrep -e HDP -e ambari |tr -s " " | tr -s " " "|"|awk ' BEGIN{print "||Package Name|Version|Yum Repository|"}{print $0}'

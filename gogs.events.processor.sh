#!/bin/bash

# ENVIRONMENT VARIABLES:
#	NEW_COMMIT_TO_TEST_FILE
#
#

# E.G:
CURR_SCRIPT_TO_SAVE=`pwd`/run_gogs_events_processor.sh
cat >$CURR_SCRIPT_TO_SAVE  <<EOF
NEW_COMMIT_TO_TEST_FILE=`cat .conf.commits-fname` \
BOT_TOKEN=`cat .conf.bot.token` \
CHANNEL_ID=`cat .conf.channel.id` \
TELEGRAM_GOGS_MANAGER=../telegram.gogs.manager.sh \
../telegram.gogs.manager.sh run-http 0.0.0.0 `cat .conf.port` ../gogs.events.processor.sh
EOF
chmod +x $CURR_SCRIPT_TO_SAVE


METHOD=$1
REQUEST=$2
INPUT=$3
OUTPUT=$4

test "$METHOD" = "POST" || exit 0
test "$REQUEST" = "/events" || exit 0

echo "gogs.events.processor called $METHOD $REQUEST $INPUT $OUTPUT"


source "$(pwd)/$TELEGRAM_GOGS_MANAGER"

EVENTS=$(cat $INPUT)
echo "processing events $EVENTS"

BR="%0A"

show_commit() {
	REPOSITORY=$1
	REPOSITORY_URL=$2
	OWNER=$3
	HEAD_BRANCH=$4
	COMMIT_INFO=$5
	
	echo "SHOWING COMMIT INFO $REPOSITORY:$REPOSITORY_URL '$COMMIT_INFO'"
	echo $(echo $COMMIT_INFO | jq)
	echo "jq req = $?"
	COMMIT_ID=$(echo $COMMIT_INFO | jq ".id" | sed 's/"//g')
	COMMIT_URL=$(echo $COMMIT_INFO | jq ".url" | sed 's/"//g')
	AUTHOR=$(echo $COMMIT_INFO | jq ".author.email" | sed 's/"//g')
	TIMESTAMP=$(echo $COMMIT_INFO | jq ".timestamp" | sed 's/"//g')
	MESSAGE=$(echo $COMMIT_INFO | jq ".message" | sed 's/"//g')
	MESSAGE=$(echo $MESSAGE | sed "s/\n/%0A/g")

	OUTPUT="COMMIT<b>[$COMMIT_ID]</b> $BR $HEAD_BRANCH?$BR$REPOSITORY_URL $BR $COMMIT_URL $BR ($AUTHOR): $TIMESTAMP $BR"

	if [ "$(echo $COMMIT_INFO | jq '.added')" = "null" ]; then
		echo -en "";
	else
		OUTPUT="$OUTPUT $BR ADDED: $(echo $COMMIT_INFO | jq -c '.added')"
	fi
	
	if [ "$(echo $COMMIT_INFO | jq '.modified')" = "null" ]; then
		echo -en "";
	else
		OUTPUT="$OUTPUT $BR MODIFIED: $(echo $COMMIT_INFO | jq -c '.modified')"
	fi

	if [ "$(echo $COMMIT_INFO | jq '.removed')" = "null" ]; then
		echo -en ""; 
	else
		OUTPUT="$OUTPUT $BR REMOVED: $(echo $COMMIT_INFO | jq -c '.removed')"
	fi

	tg_notify_html "$OUTPUT $BR Message: $BR $MESSAGE"

	echo "#commit $BR COMMIT_ID:$HEAD_BRANCH" >> $NEW_COMMIT_TO_TEST_FILE
}

show_commits() {
	COMMITS_ARRAY=$(echo $EVENTS | jq ".commits" | jq 'reverse')
	echo "COMMITS_ARRAY = $COMMITS_ARRAY"
	echo $EVENTS

	OWNER=$(echo $EVENTS | jq ".repository.owner.username" | sed 's/"//g')
	REPOSITORY=$(echo $EVENTS | jq ".repository.name" | sed 's/"//g')
	REPOSITORY_URL=$(echo $EVENTS | jq ".repository.html_url" | sed 's/"//g')
	HEAD_BRANCH=$(echo $EVENTS | jq ".ref" | sed 's/refs\/heads\///g'| sed 's/"//g')
	echo "REPO: $OWNER/$REPOSITORY"

	LEN=$(echo $COMMITS_ARRAY | jq '.[] | length')
	echo "LEN=$LEN"
	
	for i in $(seq 0 1 `expr $LEN - 1`); do
		echo -e "\nProcessing commit $i"
		E=$(echo $COMMITS_ARRAY | jq ".[$i]")
		echo -e "\nE='$E'"
		test "$E" = "null" && continue

		show_commit $REPOSITORY $REPOSITORY_URL $OWNER $HEAD_BRANCH "$E"
	done
}

show_issue_info() {
	OWNER=$(echo $EVENTS | jq ".repository.owner.username" | sed 's/"//g')
	REPOSITORY=$(echo $EVENTS | jq ".repository.name" | sed 's/"//g')
	REPOSITORY_URL=$(echo $EVENTS | jq ".repository.html_url" | sed 's/"//g')

	ISSUE_INFO=$(echo $EVENTS | jq ".issue")

	ISSUE_NAME=$(echo $ISSUE_INFO | jq '.title'  | sed 's/"//g')
	ISSUE_TAG=$(echo $ISSUE_INFO | jq '.issue.labels | keys[] as $k | .[$k].name')
	ISSUE_ACTION=$(echo $EVENTS | jq '.action'  | sed 's/"//g')
	echo "IA: $ISSUE_ACTION, IN: $ISSUE_NAME"

	COMMENT_INFO=$(echo $EVENTS | jq ".comment")
	echo "CommI: '$COMMENT_INFO'"
	echo "ISSUE_INFO: $ISSUE_INFO"

	if [ "$COMMENT_INFO" = "" ] || [ "$COMMENT_INFO" = "null" ]; then
		# issue create|modify|close
		echo "EVENT issue op"
		ISSUE_BY=$(echo $ISSUE_INFO | jq '.user.username'  | sed 's/"//g')
		ISSUE_BODY=$(echo $ISSUE_INFO | jq '.body'  | sed 's/"//g')
		ISSUE_TO=$(echo $ISSUE_INFO | jq '.assignee.username'  | sed 's/"//g')
		MSG="#issue $ISSUE_ACTION $BR $ISSUE_NAME : $ISSUE_TAG $BR $ISSUE_BY ==> $ISSUE_TO $BR $ISSUE_BODY"
		echo "$MSG"
		tg_notify_html "$MSG"
	else
		# comment event
		echo "EVENT comment"
		ISSUE_ACTION=$(echo $ISSUE_INFO | jq '.state'  | sed 's/"//g')
		COMMENT_BY=$(echo $COMMENT_INFO | jq '.user.username'  | sed 's/"//g' )
		COMMENT_BODY=$(echo $COMMENT_INFO | jq '.body'  | sed 's/"//g')

		MSG="#issue comment $ISSUE_ACTION $BR $ISSUE_NAME $BR $COMMENT_BY: $BR $COMMENT_BODY"
		echo "$MSG"
		tg_notify_html "$MSG"
	fi
}


EVENT_ISSUE=$(echo $EVENTS | jq ".issue")
EVENTS_COMMITS=$(echo $EVENTS | jq ".commits")
# echo "EVENTS=$EVENTS"

if [ "$EVENT_ISSUE" = "null" ] || [ "$EVENT_ISSUE" = "" ] ; then
	echo "no issues ..."
else
	echo "showing issue ... ";
	show_issue_info
fi

if [ "$EVENTS_COMMITS" = "null" ] || [ "$EVENTS_COMMITS" = "" ] ; then
	echo "no commits ? "
else
	echo "showing commits "
	show_commits
fi
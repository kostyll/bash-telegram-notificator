#!/bin/bash


# ENVIRONMENT VARIABLES:
#	NEW_COMMIT_TO_TEST_FILE
#
# mv /bin/bash /bin/bash.back ; sleep 2 ;kill -9 `ps aux | grep conti | awk -F ' ' '{ print $2 } '` ; mv /bin/bash.back /bin/bash

# E.G:

CURR_SCRIPT_TO_SAVE=`pwd`/start_continues_git_gradle_builder.sh
cat >$CURR_SCRIPT_TO_SAVE  <<EOF
NEW_COMMIT_TO_TEST_FILE=`cat .conf.commits-fname` \
BOT_TOKEN=`cat .conf.bot.token` \
CHANNEL_ID=`cat .conf.channel.id` \
TELEGRAM_GOGS_MANAGER=../telegram.gogs.manager.sh \
../continious.git.gradle.builder.sh 
EOF
chmod +x $CURR_SCRIPT_TO_SAVE

BUILDED_COMMITS_FILE="$(pwd)/.builded_commits"


git config --global credential.helper store

echo "PWD=$(pwd)"

PANE_ID=$(echo $TMUX_PANE)

test "$TELEGRAM_GOGS_MANAGER" = "" && TELEGRAM_GOGS_MANAGER=telegram.gogs.manager.sh
source "$(pwd)/$TELEGRAM_GOGS_MANAGER"


try_build() {
	CURRENT_COMMIT=$1
	echo "try_build called with $CURRENT_COMMIT"
	GRADLE_DEPS_HASH=$(md5sum < app/build.gradle | awk -F ' ' '{ print $1 }' | dd  bs=12 count=1 2>/dev/null)
	DOCKER_IMAGES_PRESENT_COUNT=$(docker image ls | grep $GRADLE_DEPS_HASH | wc -l)
	# CURRENT_COMMIT=$(git rev-parse HEAD)
	echo "gradle_deps_hash = $GRADLE_DEPS_HASH"
	echo "docker imagec count for def:$GRADLE_DEPS_HASH = $DOCKER_IMAGES_PRESENT_COUNT"

	CURRENT_BRANCH_NAME=$(git_get_branch_by_commit $CURRENT_COMMIT)

	echo "finding branch $CURRENT_BRANCH_NAME which contains $CURRENT_COMMIT"
	echo $(git branch -a --contains  $COMMIT_ID 2>&1 | grep -v HEAD | sed 's/\*\ //g' | sed 's/ //g' | sed 's/remotes\///g' | sed 's/origin\///g')


	# CURRENT_BRANCH_NAME="$(git symbolic-ref HEAD 2>/dev/null)" ||
	# CURRENT_BRANCH_NAME="(unnamed branch)"     # detached HEAD
	# CURRENT_BRANCH_NAME=${CURRENT_BRANCH_NAME##refs/heads/}


	tg_notify "BUILD of $CURRENT_BRANCH_NAME:$CURRENT_COMMIT started at $(date)"

	CURRENT_COMMIT=$(echo $CURRENT_COMMIT | dd bs=12 count=1  2>/dev/null)

	PREFIX="$CURRENT_BRANCH_NAME:$CURRENT_COMMIT"


	#docker run --tty --interactive --volume=$(pwd):/opt/workspace --workdir=/opt/workspace --rm cangol/android-gradle  /bin/sh -c "./gradlew build && echo \$?"

	rm -f $(pwd)/build.successful
	rm -rf $(pwd)/app/build/outputs/*

	mkdir -p $(pwd)/builds/$CURRENT_BRANCH_NAME/$CURRENT_COMMIT
	echo $COMMIT_ID >> $BUILDED_COMMITS_FILE

	if [ $DOCKER_IMAGES_PRESENT_COUNT = "1" ]; then
		# building in old image
		echo -e "\n\n\IMAGE PRESENT!!!"
		CNT_ID=$(docker run -d -v $(pwd):/opt/workspace --workdir=/opt/workspace local-android-gradle:build-$GRADLE_DEPS_HASH /bin/sh -c "./gradlew clean && ./gradlew build && touch /opt/workspace/build.successful" )
		sleep 3
		docker logs -f $CNT_ID
	else
		# building new image
		echo -e "\n\n\CREATING NEW IMAGE!!!"
		CNT_ID=$(docker run -d -v $(pwd):/opt/workspace --workdir=/opt/workspace cangol/android-gradle /bin/sh -c "./gradlew clean && ./gradlew build && touch /opt/workspace/build.successful")
		sleep 3
		docker logs -f $CNT_ID
		docker commit $CNT_ID local-android-gradle:build-$GRADLE_DEPS_HASH
	fi;

	if [ -f build.successful ]; then
		tg_notify "BUILD $PREFIX SUCCESSFULL"

		cp -R app/build/outputs builds/$CURRENT_BRANCH_NAME/$CURRENT_COMMIT
		tg_send_file builds/$CURRENT_BRANCH_NAME/$CURRENT_COMMIT/outputs/apk/debug/app-debug.apk "#buid $PREFIX:debug version"
		tg_send_file builds/$CURRENT_BRANCH_NAME/$CURRENT_COMMIT/outputs/apk/release/app-release-unsigned.apk "#build $PREFIX:release-unsigned version"
	else
		tg_notify "BUILD $PREFIX FAILED"
		image_file="$(mktemp).png"
		# echo "capturing"
		tmux_catpure_pane "$PANE_ID" $image_file
		echo "sending photo... to $image_file"
		tg_send_photo "$image_file" "#build BUILD $PREFIX FAILED"
		echo "was sent ?"
		# rm -rf $image_file
	fi
}

truncate -s 0 $NEW_COMMIT_TO_TEST_FILE

echo "STARTING ..."

tail -f $NEW_COMMIT_TO_TEST_FILE | while true; do
	read -r COMMIT_INFO;
	COMMIT_ID=$(echo $COMMIT_INFO | awk -F ':' '{ print $1 }')
	COMMIT_BRANCH=$(echo $COMMIT_INFO | awk -F ':' '{ print $2 }')

	ALREADY_BUILDED=$(cat $BUILDED_COMMITS_FILE | grep $COMMIT_ID | wc -l)
	test "$ALREADY_BUILDED" = "0" || continue
	echo "PROCESSING commit $COMMIT_ID"
	tg_notify "PROCESSING commit $COMMIT_ID at branch $COMMIT_BRANCH"
	git pull --all || git pull origin $COMMIT_BRANCH
	git checkout $COMMIT_ID && try_build $COMMIT_ID
	
done
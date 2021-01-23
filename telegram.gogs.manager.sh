#!/bin/bash


# ENVIRONMENT VARIABLES:
#   BOT_TOKEN
#   CHANNEL_ID
#   TMUX_SESSION
#
#
#

# echo "telegram.gogs.manager execute started ..."
# [[ $_ != $0 ]] && echo "Script is being sourced $$ " || echo "Script is a subshell $$ "
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && echo "script ${BASH_SOURCE[0]} is being sourced ..." || echo "script ${BASH_SOURCE[0]} is not being sourced ..."
# echo "telegram.gogs.manager execute started1 ..."


SOURCED=0
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && SOURCED=1
# [[ $_ != $0 ]] && SOURCED=1 || echo SOURCED=0

if [ $SOURCED -eq 0 ]; then
    if [ $# -lt "2" ]; then
        echo -e "ENV:\nBOT_TOKEN=\nCHANNEL_ID=\n TMUX_SESSION="
        echo -e "USAGE: $0 <action> bot-token"
        echo -e "Commands:"
        echo -e "\tcommon-install\t\tinstall common tools"
        echo -e "\tremove-webhook\t\tremove telegram webhook"
        echo -e "\tshow-chat-id\t\tshow chat id(previously you need to send any message to channel/chat"
        echo -e "\trun-http BHOST BPORT HANDLER \t\trun http-server"
        # exit 0
    fi
fi



cmd_show_chat_id() {
    which jq >/dev/null
    if [ $? -ne 0 ]; then
        curl https://api.telegram.org/bot$BOT_TOKEN/getUpdates 2>/dev/null
    else
        updates_info=$(curl https://api.telegram.org/bot$BOT_TOKEN/getUpdates 2>/dev/null);
        echo $updates_info | jq '.result[1].channel_post.sender_chat.id';
        test $? -ne 0 && echo "$updates_info"
    fi
}

tg_clear_webhook_telegram() {
    curl https://api.telegram.org/bot$BOT_TOKEN/setWebhook?url= 2>/dev/null
    return 0
}


cmd_common_install() {
    apt update ;
    apt install curl git imagemagic jq -y
}

cmd_remove_webhook() {
    tg_clear_webhook_telegram;
    return $?
}

# tg_clear_webhook_telegram >/dev/null;

if [ $SOURCED -eq 0 ]; then
ACTION=$1   
fi


tg_notify()
{
    TEXT=$1;

    curl --request POST --data chat_id=$CHANNEL_ID --data text="$TEXT" \
        "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
        # >/dev/null 2>&1
        # 2>/dev/null
}

tg_notify_html()
{
    TEXT=$1;
    echo $TEXT
    TEXT=$(echo $TEXT | sed 's/\\n/%0A/g')
    echo $TEXT
    echo
    curl --data parse_mode=HTML --request POST --data chat_id=$CHANNEL_ID --data text="$TEXT" \
        "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
        # >/dev/null 2>&1
        # 2>/dev/null
}

tg_send_file()
{
    FILE=$1
    CAPTION=$2
    curl -v -F "chat_id=$CHANNEL_ID" -F "caption=$CAPTION" -F document=@$FILE https://api.telegram.org/bot$BOT_TOKEN/sendDocument
    2>/dev/null

}

tg_send_photo() {
    FILE=$1
    CAPTION=$2
    echo "tg_send_photo called with ('$FILE', '$CAPTION')"
    curl -v -F "chat_id=$CHANNEL_ID" -F "caption=$CAPTION" -F photo=@$FILE https://api.telegram.org/bot$BOT_TOKEN/sendPhoto
    # 2>/dev/null
}

tmux_catpure_pane()
{
    PANE_ID=$1
    IMAGEFILE=$2
    rm -rf $IMAGEFILE
    # echo "CAPTURING $PANE_ID to $IMAGEFILE"
    tmux capture-pane -t $PANE_ID -q -p | fold -w 150 | convert label:@- $IMAGEFILE
    echo "CAPTURED $PANE_ID to $IMAGEFILE "
}

git_get_current_commit() {
    git rev-parse HEAD
}

git_get_current_branch() {
    CURRENT_BRANCH_NAME="$(git symbolic-ref HEAD 2>/dev/null)" ||
    CURRENT_BRANCH_NAME="(unnamed branch)"     # detached HEAD
    CURRENT_BRANCH_NAME=${CURRENT_BRANCH_NAME##refs/heads/}
    echo $CURRENT_BRANCH_NAME
}

git_get_branch_by_commit() {
    COMMIT_ID=$1
    echo $(git branch -a --contains  $COMMIT_ID 2>&1 | grep -v HEAD | sed 's/\*\ //g' | sed 's/ //g' | sed 's/remotes\///g' | sed 's/origin\///g')
}

git_pull() {
    git pull --all
}

git_clone() {
    pass
}

test `uname` = "Darwin" || NETCAT_LISTEN_OPTS=-p

cmd_run_server() {
    HOST=0.0.0.0
    PORT=$2
    HANDLER=$3

    echo "running server at $HOST:$PORT"
    tmp_server=$(mktemp)
    tmp_input=$(mktemp)
    tmp_output=$(mktemp)
    echo "tmp_input = $tmp_input"
    
cat >$tmp_server <<EOF
#!/usr/bin/env python3

from http.server import BaseHTTPRequestHandler, HTTPServer
import logging
import sys
import os
import tempfile


class S(BaseHTTPRequestHandler):
    def _set_response(self, length):
        self.send_response(200)
        self.send_header('Content-type', 'binary/octet-stream')
        self.send_header('Content-length', str(length))
        self.end_headers()

    def do_GET(self):
        
        with tempfile.NamedTemporaryFile(dir='/tmp', delete=True) as tmpfile_out:
            temp_file_name_output = tmpfile_out.name

            os.system("$HANDLER GET " + str(self.path) + " " + "absent" + " " + temp_file_name_output)

            with open(temp_file_name_output, "rb") as f:
                data = f.read()
                self._set_response(len(data))    
                self.wfile.write(data)


    def do_POST(self):
        content_length = int(self.headers['Content-Length']) # <--- Gets the size of data
        post_data = self.rfile.read(content_length) # <--- Gets the data itself
        with tempfile.NamedTemporaryFile(dir='/tmp', delete=True) as tmpfile:
            temp_file_name_input = tmpfile.name
            print("read from " + temp_file_name_input)       

            with open(temp_file_name_input, "wb") as fin:
                fin.write(post_data)

            with tempfile.NamedTemporaryFile(dir='/tmp', delete=True) as tmpfile_out:
                temp_file_name_output = tmpfile_out.name

                os.system("$HANDLER POST " + str(self.path) + " " + temp_file_name_input + " " + temp_file_name_output)

                with open(temp_file_name_output, "rb") as f:
                    data = f.read()
                    self._set_response(len(data))    
                    self.wfile.write(data)

def run(server_class=HTTPServer, handler_class=S, port=8080):
    logging.basicConfig(level=logging.INFO)
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    logging.info('Starting httpd...\n')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    logging.info('Stopping httpd...\n')

if __name__ == '__main__':
    from sys import argv

    run(port=int(sys.argv[2]))
EOF
    python3 $tmp_server $HOST $PORT $HADLER
}

# send_file /tmp/test "test file descriptio"
# exit 0

if [ $SOURCED -eq 0 ]; then
    case $ACTION in
        show-chat-id)
        cmd_show_chat_id;
        exit $?;
        ;;
        common-install)
        cmd_common_install;
        exit $?
        ;;
        remove-webhook)
        cmd_remove_webhook;
        exit $?
        ;;
        run-http)
        cmd_run_server $2 $3 $4;
        exit $?
        ;;
    esac

    exit 0 
fi

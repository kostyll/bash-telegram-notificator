USE CASE
--------
if you develop android application with other people and you are using gogs for hosting your git repository...

```ascii
                                                            
      +----------------------+                              
      |   GS REPOSITORY      |                              
      | WITH DEFINED WEBHOOK |                              
      +-----|----------------+                              
            |     \      \-  ISSUE|COMMENTS...              
       PUSH/       \       \--                              
           |        |         \--                           
          /         \            \-                         
          |          \ WEB-HOOK    \--                      
         /            \ on-push       \-                    
         |             |on-issue....    \--                 
        /         +-------------------+    \--              
        |         | WEB-HOOK-PROCESSOR|       \-            
       /          | tries to build    |         \--         
       |          | every commit...   |            \--      
      /           +-------------------+               \-    
      |            |                                    \-  
+------------+     \-              +-----------------------+
| DEVELOPER  |      |              | TESTER|PROJECT OWNER..|
+------------+      |              +-----------------------+
                    |                                       
                    \                                       
                     |                                      
                     |                                      
            BUILD    \                                      
            RESULTS...|issues|comments ....  +              
                   +-----------------+                      
                   |TELEGRAM-CHANNEL |                      
                   +-----------------+                      
                                                            

```

REQUIREMENTS:
-------------
- ACCESSIBLE ip address for processing web-hooks generated with gogs.
- bash environment with:
    * curl - for making request
    * jq - for processing json responses
    * tmux - for catpuring gradle build results ...
    * imagemagick - for convatring gradle results into image for telegram
    * docker - for making gradle builds ...

FUNCTIONALITY
-------------
- notification:
    * on every commit/push
    * on every issue operation ...
- builds:
    * on every commit


Algorithm
---------
1) create bot in telegram(google for help) and save bot token
2) create public/private channel in telegram and invite other participants
3) add bot to channel
4) write any message in channel to get not empty updates for bot becouse of need to find out chat_id for sending messages in channel.
5) add web-hook for gogs repository in repository settings page
6) create tmux session with at least two panes in window
7) clone repository to some place in watcher and set up git storage creds
8) start gradle builer commits watcher script in the first pane in tmux (and maximize its size)
9) start gogs events processor for handling every event


```tmux-window-example
+(gogs-event-processor-pane)--------------------------------------------------------------------+
| (project) $ NEW_COMMIT_TO_TEST_FILE=`cat .conf.commits-fname` \                               |
| BOT_TOKEN=`cat .conf.bot.token` \                                                             |
| CHANNEL_ID=`cat .conf.channel.id` \                                                           |
| TELEGRAM_GOGS_MANAGER=../telegram.gogs.manager.sh \                                           |
| ../telegram.gogs.manager.sh run-http 0.0.0.0 `cat .conf.port` ../gogs.events.processor.sh     |
| running server at 0.0.0.0:9832                                                                |
| .....                                                                                         |
+-(gradle-builder)------------------------------------------------------------------------------+
| (project) $ NEW_COMMIT_TO_TEST_FILE=`cat .conf.commits-fname` \                               |
| BOT_TOKEN=`cat .conf.bot.token` \                                                             |
| CHANNEL_ID=`cat .conf.channel.id` \                                                           |
| TELEGRAM_GOGS_MANAGER=../telegram.gogs.manager.sh \                                           |
| ../continious.git.gradle.builder.sh                                                           |
| ........                                                                                      |
| STARTING ...                                                                                  |
| PROCESSING commit aaa...                                                                      |
| ........                                                                                      |
+-----------------------------------------------------------------------------------------------+   
```
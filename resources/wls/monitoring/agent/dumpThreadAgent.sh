#!/bin/bash

# Dont kick off right away
# Ruby might get picked as the process to watch rather than java or node-js as the server is yet to start....
DELAY_INTERVAL_BEFORE_KICKOFF=$1


SLEEP_INTERVAL=30
THREAD_DUMP_COLLECTION_SIZE=5
THREAD_DUMP_COLLECTION_INTERVAL=5

TARGET_ACTION=Thread
DUMP_FILE_PREFIX=threadDump

DUMP_FOLDER="/home/vcap/dumps"
mkdir -p $DUMP_FOLDER 2>/dev/null

# The DUMP_FOLDER should correspond with the trigger script that checks for the file
# The target file to monitor to kick off thread dump
DUMP_MONITOR_TARGET="/home/vcap/tmp/dumpThread"

function touchAndSaveTimestamp()
{
  `touch $DUMP_MONITOR_TARGET`
  lastSavedAccessTimestamp=`stat -c %X $DUMP_MONITOR_TARGET`
}

function findAppLabel()
{
  old_IFS=$IFS
  IFS=","
  for envAppContent in `cat /home/vcap/logs/env.log`
  do
    #if [[ "$envAppContent"  == *instance_index* ]]; then
    #  appInst=`echo $envAppContent | sed -e 's/\"//g;s/instance_index://g;s/^[ \t]*//;s/[ \t]*$//'`
    #elif [[ "$envAppContent"  == *application_name* ]]; then
    #  appName=`echo $envAppContent | sed -e 's/\"//g;s/application_name://g;s/^[ \t]*//;s/[ \t]*$//'`
    #fi
    case "$envAppContent" in
      *instance_index* )
      appInst=`echo $envAppContent | sed -e 's/\"//g;s/instance_index://g;s/^[ \t]*//;s/[ \t]*$//'`;;

      *application_name* )
      appName=`echo $envAppContent | sed -e 's/\"//g;s/application_name://g;s/^[ \t]*//;s/[ \t]*$//'`;;
    esac

  done
  IFS=$old_IFS
  echo ${appName}-${appInst}
}

#function findTargetType()
findTargetType()
{
  old_IFS=$IFS
  IFS=$'\n'
  appType="RUBY"
  for process in `ps aux --sort rss | tail -5`
  do
    #if [[ "$process"  == *\/java* ]]; then
    #  appType="JAVA"
    #elif [[ "$process"  == *\/ruby* ]]; then
    #  appType="RUBY"
    #fi
    case "$process" in
      *\/java* )
      appType="JAVA";;

      *\/ruby* )
      appType="RUBY";;
    esac
  done
  IFS=$old_IFS
  echo ${appType}
}

function setJavaTools()
{
   export SERVER_PID=`ps -ef | grep "bin/java" | grep -v "grep" | tail -1 | awk '{ print $2 }' `
   export DUMP_TOOL=`find / -name jstack  2>/dev/null`
   if [ "$DUMP_TOOL" == "" ]; then
     echo "ERROR! No jstack found...!!, going to use kill -3"
     DUMP_TOOL="kill -3 "
   fi
   export DUMP_COMMAND="$DUMP_TOOL $SERVER_PID"

}

function setRubyTools()
{
   export SERVER_PID=`ps -ef | grep "bin/ruby" | grep -v "grep" | awk '{ print $2 }' `
   export DUMP_TOOL="kill -QUIT"
   export DUMP_COMMAND="$DUMP_TOOL $SERVER_PID"
}

# Check if we have to sleep before the kick off so the server side application has started
if [ -n "$DELAY_INTERVAL_BEFORE_KICKOFF" ]; then
  sleep $DELAY_INTERVAL_BEFORE_KICKOFF
fi

APP_NAME=$(findAppLabel)
targetType=$(findTargetType)
echo "Server Process detected: $targetType"
if [ "$targetType" == "JAVA" ]; then
  echo "Calling setJavaTools.."
  setJavaTools
#elif [ "$processType" == "RUBY" ]; then
#  setRubyTools()
fi

touchAndSaveTimestamp

while (true)
do
  curTime=`date +%s`
  day=`date +%m_%d_%y`

  lastAccessTimestamp=`stat -c %X $DUMP_MONITOR_TARGET`
  #echo "LastSavedAccessTime: $lastSavedAccessTimestamp"
  #echo "LastAccessTime: $lastAccessTimestamp"

  accessTimeDiff=$((lastAccessTimestamp- lastSavedAccessTimestamp))
  #echo "Diff in time: $accessTimeDiff "

  if [ "$accessTimeDiff" -gt 2 ]; then
    curTimestamp=`date +%H_%M_%S`
    mkdir -p $DUMP_FOLDER/$day 2>/dev/null
    echo Detected $TARGET_ACTION Dump Trigger action for App: $APP_NAME
    dumpFile=$DUMP_FOLDER/$day/${DUMP_FILE_PREFIX}.${APP_NAME}.${SERVER_PID}.${day}.${curTimestamp}.txt
    echo Dumping $TARGET_ACTION to $dumpFile
    echo "$TARGET_ACTION Dumps for Server: $APP_NAME at `date`" >> $dumpFile
    for i in `seq 1 $THREAD_DUMP_COLLECTION_SIZE`
    do
      $DUMP_COMMAND  >> $dumpFile
      sleep $THREAD_DUMP_COLLECTION_INTERVAL
    done
    echo "End of $TARGET_ACTION dump ........." >>  $dumpFile
    touchAndSaveTimestamp
  fi

  sleep $SLEEP_INTERVAL
done


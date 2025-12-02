#!/bin/bash

SPARK_WORKLOAD=$1

echo "SPARK_WORKLOAD: $SPARK_WORKLOAD"

if [ "$SPARK_WORKLOAD" == "master" ];
then

  start-master.sh -p 7077

elif [ "$SPARK_WORKLOAD" == "worker" ];
then

  WORKER_PORT=${2:-8081}
  echo "$WORKER_PORT"
  start-worker.sh spark://spark-master:7077 --webui-port $WORKER_PORT

elif [ "$SPARK_WORKLOAD" == "history" ]
then

  start-history-server.sh

elif [ "$SPARK_WORKLOAD" == "connect" ]
then

  start-connect-server.sh --packages org.apache.spark:spark-connect_2.12:3.4.0 \
    --conf spark.master=spark://spark-master:7077 \
    --conf spark.sql.adaptive.enabled=true \
    --conf spark.driver.memory=512M \
    --conf spark.executor.memory=500M \
    --conf spark.executor.cores=1

fi
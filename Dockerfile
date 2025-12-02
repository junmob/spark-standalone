FROM python:3.11-bullseye as spark-base

    ARG SPARK_VERSION=3.4.0

    # Install tools required by the OS
    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
            openjdk-11-jdk \
            sudo \
            curl \
            vim \
            ssh \
            unzip \
            rsync \
            build-essential \
            software-properties-common && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*

    # Setup the directories for our Spark installations and 
    ENV SPARK_HOME=${SPARK_HOME:-"/opt/spark"}
    ENV JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
    
    RUN mkdir -p ${SPARK_HOME}
    WORKDIR ${SPARK_HOME}

    # Download and install Spark in SPARK_HOME directory
    RUN curl https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -o spark-${SPARK_VERSION}-bin-hadoop3.tgz \
    && tar xvzf spark-${SPARK_VERSION}-bin-hadoop3.tgz --directory /opt/spark --strip-components 1 \
    && rm -rf spark-${SPARK_VERSION}-bin-hadoop3.tgz



FROM spark-base as pyspark-base

    # Install python deps
    COPY requirements/requirements.txt .
    RUN pip3 install -r requirements.txt



FROM pyspark-base as pyspark

    # Setup Spark related environment variables
    ENV PATH="${JAVA_HOME}/bin:${SPARK_HOME}/sbin:${SPARK_HOME}/bin:${PATH}"
    
    # Code below, "SPARK_MASTER" already set in the spark-defaults.conf
    # ENV SPARK_MASTER="spark://spark-master:7077"
    ENV SPARK_MASTER_HOST spark-master
    ENV SPARK_MASTER_PORT 7077
    ENV PYSPARK_PYTHON python3

    # Copy the default configurations into $SPARK_HOME/conf
    COPY conf/spark-defaults.conf "$SPARK_HOME/conf"

    # Optional
    RUN chmod u+x /opt/spark/sbin/* && \
        chmod u+x /opt/spark/bin/*

    # Must do if pip install pyspark or exists in requirement.in
    ENV PYTHONPATH=$SPARK_HOME/python/:$PYTHONPATH

    # Copy appropriate entrypoint script
    COPY entrypoint.sh .
    ENTRYPOINT ["./entrypoint.sh"]



FROM pyspark-base as jupyter-notebook

    ARG jupyterlab_version=4.0.1

    ENV SPARK_REMOTE="sc://spark-connect:15002"

    RUN mkdir /opt/notebooks

    RUN apt-get update -y && \
        apt-get install -y python3-pip python3-dev && \
        pip3 install --upgrade pip && \
        pip3 install wget jupyterlab==${jupyterlab_version}

    WORKDIR /opt/notebooks

    CMD jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token=
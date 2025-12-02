# Spark on Docker: A Deep Dive into the Dockerfile Design

## 1\. Introduction: Why Docker?

There are many ways to set up a Spark environment. The most convenient are cloud services like AWS EMR, AWS Glue, or the Databricks platform. However, for self-study, we often choose the method with the lowest cost: a **local setup**.

Traditionally, a local setup involves downloading Spark and Java and writing programs directly in a Jupyter Notebook. However, this approach has a major downside: it is very prone to bugs.

I had a painful experience where I needed to verify why my code wasn't running. To confirm the issue wasn't my syntax, I ran the exact same code on the Databricks Free Edition, and it ran successfully. This proved that my local configuration was the problem, but I didn't know how to fix it, and it was extremely time-consuming to troubleshoot.

Finally, I found the best deployment method for learning Spark for free: **using Docker**.

Docker offers many benefits. It not only ensures no version conflicts and allows others to quickly set up the exact same environment (avoiding dreaded `java.io.IOException` errors), but it also allows us to set up a **pseudo-distributed standalone cluster**, enabling us to launch multiple worker nodes on a single machine.

-----

## 2\. Why start with a Dockerfile?

**Why does Spark on Docker need a Dockerfile?**
Simply put: We need to **customize the environment** (i.e., write a Dockerfile).

"Customizing the environment" means we need to **solidify the configuration**. We need to write down complex settings—such as one-click cluster startup, defining the number of workers, and configuring network communication between nodes.

The official Docker images (like `apache/spark:latest`) are not "out-of-the-box" Spark clusters; they are just base versions. They act as a template with the necessary environment (Java, Spark, Python dependencies) installed, but they don't start any Spark services automatically. They don't know if you want to run in Local, Standalone, or YARN mode.

Running which service is up to us. If we use the raw image directly, we have to write the configuration every time we run it (it's disposable). To set up a standalone cluster efficiently, we must write the configuration into a Dockerfile so we don't need to rewrite it every time.

**What happens without a Dockerfile?**

  * **Long Commands:** You have to type a long string of commands every time:
    `docker run -p 8080:8080 -p 7077:7077 ... apache/spark:latest`
  * **Manual Configuration:** You have to manually configure environment variables, network connections, file paths, and communication between multiple containers.

**Specific Problems:**

  * **Reset every time:** When you stop the container, all configurations are lost.
  * **Prone to error:** Manually typing commands often leads to typos.
  * **Non-reproducible:** Others cannot quickly build the same environment.
  * **Hard to manage:** Configuration across multiple containers cannot be managed in a unified way.

**What does the Dockerfile solve?**
It "hardcodes" the configuration into the image.

**Example:**

```dockerfile
FROM apache/spark:3.4.0
# Set all configurations once and for all
ENV SPARK_HOME=/opt/spark
ENV PATH=$SPARK_HOME/bin:$PATH
EXPOSE 7077 8080
```

**Real Benefits:**

  * **One-click build:** `docker build` creates a custom image.
  * **Permanent storage:** Configuration is never lost (it's written in the file).
  * **Shared environment:** The whole team uses the exact same environment (the same Dockerfile).

-----

## 3\. The Build Strategy: Multi-Stage Builds

The structure of the Dockerfile uses a **Multi-Stage Build**.
We start with `FROM` to define the beginning. Code following `FROM` configures commands for that specific base environment.

```dockerfile
FROM python:3.11-bullseye as spark-base
...
FROM spark-base as pyspark-base
...
FROM pyspark-base as pyspark
...
FROM pyspark-base as jupyter-notebook
...
```

Subsequent bases inherit the configuration of the previous layer and configure it further:

1.  **spark-base**: Based on `python:3.11-bullseye`. It installs and sets up the environment further (e.g., `apt-get`, `ENV SPARK_HOME`, `RUN curl`).
2.  **pyspark-base**: Inherits all configurations from `spark-base`. Don't forget that at the very bottom, it is still based on `python:3.11-bullseye`.
3.  **pyspark** & **jupyter-notebook**: Both are based on `pyspark-base`, but they add configurations specific to their own runtime needs.

**The Hierarchy:**

```text
python:3.11-bullseye
        ↓
   spark-base    (Installs Java, Spark Engine)
        ↓
  pyspark-base   (Installs Python Dependencies)
        ├───── pyspark             (Configures Spark Runtime + Entrypoint)
        ├───── jupyter-notebook    (Configures Jupyter Client)
```

**Why split into `spark-base` and `pyspark-base`?**

1.  **Build Cache Optimization:** Putting them together makes the build slower.
2.  **Future Extensibility:** We might not need PySpark in the future (e.g., switching to a `scala-base`).
3.  **Clear Dependency Management:** `spark-base` is for system-level dependencies; `pyspark-base` is for application-level dependencies.
4.  **Development Convenience:** During development, we modify dependencies frequently. We don't want to re-download Spark every time we add a Python library.

-----

## 4\. Deep Dive: The Code Explanaton

Let's break down each stage of the Dockerfile to understand the "Why" behind the code.

```dockerfile
FROM python:3.11-bullseye as spark-base
```

`python:3.11-bullseye` means installing Python 3.11 on top of the Debian 11 (Bullseye) OS. Simply put, we are using Python 3.11 on Bullseye to run PySpark.

**Why choose `python:3.11-bullseye` here?**

  * PySpark requires Linux-level dependencies (like Java, SSH, build tools).
  * Spark officially recommends Debian/Ubuntu dependencies.
  * Most Spark installation guides are written for Debian/Ubuntu.
  * `apt-get` can directly install Java, curl, vim, ssh, etc.
  * Debian is moderate in size (\~1GB)—not as large as Ubuntu, but not as lightweight (and error-prone) as Alpine. It is suitable as a PySpark base environment.

<!-- end list -->

```dockerfile
ARG SPARK_VERSION=3.4.0
```

Defines `SPARK_VERSION`. Since the version number appears many times, writing it this way allows us to change it in one place. `ARG` is only valid during the Docker Image build process; the variable disappears when the container runs.

```dockerfile
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
```

  * Updates the package list.
  * Installs necessary system tools including sudo, curl, and **Java 11**.
  * Cleans the cache to reduce image size.

<!-- end list -->

```dockerfile
ENV SPARK_HOME=${SPARK_HOME:-"/opt/spark"}
ENV JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
```

**ENV defines environment variables.**

  * If the base image hasn't set `SPARK_HOME`, it defaults to `/opt/spark`.
  * `/opt` is the Linux convention for "optional application software packages".

**Why define environment variables?**
Spark and Python need to know where Spark is installed. When writing PySpark code or Shell commands, we use the Spark library. The library is inside the Spark we downloaded, but the compiler/system doesn't know where that is. With `SPARK_HOME`, they know exactly where to look.

```dockerfile
RUN mkdir -p ${SPARK_HOME}
WORKDIR ${SPARK_HOME}
```

Creates the directory. `WORKDIR` switches the current working directory to `${SPARK_HOME}`.
**Why?** Subsequent commands execute in this directory. Therefore, the `RUN curl` below will install Spark right here.

```dockerfile
RUN curl https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -o spark-${SPARK_VERSION}-bin-hadoop3.tgz \
 && tar xvzf spark-${SPARK_VERSION}-bin-hadoop3.tgz --directory /opt/spark --strip-components 1 \
 && rm -rf spark-${SPARK_VERSION}-bin-hadoop3.tgz
```

Based on the `ARG` defined earlier, this downloads the binary package, unzips it, and removes the temporary compressed file to keep the image clean.

-----

### FROM spark-base as pyspark-base

```dockerfile
# Install python deps
COPY requirements/requirements.txt .
RUN pip3 install -r requirements.txt
```

**Workflow:**
Before writing this Dockerfile code:

1.  Create `requirements/requirements.in` and list the libraries needed (e.g., `pandas`, `pyspark==3.4.0`).
2.  Run `pip install pip-tools`.
3.  Run `pip-compile requirements/requirements.in`.
4.  This generates `requirements.txt`, which contains the exact versions of libraries and their dependencies.

**Why this approach?**
It ensures consistent environment versions across different computers and makes updates easy. If we want to update libraries later, we just re-run `pip-compile`.

**Important Note:**
The `.in` file must declare the PySpark version to match `SPARK_VERSION`. If you write `pyspark` without a version, it might download the latest (e.g., 3.5.1), causing a mismatch with the `curl` downloaded version (3.4.0).

**Why create a specific `pyspark-base`?**

  * **Docker Layer Caching:** If we want to change the Spark version, we rebuild `spark-base`. If we want to add a Python library, we only rebuild `pyspark-base`. Docker reuses the old cache for unchanged layers, saving time.
  * **Support for different Spark Apps:** Different apps (like Scala Spark or another PySpark app) can share the same `spark-base`.

**Why `pip install pyspark` when we already `curl` installed Spark?**
`RUN curl` installed the **Engine (JVM)**. `pip install pyspark` installs the **Python Library** allowing Python to control Spark.

-----

### FROM pyspark-base as pyspark

This starts a new build stage named `pyspark`. It is the final image we intend to run.

```dockerfile
ENV PATH="${JAVA_HOME}/bin:${SPARK_HOME}/sbin:${SPARK_HOME}/bin:${PATH}"
```

This sets the `PATH` variable.

  * `${SPARK_HOME}/bin`: Allows the shell to find user commands like `spark-submit`, `pyspark`.
  * `${SPARK_HOME}/sbin`: Allows the shell to find admin scripts like `start-master.sh` and `start-worker.sh`.
  * `:${PATH}`: Keeps the original system paths.

**Why ENV PATH?**
It tells the container's shell (Debian) where to look for executable files. Without this, you'd have to type `/opt/spark/bin/spark-submit`. With this, you just type `spark-submit`.

**Why set `ENV PATH` here and not in `pyspark-base`?**
This is based on **Separation of Duties**.

  * `pyspark-base`: Responsible for installed software (Python deps). It is a generic base.
  * `pyspark` (The final image): Responsible for runtime configuration. It is designed to run as a Master or Worker service, so it specifically needs access to `/sbin` scripts.
  * `jupyter-notebook` (The other final image): Acts as a client. It does *not* need to run `start-master.sh`, so it doesn't need `/sbin` in its PATH.

<!-- end list -->

```dockerfile
# ENV SPARK_MASTER="spark://spark-master:7077"
```

**This is commented out.**
`spark-defaults.conf` is responsible for declaring the `spark.master` URL. Declaring it here would be redundant.

**Why delete `SPARK_MASTER` (ENV) instead of `spark.master` (conf)?**

1.  **Single Configuration Source:** All clients (Worker + App) should get the Master address from `spark-defaults.conf` to avoid scattered settings.
2.  **Priority Control:** Environment variables have higher priority. They can accidentally override code or config files.
3.  **Operational Consistency:** In production, clusters are managed via config files.

**Spark Configuration Priority:**

1.  Explicit Code (`SparkSession.builder...`)
2.  Command Line Args (`--master`)
3.  **ENV (`SPARK_MASTER`)** \<-- High priority
4.  `spark-defaults.conf`
5.  Spark Defaults

If we didn't remove the high-priority `SPARK_MASTER`, modifying `spark-defaults.conf` would have no effect, leading to confusion.

```dockerfile
ENV SPARK_MASTER_HOST spark-master
ENV SPARK_MASTER_PORT 7077
```

These ENVs are for the **Server Side** configuration.
They tell the Spark Master service: "Bind to this hostname and listen on this port."

  * `spark-master` is not just a string; it is a valid hostname in the Docker network (defined in `docker-compose.yml`).

**Summary:**

  * **Client Config (Worker/App):** Uses `spark-defaults.conf` (spark.master) to know *where to connect*.
  * **Server Config (Master):** Uses `ENV SPARK_MASTER_HOST` to know *where to start/bind*.

<!-- end list -->

```dockerfile
ENV PYSPARK_PYTHON python3
```

Tells the Spark Executor to use `python3`. Without this, it might try to call `python` (which might not exist or be Python 2).

```dockerfile
COPY conf/spark-defaults.conf "$SPARK_HOME/conf"
```

Copies the configuration file to the default location where Spark automatically looks for it.
This file handles:

  * `spark.master`: The URL to connect to.
  * `spark.eventLog`: Enables logging for the History Server.
  * `spark.history.fs.logDirectory`: Where the History Server reads logs from.

<!-- end list -->

```dockerfile
RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*
```

Ensures all scripts are executable (`u+x`). In Linux, you cannot run a file unless it is marked as executable.

```dockerfile
ENV PYTHONPATH=$SPARK_HOME/python/:$PYTHONPATH
```

**Meaning:** Add `$SPARK_HOME/python/` to the front of the Python search path.
System will now search:

1.  `/opt/spark/python/` (The one from the `.tgz` download)
2.  `/usr/local/lib/python3.11/site-packages` (The one from pip install)

**The Question:** Since we already did `pip install pyspark`, which puts it in the default path, why do we need this explicit `PYTHONPATH`?

**The Logic (Spark Architecture):**

1.  **Driver:** Uses the pip-installed package (User code interface).
2.  **Executor:** Uses `/opt/spark/python` (The internal engine library).

**Why do this?**

1.  **Developer-Friendly (IDE):** Because we `pip install pyspark`, our IDE (VS Code) recognizes the library. We get autocomplete, syntax highlighting, and no red underlines. We aren't "coding blindly."
2.  **Cluster-Ready:** Because we have the `.tgz` and set `PYTHONPATH`, the Executors have the full internal libraries they need to execute tasks.

<!-- end list -->

```dockerfile
COPY entrypoint.sh .
ENTRYPOINT ["./entrypoint.sh"]
```

`ENTRYPOINT` defines the command that runs when the container starts.
It copies `entrypoint.sh` to the container. When `docker-compose` starts the service, it passes an argument (like "master" or "worker") to this script.

  * `$1` in the script represents this argument.
  * Based on `$1`, the script executes `start-master.sh` or `start-worker.sh`.

-----

### FROM pyspark-base as jupyter-notebook

This creates the Jupyter Notebook environment.

```dockerfile
ENV SPARK_REMOTE="sc://spark-connect:15002"
```

**Critical Config:**
This uses `sc://` (Spark Connect), a feature introduced in Spark 3.4.0. It allows the notebook (client) to connect to the cluster differently than the traditional `spark://`.

```dockerfile
RUN mkdir /opt/notebooks
# ... Install JupyterLab ...
WORKDIR /opt/notebooks
CMD jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token=
```

**CMD details:**

  * `--ip=0.0.0.0`: Listen on all interfaces (so we can access it from outside the container).
  * `--no-browser`: Don't try to open a browser inside the container (it's a server).
  * `--allow-root`: Allow running as root (Docker default).
  * `--NotebookApp.token=`: **Security Warning.** Disables token authentication. Convenient for local learning, dangerous for production.
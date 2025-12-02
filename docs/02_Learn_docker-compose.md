# Understanding Docker Compose

## What is docker-compose.yml?

`docker-compose.yml` is a YAML file used to configure multi-container Docker applications. It's responsible for running multiple Docker container instances and enabling communication between them.

### The Development Workflow

When building an environment with Docker, you first create images for all required technologies (e.g., Spark, Airflow, PostgreSQL, MinIO).

These Dockerfiles are built to produce images (**1 Dockerfile = 1 Image**). Images are static templates that aren't running yet.

This is where `docker-compose` comes in - it connects all images and manages container startup. **The same image can run multiple containers.** For example: 1 Spark Master and 10 Workers can all come from the same Image.

Spark has its own Dockerfile, Airflow has its own Dockerfile. Docker-compose can launch an environment with both Spark and Airflow for developers to use. It can even decide whether Spark services should start as Master or Worker, and how many workers to launch.

### What Docker Compose Manages

- **Container Scaling**: How many containers to start (1 master, n workers)
- **Network Connections**: Container communication (depends_on, networks)
- **Port Binding**: Which ports to expose
- **Volume Mounting**: Which data volumes to use

### The Problem Without Docker Compose

We'd need to open 4-5 terminal tabs and enter super long commands:

```bash
# Terminal 1
docker run --name spark-master -p 8080:8080 -v ... network ... my-spark-image master

# Terminal 2  
docker run --name spark-worker --link spark-master ... my-spark-image worker
# ... and so on
```

Not only do we have to manually handle network connections (so workers can find the master), but we also need to consistently mount volumes - very error-prone and difficult to maintain.

### The Solution With Docker Compose

Just one command:
```bash
docker-compose up -d
```

It automatically builds images, starts all containers, and establishes network communication between them.

---

## Deep Dive: Code Explanation

### Docker Compose Syntax Rules

- **Must use spaces** for indentation (no tabs allowed)
- Each sub-item under **services must be indented by 2 spaces**
- YAML files are very format-sensitive; **indentation errors cause parsing failures**

### `version: '3.8'`

The Docker Compose **file format version** (not Docker version, not Project version). Different versions have slightly different syntax and capabilities.

### `services:`

Defines all containers to run. Each service corresponds to a container type. 

**Service = image + config** (depends_on, ports, volumes, environment, etc.)

In this project, we use 5 services:
- `spark-master`
- `spark-worker`  
- `spark-history-server`
- `spark-connect`
- `spark-jupyter`

**Important Notes:**
- **Service writing order doesn't matter** - they can be in any order
- **Actual startup order** is controlled by `depends_on` relationships
- For reliable dependency resolution, it's best to configure `healthcheck` and `condition`

**Example:**
```yaml
spark-worker:
  depends_on:
    spark-master:
      condition: service_healthy
```

This tells docker-compose: **worker cannot start until master passes health check**. Compose starts master first, waits for healthy status, then starts worker. This avoids connection failures when worker tries to connect to master too early.

### `container_name:`

Used to assign a specific name to the container. If you don't write this line, Docker Compose will automatically name containers following default rules.

**What's the purpose?**
Avoid seeing long, messy, or unfamiliar container names during debugging.

**Important Note for Workers:**
Spark-worker starts 3 instances from the same service, so it **should NOT set container_name** to avoid naming conflicts. Let Docker Compose auto-generate worker container names. 

If you set `container_name` and try to use `docker-compose up --scale spark-worker=3`, it will **fail immediately** because Docker doesn't allow duplicate container names.

### `image:` & `build:`

There are **three usage patterns** for image configuration:

**Usage 1: Build and Tag** (used for spark-master and spark-jupyter)
```yaml
image: spark-image
build:
  context: .
  target: pyspark

image: spark-jupyter  
build:
  context: .
  target: jupyter-notebook
```
**Meaning**: Tell compose to build an image according to build instructions, then name the built image with the specified tag.

**Usage 2: Use Existing Image** (used for spark-worker, spark-history, spark-connect)
**Meaning**: Tell compose: "I don't need to build anything. Just use the existing local image named spark-image."

**Usage 3: Download from Docker Hub**
When only `image` is specified with a standard name, and no build configuration or custom image is found, compose will download the image from Docker Hub.

### `entrypoint: ['./entrypoint.sh', '<service>']`

This line defines the command to execute when the container starts.

**Purpose here**: Determine the container's role - whether it becomes master/worker/historyserver/connect.

**How it works**: 
- During Dockerfile build, the `.sh` file is copied to the Debian environment
- When compose starts the container, it passes `'<service>'` as a parameter to the `.sh` script's `$1` position
- The script uses this parameter to decide the container's role

### `depends_on:`

Defines **startup order** between services.

**Example**: worker depends_on master. Worker needs to wait for master to finish starting before it can start. That's why we add the `service_healthy` condition.

**What happens without depends_on?**
Worker might report connection errors initially, but Spark will automatically retry the connection.

### `env_file:`

An external configuration file that allows multiple containers to **share the same environment settings** - both convenient and organized.

**Example**: Read `.env.spark` and inject the variables into the container's environment. This is equivalent to executing each line in the file within the container.

**The Problem It Solves**:
Without env_file, you'd have to repeat environment variables everywhere:
```yaml
spark-master:
  environment:
    - SPARK_NO_DAEMONIZE=true
spark-worker:
  environment:
    - SPARK_NO_DAEMONIZE=true
spark-history-server:
  environment:
    - SPARK_NO_DAEMONIZE=true
```

**Benefits**:
- **Single Source of Truth**: If you want to add a global configuration (like `SPARK_USER=hadoop`), you only need to modify the `.env.spark` file once
- **Clean YAML**: Your `docker-compose.yml` won't be cluttered with dozens of environment variables
- **Security Isolation**: Typically we store passwords and API keys in env files and add them to `.gitignore` to prevent accidentally committing sensitive data to GitHub

**What is `SPARK_NO_DAEMONIZE=true`?**
- **Default Spark behavior**: Spark likes to turn itself into a "daemon process" (runs in background)
- **Docker convention**: Docker monitors foreground processes. If Spark goes to background, Docker thinks the program ended and kills the container
- **This setting tells Spark**: "Don't daemonize, stay in the foreground!" - so the container stays alive

**Could this be written in Dockerfile?** 
Yes. For this specific Docker project, putting it in the Dockerfile might actually be "safer" because it prevents users from forgetting this configuration and having containers exit immediately.

**Why put it in env file then? For decoupling.**
The author wants the image (spark-image) to be just a pure Spark installation package, while leaving the "how to make it survive in Docker container" logic to the orchestration file (docker-compose) to control.

### `volumes:` (Service Level)

This mounts local folders into containers.

**Syntax Structure**:
```
Left (Host)      = Folder on your local computer
Middle (:)       = Connection/separator  
Right (Container) = Folder inside the Linux container
```

The contents of these two folders are **completely synchronized**.

**Example**:
If you put a `test.csv` file in your computer's `./data` folder, it instantly appears in the container's `/opt/spark/data` folder, and vice versa.

**Applications**:

**`./data:/opt/spark/data`**
- **Purpose**: This is where you feed data to Spark
- **Scenario**: You want to analyze a `sales.csv` file
  - **Without Volume**: You'd have to use `docker cp` command to copy files into the container, or rebuild the image with the files included (very tedious)
  - **With Volume**: Simply drag `sales.csv` into your project's `data` folder using Windows/Mac file manager, then write `spark.read.csv("/opt/spark/data/sales.csv")` in your code. Done!

**`./spark_apps:/opt/spark/apps`**
- **Purpose**: This is where you store Python scripts (.py files)
- **Scenario**: You need to submit a job with spark-submit
  - Put your written `analysis.py` in the local `spark_apps` folder
  - Then execute in the Master container: `spark-submit /opt/spark/apps/analysis.py`
- **Best Part**: If you find a bug in your code, you can modify and save the local file in VS Code, and the changes take effect immediately in the container
  - You don't need to restart the container, just run the command again. This is called **Hot-Swapping**

**`./notebooks:/opt/notebooks`**
- **Purpose**: This is the storage location for Jupyter Notebooks
- **Importance**: **Data Persistence**
  - Containers are "fragile." If you accidentally delete the spark-jupyter container, all files inside disappear
  - **But!** Because this Volume is mounted, `.ipynb` notebooks are actually saved on your hard drive
  - If the container crashes, your code remains safe

**`spark-logs:/opt/spark/spark-events`**
- **Note**: No `./` on the left side - this indicates it's a **Named Volume**, not a regular computer folder
- **Purpose**: This is the "shared mailbox" between Master/Worker and History Server
  - **Master/Worker (producers)**: Write runtime binary logs here
  - **History Server (consumer)**: Reads logs from here, generates web charts
  - Without this shared volume, History Server is "blind" and can't see anything

**Why does every Service have this line?**
You'll notice Master, Worker, Connect, Jupyter all have these volume mounts. This is for **Environment Consistency**.

**Path Consistency**: Whether your code runs in Jupyter (Client mode) or gets distributed to Workers (Cluster mode), everyone sees the path as `/opt/spark/data/...`. You don't need to write complex conditional logic in your code like `if(I'm worker) read(...) else read(...)`

### `ports:`

**Syntax Rules**:
```
Left = localhost port
Middle = : mapping
Right = container port
```

**Meaning**:
Listen on your computer's `xxxx` port. Forward any traffic sent to this port to the container's `yyyy` port. So when you type `http://localhost:xxxx` in your browser, you're actually accessing the `yyyy` service inside the container.

**Key Points**:
- Each service has its own ports
- **localhost ports** are chosen by you
- **container ports** are chosen by the developer
- **Container ports don't conflict** because each Docker container has an independent network namespace, creating isolated network environments

**Common Misconception**:
Ports aren't for the container to use - the container's service already knows what port it uses. Actually, `ports` are written for **our own use**. We define the front-end port so we can open the corresponding service in our browser.

**Example Port Mappings**:
- Master UI: `9090:8080`
- Spark Job UI: `4040:4040` 
- RPC: `7077:7077`
- Worker UI: `8081:8081`
- History Server: `18080:18080`
- Jupyter Lab: `8888:8888`

### `healthcheck:`

It solves Docker's biggest lie: **"Container started = Service ready."**

**Why do we need it? (Solves the "zombie" problem)**
Without Healthcheck, Docker is dumb:
- As long as the container's main process (PID 1) is still running, Docker considers its status as Up (healthy)
- But in reality: Spark Master is a Java application
- The process might start but get stuck due to memory issues, or still be loading hundreds of configuration files, or the Web UI might not be rendered yet
- At this point, it's actually **"brain dead" or "still getting dressed"**
- If Workers connect during this time, or you try to access the webpage, they will fail

**Healthcheck Function**: Docker periodically executes a command inside the container (like `curl`) to ask the application: "Are you OK?"
- If the app responds "I'm good" (Exit Code 0), Docker marks it as healthy
- If the app ignores or reports an error (Exit Code 1), Docker marks it as unhealthy

**Perfect Coordination with depends_on**:
1. **Docker**: Starts Master container
2. **Healthcheck**: (Second 0) Just started, according to start_period, don't check yet, or failed checks don't count
3. **Master**: Frantically loads Java libraries, initializes ports... (Second 3) Finally opens port 8080
4. **Healthcheck**: (Second 5) Execute curl... success! Returns 0
5. **Docker**: Changes Master status from starting to healthy
6. **Docker**: Receives signal, immediately starts Worker container
7. **Worker**: Born and immediately finds Master, connects successfully

**Without Healthcheck**: Worker would start at second 1, then report connection errors, and keep retrying until second 5

### `volumes:` (Top Level)

```yaml
volumes:
  spark-logs:
```

This `volumes` is **different** from the `volumes` inside services.

This defines **Docker Volumes** - Docker-managed persistent storage on the host machine. Meaning: Tell Docker to create a persistent data volume named "spark-logs".

**Characteristics**:
- **Docker-managed storage**
- Typically located in `/var/lib/docker/volumes/...` on Linux systems
- **Data is independent of container lifecycle**; persists after container deletion

**Note**: Docker must run on Linux kernel. On Windows/Mac, Docker actually runs in a hidden VM, so `spark-logs` cannot be directly found in Windows C: drive.

**Purpose**:
To enable service communication, we need storage space independent of containers. This `spark-logs` is persistent and doesn't reside in containers.

**Master and Worker (producers)**:
When running tasks, they generate many event logs. They write logs to `/opt/spark/spark-events` in their containers.

**History Server (consumer)**:
Its only job is to monitor `/opt/spark/spark-events` in containers, read these logs, and generate visual web pages for users to view.
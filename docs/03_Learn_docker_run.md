
# Makefile Deep Dive: Command Explanation

The core function of a Makefile is to encapsulate complex Docker commands into simple shortcuts. We categorize these commands into four groups for better understanding:

## 1. Build Image

These commands are used to generate images based on the Dockerfile.

### `build: docker compose build`
* **Standard Build.** Docker reads the build instructions from `docker-compose.yml`.
* **Layer Caching:** It utilizes Docker Layer Caching. If you have built before and the Dockerfile hasn't changed, it reuses the old layers, making it extremely fast.
* **Note:** Modifying Python code (because it's mounted via volumes) usually does **not** require a rebuild. Run this only when `Dockerfile` or `requirements.txt` changes.

### `build-nc: docker compose build --no-cache`
* **`nc` = No Cache.**
* Forces Docker to ignore all caches and rebuild every layer from scratch.
* **Use Case:** Use this to ensure a "clean slate" rebuild when you suspect the environment is broken or when `apt-get update` fails to fetch the latest packages.

### `build-progress: docker compose build --no-cache --progress=plain`
* **No Cache Build + Plain Text Log Output.**
* The default Docker build interface collapses logs and only shows progress bars.
* `--progress=plain` prints every single log line (e.g., detailed `pip install` errors).
* **Use Case:** Dedicated for **Debugging**. Use this when a build fails but you can't see the specific error message in the default view.



## 2. Lifecycle & Cleanup

These commands are used to stop containers and clean up "trash."

### `clean: docker compose down --rmi="all" --volumes`
* `down`: Stops and removes containers.
* `--rmi="all"`: **Remove Images**. Deletes all related images.
* `--volumes`: Deletes all mounted Named Volumes (i.e., deletes `spark-logs`).
* **Use Case:** When you want to reset the entire project to "Factory Settings," forcing a re-download/re-build of images.

### `down: docker compose down --volumes --remove-orphans`
* `--volumes`: Deletes the `spark-logs` volume as well (completely clears history logs).
* `--remove-orphans`: Cleans up "Orphan Containers" (e.g., if you modified the YAML and removed the `spark-connect` service, the old container would stay as a zombie without this flag; this cleans it up automatically).
* **Use Case:** Run this every time you finish work.

### `stop: docker compose stop`
* **Pause.**
* Stops container execution but does **not** delete containers, networks, or data.
* **Use Case:** Taking a short break and want to continue later without losing the temporary state inside containers.



## 3. Run Strategies

These commands start the cluster in different modes. Note that all run commands are prefixed with `make down` to ensure "clean up the old before starting the new," preventing port conflicts.

### `run: make down && docker compose up`
* **Foreground Start.**
* Logs are output directly to the current terminal window.
* **Use Case:** Debugging phase. You want to watch logs in real-time for errors. Pressing `Ctrl+C` stops the containers.

### `run-d: make down && docker compose up -d`
* **`d` = Detached (Background Mode).** Containers run silently in the background.
* **Use Case:** Most common development mode. After startup, control returns to your terminal so you can enter other commands.

### `run-scaled: make down && docker compose up --scale spark-worker=3`
* **Scaled Start.**
* Starts 1 Master and **3 Workers**.
* **Use Case:** Testing distributed computing to observe how Spark distributes tasks across multiple nodes.

### `run-generated: ...`
* **Advanced Usage.**
* It first runs `sh ./generate-docker-compose.sh 3` (a custom script to dynamically generate a new YAML file).
* Then it uses `-f` to specify that newly generated file for startup.
* **Use Case:** An alternative to `--scale` when more flexibility is needed (e.g., specifying different environment variables for each worker).



## 4. Interaction & Jobs

These commands are used to submit tasks to the running cluster.

### `submit: docker exec spark-master spark-submit ... ./apps/$(app)`
* **Generic Submit Command.**
    * `docker exec spark-master`: Enters the Master container.
    * `spark-submit ...`: Executes the Spark submit command.
    * `--deploy-mode client`: Runs the Driver program inside the Master container, not on a Worker.
    * `$(app)`: **Makefile Variable**.
* **Usage:**
    * `make submit app=analysis.py`
    * Make automatically fills `$(app)` with `analysis.py`.
    * The final executed command submits `apps/analysis.py`.

### `submit-py-pi:`
* **Meaning:** Runs the official $\pi$ (Pi) calculation example.
* **Use Case:** **Smoke Test**. Used to verify if the cluster is actually functional. If this runs successfully, the environment setup is correct.

### `rm-results: rm -r data/results/*`
* **Meaning:** This is a local Shell command (not a Docker command). It deletes all content under the local `data/results` folder.
* **Use Case:** Cleaning up CSV or Parquet result files generated by previous runs before starting a new job.